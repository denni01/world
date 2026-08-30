#!/usr/bin/env bash
# Write or verify the password hash that users.users.dennis.hashedPasswordFile
# reads at activation.
#
#   sudo bash scripts/set-password.sh           # prompt and write
#   bash scripts/set-password.sh --check        # verify an existing file
#
# The hash lives outside the repo on purpose. This repo is public, so a hash
# committed here could be cracked offline, unlimited and forever. /persist is
# neededForBoot, so the file is mounted before activation reads it.
#
# NixOS applies this only when the account is created. Where dennis already
# exists and mutableUsers is true, `passwd` still wins — this is the fresh-install
# path, not a way to force a password.
set -euo pipefail

TARGET=${TARGET:-/persist/secrets/dennis-password}
MODE="set"
[ "${1:-}" = "--check" ] && MODE="check"

die() {
  echo "error: $*" >&2
  exit 1
}

# Useful only if it is exactly what shadow(5) expects: one line, yescrypt
# (the NixOS default), readable by root alone.
validate() {
  local file=$1 hash mode owner
  [ -f "$file" ] || die "$file does not exist"

  mode=$(stat -c '%a' "$file")
  [ "$mode" = "400" ] || die "$file must be mode 0400, is $mode"

  owner=$(stat -c '%U:%G' "$file")
  [ "$owner" = "root:root" ] || die "$file must be root:root, is $owner"

  [ "$(wc -l <"$file")" -eq 1 ] || die "$file must be exactly one line"

  hash=$(head -1 "$file")
  # shellcheck disable=SC2016  # crypt prefixes are literals, not expansions
  case "$hash" in
    '$y$'*) ;;
    '$'*) die "expected yescrypt, found \$$(printf '%s' "$hash" | cut -d'$' -f2)\$" ;;
    *) die "does not look like a crypt(3) hash" ;;
  esac

  echo "ok: $file is a well-formed yescrypt hash"
}

# --check claims no privilege of its own; reading a 0400 root-owned file fails
# on its own terms and says so.
if [ "$MODE" = "check" ]; then
  validate "$TARGET"
  exit 0
fi

[ "$(id -u)" -eq 0 ] || die "run as root"
command -v mkpasswd >/dev/null || die "mkpasswd not found (pkgs.mkpasswd)"

install -d -m 0700 -o root -g root "$(dirname "$TARGET")"

umask 077
mkpasswd -m yescrypt >"$TARGET"
chmod 0400 "$TARGET"
chown root:root "$TARGET"

validate "$TARGET"
