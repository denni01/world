# nix

NixOS configuration for `proart`. Everything the machine is, expressed as a
flake, so the install is reproducible and recoverable.

**If something is broken and you need to get back in, jump to [Recovery](#recovery).**
It covers everything from a bad rebuild through to a dead disk.

## Layout

```
flake.nix                 nixpkgs 26.05, home-manager, xremap
hosts/proart/
  default.nix             host identity: hostname, locale, user, stateVersion
  hardware.nix            btrfs subvolume mounts, kernel modules, swap
modules/nixos/
  boot.nix                systemd-boot, kernel 7.2 (pinned), firmware
  filesystems.nix         btrbk snapshots, monthly scrub
  fonts.nix               Berkeley Mono + fallbacks
  networking.nix          NetworkManager, Bluetooth, localsend, rpfilter
  nvidia.nix              RTX 3090, open modules, pinned driver
  desktop.nix             Hyprland/UWSM, greetd, PipeWire, launcher services
  input.nix               hid_apple, xremap macOS keybindings
  docker.nix
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

### Two traps worth knowing

**A flake only sees git-tracked files.** A new `.nix` file that has not been
`git add`ed is invisible to `nixos-rebuild`, which then fails with a confusing
"file not found". This is the single most common way to lose an hour.

**Validate the desktop config before rebooting into it.** Hyprland treats some
config errors as fatal and exits, and the greeter bounces you straight back with
the message on screen for about half a second:

```sh
Hyprland --verify-config
```

## Dotfiles

`home/dotfiles/` holds real config files, symlinked into `~/.config` via
`mkOutOfStoreSymlink` — they point at the **working tree**, so edits apply
immediately (`hyprctl reload`) with no rebuild. The trade-off is a baked
absolute path: this repo must be cloned to `~/Developer/world/nix` for the home
configuration to be complete.

Nix owns packages, services and session variables. It does not generate these
files.

## Things that need supplying by hand

Almost everything is committed, including the MT6639 Bluetooth blob — it is
redistributable firmware for hardware you own. Only Berkeley Mono is held out,
for licence reasons.

| What | Where | If missing |
|---|---|---|
| Berkeley Mono | `fonts/berkeley-mono/` | falls back to JetBrainsMono Nerd Font |
| nvim config | `home/dotfiles/nvim/` | placeholder only; port pending |

Berkeley Mono is gitignored, which also puts it out of reach of the flake: only
git-tracked files reach the store, so it could never be packaged as a system
font. It is installed as a *user* font through `mkOutOfStoreSymlink` instead,
read from the working tree at runtime — so dropping the files in place is enough,
with no rebuild.

That distinction matters for anything added later. **Build-time** assets must
physically reach the store, so they have to be tracked. **Runtime** assets behind
`mkOutOfStoreSymlink` never enter the store, so tracking them only decides
whether a fresh clone has them.

## Hardware notes

Facts that were expensive to learn and are easy to forget:

- **Kernel is pinned to 7.2.** The onboard MediaTek MT7927 WiFi has no driver
  before it. Do not drop to an older kernel expecting WiFi to survive.
- **The NVIDIA driver is pinned to 595.91.07.** 26.05 ships 595.71.05, which
  does not compile against 7.2 — Linux removed `strncpy` and the driver still
  calls it. `modules/nixos/nvidia.nix` carries removal instructions.
- **DRM card numbers move.** The NVIDIA card has been card0, then card1, then
  card1 again with the iGPU at card2. Never address a GPU by card number; and
  `AQ_DRM_DEVICES` cannot take a symlink, so a by-path value silently yields no
  GPU at all.
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
| Swap | `/dev/nvme0n1p3`, UUID `9568a369-3897-487d-9178-fceb06cc429e` (no partlabel) |
| Subvolumes | `rootfs` `home` `nix` `log` `docker` `persist` `snapshots` |
| Flake | `~/Developer/world/nix#proart` |

The greeter offers a single session, `Hyprland (uwsm-managed)`. There is no fallback desktop
to select: the fallbacks are a TTY (`Ctrl+Alt+F2`) and an older generation at the boot menu.

**Every NixOS generation is self-contained**, including its initrd and the fstab inside it, which
is the property most of this relies on. Current generations mount by partition label; generations
from before that change mount by UUID. Both work, so rolling back across it is safe.

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

