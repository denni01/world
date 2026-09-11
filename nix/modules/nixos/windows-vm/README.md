# Windows 11 with a passed-through 3090

A disposable Windows guest that owns `0000:01:00.0` (top slot) outright, for
games and Windows-only software. Everything except the disk image and what is
installed inside Windows comes from this directory.

Gaming and LLM inference are mutually exclusive by design — that assumption is
what lets the guest take a whole CCD and a whole GPU without negotiating.

```
sudo virsh start win11 && looking-glass-client
sudo virsh shutdown win11
```

## Why it fits this machine

The desktop already runs on the Raphael iGPU (`desktop.nix`), so neither 3090 is
claimed by the compositor — the hard prerequisite, already met. Each card sits
alone in its IOMMU group (14 and 16) with only its own HDMI-audio function, so
there is no ACS override and no group to break up. IOMMU is on from BIOS; the
kernel params in `default.nix` only make that durable.

Both cards run at PCIe x8 — the CPU bifurcates x8/x8 with both slots populated.
At 4K that costs 1-2% against x16.

## The choices worth knowing

**`nvidia_modeset` is refused outright, not merely blacklisted.** This is the
one thing that makes the handover survivable once a cable is in the passed card.
When modeset tears down a display head it calls `RmSetELDAudioCaps` to write ELD
to the display's audio device — and that is `0000:01:00.1`, which is on
vfio-pci. The nvidia core then oopses in `nv_audio_dynamic_power`, killing the
caller with IRQs disabled: an unreapable task, a wedged libvirtd, and a reboot.
`RmSetELDAudioCaps` is the only issuer of that RM control and it lives in
`nvidia-modeset`, so with the module absent the path is unreachable. Compute
needs only `nvidia` and `nvidia_uvm`.

`boot.blacklistedKernelModules` is *not* sufficient — it only stops udev
autoloading by alias, and `nvidia-modprobe` loads modeset explicitly on behalf
of `nvidia-smi` and CUDA. `boot.nix` therefore uses `install ... /bin/true` via
`boot.extraModprobeConfig`, and the `prepare` hook refuses to start the domain
if the module is loaded anyway.

Symptom to recognise: a `virsh start` that never returns, with
`nvidia-persistenced` in `D` state and `nvidia_modeset` in `lsmod`. Do not retry
— check `sudo cat /proc/<pid>/stack` for `nvkms_close`.

**The desktop session is pinned to mesa so nothing opens the compute cards.**
The second prerequisite. Unbinding a GPU the
nvidia driver still has a client on logs `NVRM: Attempting to remove device ...
with non-zero usage count`, and that message is not a failure — it is
`nv_pci_remove_helper` announcing that it is about to block. It then spins in a
500 ms poll loop until the count reaches zero, holding locks, which presents as
an unkillable D-state recoverable only by a hard reset. The count is incremented
per open of `/dev/nvidiaN`, so the only thing that ever holds it is a userspace
fd.

The holder here was the desktop. `services.xserver.videoDrivers = [ "nvidia" ]`
installs `10_nvidia.json` into `glvnd/egl_vendor.d`, GLVND enumerates vendors in
filename order, and `10_` outranks `50_mesa.json` — so every EGL client on the
session bound NVIDIA EGL and opened both 3090s, even though the compositor runs
on the iGPU. `walker` is the one that stays resident. `desktop.nix` therefore
sets `__EGL_VENDOR_LIBRARY_FILENAMES`, `__GLX_VENDOR_LIBRARY_NAME` and
`VK_LOADER_DRIVERS_DISABLE` whenever the display is not an NVIDIA card. CUDA does
not go through GLVND, so inference is unaffected.

Worth knowing when debugging this: the fd count moves on its own as clients come
and go, so a one-shot `lsof`/`fuser` check lands in a gap and reports clean.
Count holders, do not spot-check them:

```sh
for p in /proc/[0-9]*; do ls -l $p/fd 2>/dev/null | grep -q /dev/nvidia && cat $p/comm; done
```

**The nvidia stack is unloaded before the handover, not just stopped.** With the
session off the cards this succeeds, and it is the guarantee that no client can
appear between the check and libvirt's unbind. The `prepare` hook unloads the
stack and refuses to start the domain if `nvidia` is still loaded — failing safe
instead of deadlocking. Unloading is only available because the compositor is on
the iGPU; on a single-GPU host it would mean killing the display manager.

The cost is that **both** 3090s are offline while the guest runs — `nvidia-smi`
does not work at all — which is the trade that keeps inference on the full 48 GB
pair the rest of the time.

`modesetting.enable = false` and the `nvidia_drm` / `nvidia_modeset` blacklist in
`boot.nix` are housekeeping for compute-only cards, not part of the fix — neither
was ever the reference, and the blacklist does not in fact stop the NVIDIA GL
stack pulling `nvidia_modeset` back in.

**Binding is dynamic, not boot-time.** Both cards report `10de:2204`, so
`vfio-pci.ids=` cannot tell them apart, and binding at boot would cost the host a
card permanently. `<hostdev managed='yes'>` makes libvirt do the unbind at start
and the rebind at shutdown, so both cards are ordinary CUDA devices whenever the
VM is down.

**16 vCPUs = all of CCD1.** Physical cores 8-15 plus their SMT siblings, exposed
as 8 cores x 2 threads, which keeps the guest inside one 32 MiB L3 with no
Infinity Fabric hops. QEMU's emulator and I/O threads go on CCD0 so they cannot
steal from a vCPU. `<vcpusched fifo>` stops the host scheduler preempting a vCPU
mid-frame.

**Host isolation is dynamic too.** The hook sets `AllowedCPUs` on the host slices
for as long as the guest runs, rather than surrendering half the machine to
`isolcpus` on a box that mostly does LLM work.

