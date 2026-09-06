# Declarative disk layout for a fresh install:
#   disko --mode destroy,format,mount --flake .#proart
#
# Exposed as flake.diskoConfigurations, deliberately not imported into the NixOS
# config, so evaluating or switching this machine can never depend on it.
# hardware.nix mounts what this creates, matching on the partition labels below.
#
# Only the ESP and swap are fixed size; root takes the rest, so a replacement
# drive of any capacity works. Partition numbering differs from this machine
# (root is p2 here, p3 there) because a 100% partition must be allocated last —
# nothing depends on the numbers, only the labels.
{
  disko.devices.disk.main = {
    type = "disk";

    # Hardcoded: edit this for a different drive.
    device = "/dev/nvme0n1";

    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          label = "EFI";
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };

        # Larger than RAM (187 GiB usable) so hibernation has somewhere to go.
        swap = {
          priority = 2;
          label = "swap";
          size = "208G";
          content.type = "swap";
        };

        root = {
          priority = 3;
          label = "root";
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];

            # btrbk operates on the top level so every subvolume is reachable
            # below it.
            mountpoint = "/mnt/btrfs";
            mountOptions = [ "noatime" ];

            subvolumes = {
              "rootfs" = {
                mountpoint = "/";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
              "home" = {
                mountpoint = "/home";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
              "nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
              # Kept out of the root subvolume so it survives a root rollback.
              "log" = {
                mountpoint = "/var/log";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
              "persist" = {
                mountpoint = "/persist";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
              # nodatacow: container layers churn, and CoW plus hourly snapshots
              # fragments them badly. It also disables compression inside, hence
              # no compress option here.
              "docker" = {
                mountpoint = "/var/lib/docker";
                mountOptions = [
                  "nodatacow"
                  "noatime"
                ];
              };
              # No need to snapshot models
              "models" = {
                mountpoint = "/var/lib/llm-models";
                mountOptions = [
                  "nodatacow"
                  "noatime"
                ];
              };
              # Must sit outside everything it snapshots.
              "snapshots" = {
                mountpoint = "/.snapshots";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
            };
          };
        };
      };
    };
  };
}
