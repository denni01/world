# nix

NixOS configuration for the `proart` machine.

Goal: All configuration is a flake for reproducibility and recoverability.

**If something is broken and you need to get back in, jump to [Recovery](#recovery).**

## Layout

```
flake.nix                 nixpkgs 26.05 + unstable (LLM only), home-manager, xremap, disko
hosts/proart/
  default.nix             host identity: hostname, locale, user, stateVersion
  hardware.nix            btrfs subvolume mounts, kernel modules, swap
modules/nixos/
  boot.nix                systemd-boot, kernel 7.2 (pinned), firmware
  filesystems.nix         btrbk snapshots, monthly scrub
  fonts.nix               Berkeley Mono + fallbacks
  networking.nix          NetworkManager, Bluetooth, localsend, rpfilter
  nvidia.nix              2x RTX 3090 (compute-only), pinned driver, power caps
  desktop.nix             Hyprland/UWSM on the iGPU, greetd, PipeWire, launchers
  input.nix               hid_apple, xremap macOS keybindings
  llm.nix                 llama.cpp + llama-swap on the 3090s, manual start
  docker.nix
  sandbox/                opencode in a container; egress allowlist, no NAT
  performance.nix         sysctl, governor, tmpfs, nix build parallelism
home/
  default.nix             user packages, dotfile symlinks, git
  dotfiles/               PLAIN FILES — edited directly, not generated
pkgs/
  mt6639-bt-firmware.nix  Bluetooth blob, committed
scripts/                  config validation and restore drill
```

## Rebuilding

```sh
sudo nixos-rebuild switch --flake ~/Developer/world/nix#proart   # or: nrs
sudo nixos-rebuild boot   --flake ~/Developer/world/nix#proart   # or: nrb
```

Use `boot` + reboot for kernel, GPU-driver or filesystem changes; `switch` for
everything else.

### Config Validation

Validate desktop config before rebooting into it.

```sh
Hyprland --verify-config
```

## Dotfiles

`home/dotfiles/` holds live config files which are symlinked into `~/.config`.

## Manual Setup

- Berkeley Mono Font
    - Stored in `fonts/berkeley-mono`
- MT6639 Bluetooth Blob for Motherboard Chipset

## Hardware notes

- **Kernel is pinned to 7.2.** The onboard MediaTek MT7927 WiFi has no driver
  before it. Do not drop to an older kernel expecting WiFi to survive.
- **The NVIDIA driver is pinned to 595.91.07.** 26.05 ships 595.71.05, which
  does not compile against 7.2 — Linux removed `strncpy` and the driver still
  calls it. `modules/nixos/nvidia.nix` carries removal instructions.
- **DRM card numbers move.** The NVIDIA card has been card0, then card1, then
  card1 again with the iGPU at card2; adding the second 3090 renumbered things
  again and shifted the iGPU from `79:00.0` to `7a:00.0`. Never address a GPU by
  card number; and `AQ_DRM_DEVICES` cannot take a symlink, so a by-path value
  silently yields no GPU at all. `desktop.nix` therefore resolves the by-path
  symlink to a real `cardN` at session start, via `/etc/xdg/uwsm/env-hyprland`.
- **Two 3090s, both headless.** `01:00.0` (top slot, 420 W SKU) and `03:00.0`
  (bottom slot, 350 W SKU) are reserved for compute; the Raphael iGPU at
  `7a:00.0` drives the display. Both cards are capped to 280 W with a 1695 MHz SM
  ceiling — they are 2.5-slot coolers in adjacent slots. The bottom card gets the
  heavier model: the top card's intake fans face the backplate below them.
- **Each 3090 is alone in its IOMMU group** (14 and 16), with only its own
  HDMI-audio function. VFIO passthrough needs no ACS override — and the host
  already drives neither card, which is the other prerequisite.
- **`/var/lib/docker` is a nodatacow subvolume** and is excluded from snapshots.

## Bootstrapping a new machine

1. Boot the NixOS installer.
2. Partition to match `hosts/proart/hardware.nix` — or use `disko.nix` once
   written.
3. Clone this repo to `~/Developer/world/nix` (the path matters, see Dotfiles).
4. `nixos-install --flake <repo>/nix#proart`
5. Restore `home` and `persist` from btrbk; `nix` rebuilds itself from the flake.
6. Supply Berkeley Mono if wanted (see above).
7. Verify Pi-hole blocking loaded:
   `curl -s http://127.0.0.1:8080/api/info/ftl | grep -o '"gravity":[0-9-]*'`.
   A count of `-2` means the database is not attached.

## Local LLM

llama.cpp behind llama-swap on **http://127.0.0.1:8090** (8080 is pihole-web).
`modules/nixos/llm.nix`. **Manual start** — it holds ~40 GB of VRAM when running:

```
sudo systemctl start llama-swap
curl -s http://127.0.0.1:8090/v1/models | jq '.data[].id'
```

One model resident per card, no tensor split. `03:00.0` (bottom, cooler intake)
runs the primary; `01:00.0` runs the small model. Both stay loaded, so opencode's
`model`/`small_model` switch costs nothing.

`CUDA_DEVICE_ORDER=PCI_BUS_ID` is set on every model. Without it CUDA orders
devices by its own speed heuristic, not PCI order, and since the two 3090s are
different board SKUs a model silently lands on the wrong card.

**Two packages come from `nixpkgs-unstable`**, scoped in `llm.nix` and
`home/default.nix`: 26.05's llama-cpp is b9190, which predates the `qwen35`
architecture and a CUDA correctness fix — an older build runs at full speed and
emits *garbage*. Drop the input once 26.05's successor catches up.

CUDA is not in cache.nixos.org; `performance.nix` adds `cache.nixos-cuda.org`
(**not** the dead `cuda-maintainers.cachix.org`). llama-cpp itself still compiles
locally — tens of minutes.

### Before the first switch

The models subvolume is the one piece disko did not create, since it was added to
a live machine:

```
sudo btrfs subvolume create /mnt/btrfs/models
```

The mount is `nofail`, so skipping this will not break the boot — but the weights
then land on `rootfs` and get swept into hourly snapshots. Confirm with
`findmnt /var/lib/llm-models`.

Weights (world-readable; llama-swap is a `DynamicUser`):

```
hf download unsloth/Qwen3.8-27B-GGUF --include '*UD-Q4_K_XL*' \
  --local-dir /var/lib/llm-models/qwen3.8-27b
hf download unsloth/GLM-4.7-Flash-GGUF --include '*UD-Q4_K_XL*' \
  --local-dir /var/lib/llm-models/glm-4.7-flash
```

## Agent sandbox

opencode in a container that can reach llama-swap and an allowlisted slice of the
internet, and nothing else. `modules/nixos/sandbox/`.

```sh
opencode-sandbox                          # mounts $PWD at /workspace
opencode-sandbox ~/Developer/foo          # mounts that instead
opencode-sandbox ~/Developer/foo -- bash  # a shell, not opencode
```

The docker network is `--internal`, so there is no NAT and no route out; the
bridge gateway carries the only two things reachable, `172.28.0.1:8090`
(socket-proxied to llama-swap on loopback) and `:3128` (squid).

```sh
git worktree add ~/Developer/agent-x -b agent/x
opencode-sandbox ~/Developer/agent-x
cd ~/Developer/agent-x && git diff
```

The allowlist is `sandbox/allowlist.nix`, ~200 hosts vendored from [GitHub's
Copilot allowlist][https://docs.github.com/en/copilot/reference/copilot-allowlist-reference]; add a line and rebuild. It filters by host
only

> Note: `journalctl -u squid` shows `TCP_DENIED/403` when something is blocked.

## DNS

Pi-hole runs locally, bound to loopback only (`interface = "lo"`,
`listeningMode = "BIND"`), with `networking.nameservers = [ "127.0.0.1" "::1" ]`.
Dashboard: **http://pi.hole:8080/** (no login — see `modules/nixos/pihole.nix`).

**If `pihole-ftl` will not start, this machine has no DNS at all.** Recover with
`echo nameserver 1.1.1.1 > /etc/resolv.conf`, or boot an older generation.

## Snapshots

btrbk snapshots `rootfs`, `home` and `persist` hourly into `/mnt/btrfs/snapshots`,
kept `48h 14d 8w 6m`. Verify restorability with:

```sh
sudo bash scripts/snapshot-restore-test.sh
```

**These are local snapshots.** They protect against mistakes, not against the
disk failing. Adding an off-machine target is a `target` block in
`modules/nixos/filesystems.nix` — `ssh://host/path` or an external btrfs disk —
with no restructuring needed.

## Recovery

Reference card. Everything below assumes nothing about the machine being in a working state.

| | |
|---|---|
| Disk | `/dev/nvme0n1` (Samsung 990 PRO 4 TB) |
| btrfs | `/dev/nvme0n1p2`, partlabel `root`, UUID `49f65f6a-f464-4f23-b0e1-336131b10de3` |
| ESP | `/dev/nvme0n1p1`, partlabel `EFI`, UUID `BC7C-0B61`, vfat, 1 GiB |
| Swap | `/dev/nvme0n1p3`, partlabel `swap`, UUID `9568a369-3897-487d-9178-fceb06cc429e` |
| GPT backup | `/persist/gpt-backup.bin` — restore with `sgdisk --load-backup=` |
| Subvolumes | `rootfs` `home` `nix` `log` `docker` `models` `persist` `snapshots` |
| Flake | `~/Developer/world/nix#proart` |

The greeter offers a single session, `Hyprland (uwsm-managed)`. There is no fallback desktop
to select: the fallbacks are a TTY (`Ctrl+Alt+F2`) and an older generation at the boot menu.

**Every NixOS generation is self-contained**, including its initrd and the fstab inside it, which
is the property most of this relies on. Current generations mount by partition label; generations
from before that change mount by UUID. Both work, so rolling back across it is safe. The
UUIDs above are recorded for exactly that case — nothing in the config uses them now.

### Level 1 — bad rebuild, system still boots
```bash
sudo nixos-rebuild switch --rollback
```

### Level 2 — boots, but no desktop
`Ctrl+Alt+F2` for a TTY (TTYs are independent of the compositor and greeter), log in, then Level 1.
If greetd itself is looping: `sudo systemctl stop greetd` first.

### Level 3 — won't boot
Hold `Space` during boot to get the systemd-boot menu, pick an older generation. This is the
escape hatch for a broken kernel, a broken NVIDIA module, or a bad fstab.

### Level 4 — no generation boots; use a NixOS live USB
```bash
sudo mount -o subvol=rootfs /dev/nvme0n1p2 /mnt
sudo mount -o subvol=nix    /dev/nvme0n1p2 /mnt/nix
sudo mount -o subvol=home   /dev/nvme0n1p2 /mnt/home
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo nixos-enter --root /mnt
# then, inside:
nixos-rebuild switch --rollback
# or rebuild from the repo:
nixos-rebuild boot --flake /home/dennis/Developer/world/nix#proart
```

### Level 5 — roll the root filesystem back to a snapshot
btrbk snapshots are read-only; taking a snapshot *of* one (without `-r`) yields a writable
subvolume, which is what you want to boot from.
```bash
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt && cd /mnt
ls snapshots/                                   # pick a timestamp
sudo mv rootfs rootfs.broken
sudo btrfs subvolume snapshot snapshots/rootfs.YYYYMMDDTHHMM rootfs
# reboot; once satisfied:
sudo btrfs subvolume delete rootfs.broken
```
`/home` and `/persist` restore identically. Note this rolls back **state, not the ESP** — if the
snapshot predates a kernel change, boot the matching older generation as well.

### Level 6 — dead disk / new machine
Live USB, then:
```bash
sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko -- --mode destroy,format,mount \
  --flake /path/to/repo/nix#proart          # partitions + subvolumes from disko.nix
sudo nixos-install --flake /path/to/repo/nix#proart
```
Then restore `home` and `persist` from the btrbk target with `btrfs receive`. `nix` is not
restored — it rebuilds from the flake, which is the entire point of keeping it out of backups.


### The one thing that makes all of this work
The repo must be pushed to a remote, and the btrbk target must eventually be off this disk.
Local snapshots protect against mistakes; they do not protect against the 990 PRO dying.