**Display: Looking Glass, with a DisplayPort cable as the fallback.** Run DP from
the passed 3090 to the monitor's spare input. Day to day the guest appears in a
Hyprland window and the host keyboard and mouse just work; switching the monitor
to DP gives a zero-overhead direct view. The cable also gives the guest a real 4K
EDID, so no dummy plug, and it is how you see the Windows installer before
Looking Glass exists.

**The GPU's HDMI audio is pinned to vfio-pci at boot**, by
`vfio-bind-gpu-audio.service` and by PCI address — `03:00.1` has the same device
ID and stays with the host. PipeWire otherwise enumerates it as
`alsa_card.pci-0000_01_00.1` and holds it open, and because it shares IOMMU group
14 with the GPU it has to be passed too: libvirt's detach then blocks forever,
deadlocking libvirtd with the GPU already unbound and no vfio group created. Its
`<hostdev>` is `managed='no'` for the same reason — letting libvirt restore it to
`snd_hda_intel` on shutdown would recreate the problem on the next start.

**Secure Boot is enforcing, not just available.** The firmware is named
explicitly instead of using libvirt's `firmware='efi'` autoselection, which only
sees QEMU's bundled edk2 — that has secure-boot capable code but an *unenrolled*
vars template, so Secure Boot would report off. `OVMFFull`'s `OVMF_VARS.ms.fd`
carries the Microsoft keys. Anti-cheat increasingly checks for this, and the
nvram at `/var/lib/libvirt/qemu/nvram/win11_VARS.fd` survives rebuilds.

**Shared memory is `/dev/shm`, not `kvmfr`.** `kvmfr` saves one memcpy per frame
but is an out-of-tree module against a pinned 7.2 kernel — the same fragility
that already forces a hand-pinned NVIDIA driver. Upgrade only if measurements
justify it.

Deliberately not done: `pcie_acs_override` (groups are already clean, and it is a
security hole for no gain), `allow_unsafe_interrupts` (AMD-Vi remaps interrupts),
`isolcpus`/`nohz_full`, and any new flake input — a generated XML plus one
activation unit covers it.

The 32 GiB of 1 GiB hugepages is reserved at boot and unavailable to the host
even when the VM is down. 1 GiB pages cannot be allocated reliably later, so it
is static or nothing; drop the three `hugepages` kernel params if the RAM is
missed more than the determinism is wanted.

## First-time setup

The subvolume, the image and Windows itself are one-time manual steps.

```sh
sudo btrfs subvolume create /mnt/btrfs/vms
sudo nixos-rebuild switch --flake ~/Developer/world/nix#proart && sudo reboot
```

After the reboot, check `lsattr -d /var/lib/libvirt/images` shows `C` *before*
creating the image — `+C` is inherited by new files only:

```sh
truncate -s 512G /var/lib/libvirt/images/win11.raw
```

Sparse, so it consumes only what Windows writes, and `discard='unmap'` lets TRIM
give space back.

Then: run the DP cable, set `installIso` in `domain.nix` to the Windows 11 ISO
(this also swaps in an emulated display and attaches the virtio-win drivers),
rebuild, `virsh start win11`, and switch the monitor to DP. The installer shows
no disks until you load the virtio-blk driver from the second CD.

Inside Windows, in order: NVIDIA driver, then the Looking Glass **host**
application — it must be the same release as `looking-glass-client` — then the
IVSHMEM driver from that same download. Set `installIso` back to `null` and
rebuild.

## Checks

```sh
grep HugePages_Total /proc/meminfo                # 32
lspci -nnk -s 01:00.0 | grep 'Kernel driver'      # vfio-pci while up, nvidia after
systemctl show system.slice -p AllowedCPUs        # 0-7,16-23 while up, 0-31 after
sudo virsh vcpupin win11                          # 0->8, 1->24, 2->9, 3->25, ...
nvidia-smi -q -d POWER | grep 'Power Limit'       # 280 W back on both after release
```

In the guest: Task Manager should show 8 cores / 16 logical processors and 32 GB,
GPU-Z an RTX 3090 on bus 01 at x8.

## When it breaks

**Editing `hook.nix` requires `sudo systemctl restart libvirtd`.** A
`nixos-rebuild switch` is not enough and fails silently. The NixOS libvirtd
module sets `restartIfChanged = false` so a rebuild never disturbs a running
guest, but the hook symlinks under `/var/lib/libvirt/hooks/qemu.d/` are written
by libvirtd's start-time script — so the old hook stays live and the symlink
mtime stops tracking your rebuilds. Check with:

```sh
readlink -f /var/lib/libvirt/hooks/qemu.d/win11   # vs. the current eval
```

A refused start with `still has compute clients` means something holds the card —
usually `llama-swap`; the hook stops it, so check for a stray CUDA process.

A refused start with `nvidia is still loaded` means a userspace client has an fd
on `/dev/nvidia*` and the module would not unload. This is the failure the whole
design guards against, and it fails safe — do **not** force the unbind past it.
List the holders with the loop above; if the culprit is a desktop app, the mesa
pinning in `desktop.nix` is not reaching it. Check with
`systemctl --user show-environment | grep EGL_VENDOR`, which is empty in any
session started before that setting landed — log out and back in.

A wedged card after a crash: `sudo virsh destroy win11`, then
`echo 1 | sudo tee /sys/bus/pci/devices/0000:01:00.0/remove && echo 1 | sudo tee /sys/bus/pci/rescan`.

No output on DP during install usually means the monitor drops HPD on its
inactive input — a DP dummy plug fixes it, or use `virt-viewer` against the
emulated display that `installIso` already adds.

A host that boots without a desktop is almost certainly one of the kernel params;
pick the previous generation in systemd-boot, as the top-level README's Recovery
section describes.
