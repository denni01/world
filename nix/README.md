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
  tailscale.nix           tailnet membership + sshd bound to tailscale0 only
  workvm.nix              host side of the work VM; guest is hosts/workvm/
  performance.nix         sysctl, governor, tmpfs, nix build parallelism
hosts/workvm/
  default.nix             the work VM guest: PIA, DoT+DNSSEC, kill switch
  pia/                    PIA's OpenVPN profile, vendored
home/
  default.nix             user packages, dotfile symlinks, git
  webapps.nix             borderless Chromium apps as launcher entries
  webapp-icons/           icons for the above that no package already ships
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

### Neovim

`home/dotfiles/nvim/`, plain Lua on 0.12, plugins via lazy.nvim.

Servers, formatters and debug adapters come from Nix, not Mason — they sit in
`home.packages` and the Lua finds them on `$PATH`, so no store path is ever
written into a dotfile. `gcc` and `tree-sitter` are in that list because
nvim-treesitter compiles parsers locally and generates a few (typescript, tsx);
without them those files fail to open rather than degrading.

`lazy-lock.json` is committed and is the only thing pinning plugin versions.

Two spaces by default only — `.editorconfig` wins, then `guess-indent.nvim`,
then that. `:verbose set shiftwidth?` says which.

`:Theme` switches between melange, kanagawa and gruvbox (light and dark) and
persists the choice, so trying one is not a config edit. Your own is cheapest as
a kanagawa `overrides` table.

```sh
nvim --headless "+Lazy! sync" +qa      # after a fresh clone
nvim +checkhealth
```

## Manual Setup

Everything here is deliberately outside the flake, because the repo is public and
none of it can live in the world-readable store.

- Berkeley Mono Font
    - Stored in `fonts/berkeley-mono`
