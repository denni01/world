# Bootable installer ISO for proart.
#
#   nix build .#installer
#   sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
#
# The ISO carries no copy of the system: install-proart clones the repo from
# GitHub at install time, so an ISO burned months ago still installs whatever is
# on main. It needs a network connection for that — `nmtui` if not on ethernet.
#
# The clone lands at ~/Developer/world because home/default.nix hardcodes that
# path for its out-of-store dotfile symlinks; installing from anywhere else
# produces a system whose dotfiles point at nothing.
{
  modulesPath,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # Two forms of the same repo: git clones over https, nix resolves a flakeref.
  # Passing the https URL to --flake makes nix treat it as a tarball and fail.
  repoUrl = "https://github.com/denni01/world";
  flakeRef = "github:denni01/world?dir=nix";

  # Where the clone must land, per home/default.nix.
  checkout = "/mnt/home/dennis/Developer/world";

  installProart = pkgs.writeShellApplication {
    name = "install-proart";
    runtimeInputs = with pkgs; [
      git
      mkpasswd
      nixos-install-tools
      inputs.disko.packages.${pkgs.system}.disko
      coreutils
    ];
    text = ''
      set -euo pipefail

      if [ "$(id -u)" -ne 0 ]; then
        echo "run as root" >&2
        exit 1
      fi

      echo "==> Partitioning (this DESTROYS /dev/nvme0n1)"
      disko --mode destroy,format,mount --flake "${flakeRef}#proart"

      # Before nixos-install, so activation finds the hash and the account is
      # created loginable. Without this a fresh machine has no way in: the
      # greeter offers only Hyprland and there is no autologin.
      echo "==> Set a password for dennis"
      install -d -m 0700 -o root -g root /mnt/persist/secrets
      (umask 077; mkpasswd -m yescrypt > /mnt/persist/secrets/dennis-password)
      chmod 0400 /mnt/persist/secrets/dennis-password

      echo "==> Cloning ${repoUrl}"
      mkdir -p "$(dirname ${checkout})"
      git clone "${repoUrl}" "${checkout}"

      # Install from the clone rather than the GitHub flake ref so the flake.lock
      # in the installed system is the same tree the dotfiles point at.
      echo "==> Installing"
      nixos-install --root /mnt --flake "${checkout}/nix#proart"

      # uid 1000 / gid 100 are pinned in hosts/proart/default.nix.
      echo "==> Fixing ownership of the checkout"
      chown -R 1000:100 /mnt/home/dennis

      cat <<'NEXT'

      Done. Reboot and log in as dennis.

      If the password step was skipped, the account is locked; recover with
      nixos-enter --root /mnt -c 'passwd dennis'.
      NEXT
    '';
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  environment.systemPackages = [ installProart ];

  # The installer clones over https and nixos-install evaluates a flake.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Shown at the console login prompt.
  services.getty.helpLine = ''

    Install this machine with:  sudo install-proart
    Needs a network connection — run `nmtui` first if not on ethernet.
  '';

  # Not isoImage.isoName — that is a renamed alias for image.fileName, which
  # does not drive the filename. iso-image.nix builds it from image.baseName,
  # assigned plainly there, so overriding needs mkForce.
  image.baseName = lib.mkForce "nixos-proart-installer";
}
