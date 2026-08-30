# Docker: rootful daemon at boot. No Docker Desktop.
{ ... }:

{
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    daemon.settings.storage-driver = "overlay2";
  };

  # /var/lib/docker is a nodatacow subvolume (hosts/proart/hardware.nix), which
  # avoids overlay2-on-CoW fragmentation and keeps image layers out of snapshots.
  #
  # The docker group is root-equivalent. virtualisation.docker.rootless is the
  # alternative if that ever matters.
  users.users.dennis.extraGroups = [ "docker" ];
}