- MT6639 Bluetooth Blob for Motherboard Chipset
- `/persist/secrets/dennis-password` — `scripts/set-password.sh`
- Tailscale enrolment is `sudo tailscale up` — no secret. The **Disable key
  expiry** toggle in the admin console is the part that actually matters; see
  [Remote access](#remote-access)
- `/persist/secrets/workvm/pia-credentials` and the `microvms` subvolume — see
  [Work VM](#work-vm)
- The `vms` subvolume, the 512 GiB disk image, the DisplayPort cable and the
  Windows install itself — see [Windows VM](#windows-vm)

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
  already drives neither card, which is the other prerequisite. The top card is
  passed to the Windows guest; see Windows VM below.
- **Both 3090s run at PCIe x8** — the CPU bifurcates x8/x8 with both slots
  populated, and the root ports report `max_link_width=8`, so this is the wiring
  rather than a link that failed to train. Idle speed drops to 2.5 GT/s and
  climbs back to Gen 4 under load.
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

## Work VM

`modules/nixos/workvm.nix` (host), `hosts/workvm/default.nix` (guest). Headless
NixOS under QEMU via microvm.nix, egress through PIA and nothing else. Stronger
than `sandbox/`: separate kernel, no route to the LAN.

Not autostarted — it holds a VPN connection open.

```sh
sudo systemctl start microvm@workvm
ssh -p 2222 dennis@127.0.0.1     # forwarded, host loopback only
journalctl -u microvm@workvm     # the console; qemu runs -nographic
```

`nrs` rebuilds and restarts it; the guest needs nothing special.

What it demonstrates:

- **No path to the LAN or this host.** QEMU user-mode networking — no tap, no
  bridge, no forwarding — so this is structural, not a firewall rule.
- **No egress if the VPN drops.** nftables default-drops output. Two narrow
  clear-text exceptions: UDP 1197 to the endpoint's resolved addresses, and the
  one pre-tunnel lookup of that name.
- **One file channel**, `~/share` here, `/share` there. Credentials come in
  separately, on a read-only share, since anything in the VM can read `/share`.
- **DNS security, not filtering.** Strict DoT + DNSSEC to Quad9, which drops
  malicious domains. Pi-hole is the host's ad blocker and is unreachable here.

### Before the first start

```sh
sudo btrfs subvolume create /mnt/btrfs/microvms   # else images land on rootfs
                                                  # and btrbk snapshots them

sudo install -d -m 0700 /persist/secrets/workvm
sudo install -m 0400 -o root -g root /dev/stdin /persist/secrets/workvm/pia-credentials
# username line 1, password line 2, Ctrl-D
```

### Proving it works

From inside the guest — the `MUST fail` lines are the interesting ones:

```sh
curl -s https://ipinfo.io/ip         # a PIA exit address, not the ISP's
resolvectl query example.com         # "authenticated: yes"
dig +short @9.9.9.9 example.com      # MUST fail: plaintext 53 is dropped
ping -c1 192.168.1.1                 # MUST fail: no route to the LAN
ping -c1 192.168.1.173               # MUST fail: no route to this host
sudo systemctl stop openvpn-pia
curl -m5 https://example.com         # MUST fail: the kill switch
touch /share/hello                   # appears in ~/share on the host
```

Changing region moves two things together — the vendored `.ovpn` and
`piaEndpoint`/`piaPort` — because the kill switch permits exactly one host and
port. A mismatch fails closed. See `hosts/workvm/pia/README.md`.

## Windows VM

`modules/nixos/windows-vm/`. Windows 11 under libvirt with the top RTX 3090
passed through, for games and Windows-only software. Disposable — the disk image
and what is inside Windows are the only state.

Not autostarted, and mutually exclusive with `llama-swap`: the libvirt hook stops
inference and releases the card on the way in, and restores both on the way out.

```sh
sudo virsh start win11
looking-glass-client             # or $mod+W
sudo virsh shutdown win11
```

- **16 vCPUs pinned to CCD1** (cores 8-15 + siblings), so the guest sits inside
  one 32 MiB L3 with no Infinity Fabric hops. QEMU's own threads go on CCD0, and
  the hook fences the host onto CCD0 for as long as the guest runs.
- **32 GiB of 1 GiB hugepages**, reserved at boot — 1 GiB pages cannot be
  allocated reliably later, so the host loses that RAM even when the VM is down.
- **The GPU is bound dynamically.** Both cards report `10de:2204`, so
  `vfio-pci.ids=` cannot tell them apart; `managed='yes'` makes libvirt unbind
  and rebind around the domain instead. Both are ordinary CUDA devices when it
  is off.
- **Looking Glass for the display**, with a DisplayPort cable from the passed
  card to the monitor's spare input as the fallback and the guest's EDID source.

Setup, the disposable-image runbook and the recovery steps are in
`modules/nixos/windows-vm/README.md`.

## Remote access

`modules/nixos/tailscale.nix`. The tailnet is the only way in: sshd is bound to
`tailscale0`, so 22 is never open on the LAN. Trayscale (GTK4) runs as a user
service in waybar's tray.

```sh
ssh dennis@proart                 # from another tailnet device
tailscale status
```

### Setup, once

```sh
sudo tailscale up                 # opens a URL, log in
```

Then toggle **Disable key expiry** on `proart` in the admin console. That is what
decides whether the machine is reachable three weeks into a trip, and nothing
here can set it — two mechanisms, easily conflated:

| | expires | set where |
|---|---|---|
| Auth key | ≤ 90 days | at creation — **not used here** |
| Node key | 180 days | per-device toggle in the admin console |

```sh
tailscale status --json | jq .Self.KeyExpiry     # null == will not expire
```

No auth key: they provision machines you cannot sit in front of, and this one you
can. `--operator=dennis` is why the GUI and a bare `tailscale up` need no sudo.

### DNS

MagicDNS is declined so it cannot displace Pi-hole; `pihole.nix` forwards
`ts.net` and the 64 CGNAT reverse zones to `100.100.100.100` instead, so names
still resolve. It is `extraSetFlags`, not `extraUpFlags` — the latter only
applies when `authKeyFile` is set, so it would silently do nothing here.

```sh
dig +short pi.hole                # 127.0.0.1
dig +short <othernode>.ts.net     # forwarded through it
```

## Web apps

`home/webapps.nix`. `chromium --app=URL` gives a borderless window;
`xdg.desktopEntries` makes each a launcher entry that elephant indexes. YouTube
and the Pi-hole dashboard to start; adding one is four lines.

## DNS

MagicDNS is declined so it cannot rewrite `resolv.conf` and displace Pi-hole.
`.ts.net` names still resolve — `pihole.nix` conditionally forwards `ts.net` and
the 64 reverse zones of the 100.64.0.0/10 CGNAT range to `100.100.100.100`,
which tailscaled serves regardless of that flag.

This is `extraSetFlags`, **not** `extraUpFlags`: the latter is only applied when
`authKeyFile` is set, so with interactive enrolment it would silently do nothing
and MagicDNS would take the resolver back. `tailscaled-set.service` runs on every
boot, so it also survives a bare `tailscale up` later dropping the flag.

```sh
dig +short pi.hole                    # 127.0.0.1 — Pi-hole is still the resolver
dig +short <othernode>.ts.net         # forwarded through it
```

## Web apps

`home/webapps.nix`. `chromium --app=URL` gives a borderless window with no tab
strip or omnibox; `xdg.desktopEntries` turns each into a launcher entry. Each one
becomes a tiny derivation in `home.packages`, so it lands in
`/etc/profiles/per-user/dennis/share/applications` — already on `XDG_DATA_DIRS`,
which is what elephant indexes — and shows up in walker like any other
application. YouTube and the Pi-hole dashboard to start.

Adding one is four lines in that file. `--class` is set explicitly so
`hypr/windowrules.conf` can match on a readable name rather than on Chromium's
derived `chrome-youtube.com__-Default`.

## DNS

Pi-hole runs locally, bound to loopback only (`interface = "lo"`,
`listeningMode = "BIND"`), with `networking.nameservers = [ "127.0.0.1" "::1" ]`.
Dashboard: **http://pi.hole:8080/** (no login — see `modules/nixos/pihole.nix`),
or the launcher entry from `home/webapps.nix`.

Pi-hole is the only resolver, and Tailscale is configured not to change that:
`misc.dnsmasq_lines` forwards `ts.net` and the 64 reverse zones of 100.64.0.0/10
to `100.100.100.100` so MagicDNS works *through* it. The work VM does not use
Pi-hole at all and could not reach it — see [Work VM](#work-vm).

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
| Subvolumes | `rootfs` `home` `nix` `log` `docker` `models` `microvms` `persist` `snapshots` |
| Flake | `~/Developer/world/nix#proart` |
| Remote | Tailscale; sshd on `tailscale0` only. Key expiry disabled in the admin console, not here. |

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

