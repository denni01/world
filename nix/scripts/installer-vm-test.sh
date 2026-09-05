#!/usr/bin/env bash
# Boot the installer ISO in a VM against a blank disk, so the recovery path can
# be exercised without touching real hardware.
#
#   nix build .#installer
#   bash scripts/installer-vm-test.sh
#
# The VM deliberately mirrors proart where it matters:
#
#   * the disk is emulated as NVMe, so it appears as /dev/nvme0n1 — the device
#     hosts/proart/disko.nix names. A virtio disk would be /dev/vda and disko
#     would fail on a missing device.
#   * it boots UEFI via OVMF, because the installed system uses systemd-boot.
#     A BIOS VM boots the ISO fine but cannot boot the result, which is the
#     half of the test that matters.
#
# The disk image is sparse: it reports 260G but only occupies what is written.
# Delete it to start over — the script never reuses a dirty image silently.
#
#   bash scripts/installer-vm-test.sh --installed
#
# boots the same disk with no ISO attached, which is how you check the installed
# system actually comes up. With the ISO present the firmware boots it in
# preference to the disk, so you land back in the installer.
set -euo pipefail

BOOT_INSTALLED=0
[ "${1:-}" = "--installed" ] && BOOT_INSTALLED=1

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ISO=${ISO:-$REPO_ROOT/result/iso/nixos-proart-installer.iso}
WORKDIR=${WORKDIR:-/var/tmp/proart-installer-vm}
DISK="$WORKDIR/disk.qcow2"
VARS="$WORKDIR/OVMF_VARS.fd"

# 1G ESP + 208G swap + root; must exceed the fixed partitions with room to spare.
DISK_SIZE=${DISK_SIZE:-260G}
RAM=${RAM:-8192}
CPUS=${CPUS:-4}

die() {
  echo "error: $*" >&2
  exit 1
}

if [ "$BOOT_INSTALLED" = 1 ]; then
  [ -f "$DISK" ] || die "no installed disk at $DISK — run without --installed first"
else
  [ -f "$ISO" ] || die "no ISO at $ISO — run: nix build .#installer"
fi

# Build, don't just evaluate: `nix eval` returns the path OVMF *would* have and
# the .fd files are absent until the derivation is realised.
nix build --no-link "$REPO_ROOT#nixosConfigurations.proart.pkgs.OVMF.fd"
OVMF_CODE=$(nix eval --raw "$REPO_ROOT#nixosConfigurations.proart.pkgs.OVMF.firmware")
OVMF_VARS=$(nix eval --raw "$REPO_ROOT#nixosConfigurations.proart.pkgs.OVMF.variables")
[ -f "$OVMF_CODE" ] || die "OVMF firmware missing at $OVMF_CODE"

mkdir -p "$WORKDIR"

if [ -f "$DISK" ]; then
  echo "Reusing existing disk: $DISK"
  echo "  (delete it to start from blank)"
else
  echo "Creating blank $DISK_SIZE disk at $DISK"
  nix shell nixpkgs#qemu -c qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
fi

# OVMF vars must be writable, and per-VM so boot entries persist across runs.
[ -f "$VARS" ] || install -m 0644 "$OVMF_VARS" "$VARS"

CDROM=(-cdrom "$ISO" -boot menu=on)
if [ "$BOOT_INSTALLED" = 1 ]; then
  CDROM=()
  echo
  echo "Booting the installed disk with no ISO attached."
  echo "Log in as dennis with the password given during install."
  echo
else
  echo
  echo "Booting the installer. Inside the VM:"
  echo "    sudo install-proart"
  echo
  echo "It prompts for a password, then partitions, clones and installs."
  echo "Afterwards, re-run with --installed to boot the result."
  echo
fi

exec nix shell nixpkgs#qemu -c qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,smm=on \
  -cpu host \
  -m "$RAM" \
  -smp "$CPUS" \
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
  -drive "if=pflash,format=raw,unit=1,file=$VARS" \
  -drive "file=$DISK,if=none,id=nvm,format=qcow2" \
  -device "nvme,serial=proarttest,drive=nvm" \
  ${CDROM[@]+"${CDROM[@]}"} \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -display gtk \
  -vga virtio
