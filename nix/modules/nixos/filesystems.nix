# Snapshots and filesystem maintenance.
#
# btrbk over snapper: the same config later gains an ssh:// or external-disk
# target with no restructuring, and it does not care about the subvolume layout.
{ ... }:

{
  services.btrbk.instances.local = {
    onCalendar = "hourly";
    settings = {
      snapshot_preserve_min = "2d";
      snapshot_preserve = "48h 14d 8w 6m";

      # btrbk works on the btrfs top level, where every subvolume is reachable
      # as a subdirectory — that is what /mnt/btrfs (subvolid=5) is mounted for.
      volume."/mnt/btrfs" = {
        snapshot_dir = "snapshots";
        subvolume = {
          rootfs = { };
          home = { };
          persist = { };
        };
      };
    };
  };

  # Excluded on purpose: `nix` rebuilds from the flake, `log` exists so a rootfs
  # rollback does not erase the evidence, and `docker` is nodatacow —
  # snapshotting it forces CoW back on and fragments the image store.
  #
  # These are local snapshots only. They protect against mistakes, not against
  # the disk dying; an off-machine copy is a `target` block here.

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
}
