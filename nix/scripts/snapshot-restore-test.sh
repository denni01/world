#!/usr/bin/env bash
# Prove that a btrbk snapshot can actually be restored — without rebooting and
# without touching the live root.
#
#   sudo bash scripts/snapshot-restore-test.sh
#
# This exercises the same mechanic as Level 5 of the recovery playbook in
# README.md: btrbk snapshots are read-only, and taking a snapshot OF one (without
# -r) yields a writable subvolume you can boot. The drill builds that writable
# copy at a scratch path, checks it looks like a real root, confirms it is
# writable, and deletes it again.
#
# An untested backup is not a backup. Run this once now, and again any time the
# subvolume layout changes.

set -euo pipefail

TOP="/mnt/btrfs"
SNAPDIR="${TOP}/snapshots"
SCRATCH="${TOP}/restore-drill"

die() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "  -> $*"; }
cleanup() {
  if [[ -e "$SCRATCH" ]]; then
    btrfs subvolume delete "$SCRATCH" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "== Preflight =="
[[ $EUID -eq 0 ]] || die "must run as root"
mountpoint -q "$TOP" || die "$TOP is not mounted (needs subvolid=5)"
note "$TOP mounted"

echo
echo "== Snapshots present =="
[[ -d "$SNAPDIR" ]] || die "$SNAPDIR does not exist — has btrbk run yet? (systemctl start btrbk-local)"
mapfile -t snaps < <(find "$SNAPDIR" -maxdepth 1 -name 'rootfs.*' -printf '%f\n' 2>/dev/null | sort)
(( ${#snaps[@]} )) || die "no rootfs.* snapshots in $SNAPDIR — run: systemctl start btrbk-local"
note "${#snaps[@]} rootfs snapshot(s); newest: ${snaps[-1]}"
for s in home persist; do
  n=$(find "$SNAPDIR" -maxdepth 1 -name "${s}.*" | wc -l)
  note "$s: $n snapshot(s)"
done

NEWEST="${SNAPDIR}/${snaps[-1]}"

echo
echo "== The snapshot is read-only (as btrbk intends) =="
ro=$(btrfs property get -ts "$NEWEST" ro)
[[ "$ro" == "ro=true" ]] || die "expected a read-only snapshot, got: $ro"
note "$ro"

echo
echo "== Building a writable restore from it =="
cleanup
btrfs subvolume snapshot "$NEWEST" "$SCRATCH" >/dev/null
note "created $SCRATCH"

ro=$(btrfs property get -ts "$SCRATCH" ro)
[[ "$ro" == "ro=false" ]] || die "restored copy is still read-only: $ro"
note "writable: $ro"

echo
echo "== Does it look like a bootable root? =="
fail=0
for p in etc/os-release etc/passwd etc/shadow etc/machine-id etc/fstab nix home var; do
  if [[ -e "$SCRATCH/$p" ]]; then
    note "$p present"
  else
    echo "  !! $p MISSING" >&2
    fail=1
  fi
done
# /etc/NIXOS is what the activation script looks for to confirm a NixOS root.
if [[ -e "$SCRATCH/etc/NIXOS" ]]; then
  note "etc/NIXOS marker present"
else
  echo "  !! etc/NIXOS missing" >&2
  fail=1
fi
(( fail == 0 )) || die "the restored subvolume does not look like a usable root"

echo
echo "== Writable in practice, not just in the property =="
probe="$SCRATCH/.drill-probe"
echo ok > "$probe" && [[ "$(cat "$probe")" == "ok" ]] || die "could not write into the restored subvolume"
rm -f "$probe"
note "write/read/delete OK"

echo
echo "== Space =="
btrfs filesystem usage "$TOP" 2>/dev/null | sed -n '1,6p'

cat <<'NEXT'

PASS — a btrbk snapshot restores to a writable, plausible root.

To do this for real (Level 5 in README.md), from a live USB or another
generation, with / NOT mounted from rootfs:

  mount -o subvolid=5 /dev/nvme0n1p2 /mnt && cd /mnt
  mv rootfs rootfs.broken
  btrfs subvolume snapshot snapshots/rootfs.YYYYMMDDTHHMM rootfs
  reboot
  # once satisfied: btrfs subvolume delete rootfs.broken

Note this restores state, not the ESP. If the snapshot predates a kernel
change, boot the matching older generation too.
NEXT
