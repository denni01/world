# Derived from nixos-generate-config, then hand-maintained.
#
# Subvolume layout on nvme0n1p2 (created by hosts/proart/disko.nix):
#
#   subvolid=5 (top level, mounted at /mnt/btrfs for btrbk)
#   ├── rootfs      -> /
#   ├── home        -> /home
#   ├── nix         -> /nix
#   ├── log         -> /var/log           survives a root rollback
#   ├── docker      -> /var/lib/docker    nodatacow, excluded from snapshots
#   ├── models      -> /var/lib/llm-models  nodatacow, excluded from snapshots
#   ├── vms         -> /var/lib/libvirt/images  nodatacow, excluded from snapshots
#   ├── persist     -> /persist           impermanence-ready, unused
#   └── snapshots   -> /.snapshots        must sit outside what it snapshots
#
# btrfs applies `compress` filesystem-wide from the first mount, so the option is
# listed uniformly; the docker subvolume is exempt in practice because NODATACOW
# disables compression for anything created inside it.
#
# Compression only affects new writes:
#   sudo btrfs filesystem defragment -r -czstd /
{
  config,
  lib,
  modulesPath,
  ...
}:

let
  # By partition label, not UUID: mkfs mints UUIDs, so a UUID can only name a
  # disk that already exists and a fresh install could never match. disko.nix
  # creates these labels. Note by-partlabel resolves to whichever disk appeared
  # last, so do not attach another disk with a partition called "root".
  #
  # Samsung 990 PRO 4TB — nvme0n1p2
  pool = "/dev/disk/by-partlabel/root";
  btrfsVol = subvol: {
    device = pool;
    fsType = "btrfs";
    options = [
      subvol
      "compress=zstd:1"
      "noatime"
    ];
  };
in
{
  # Sets hardware.enableRedistributableFirmware; dropping it silently removes
  # ~780 MiB of firmware.
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "thunderbolt"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = btrfsVol "subvol=rootfs";
  fileSystems."/home" = btrfsVol "subvol=home";
  fileSystems."/nix" = btrfsVol "subvol=nix";

  # Stage 1, so journald never writes into the root subvolume first.
  fileSystems."/var/log" = btrfsVol "subvol=log" // {
    neededForBoot = true;
  };

  # Unused for now; mounted early so enabling impermanence later is a config
  # change rather than a layout change.
  fileSystems."/persist" = btrfsVol "subvol=persist" // {
    neededForBoot = true;
  };

  fileSystems."/var/lib/docker" = btrfsVol "subvol=docker";
  fileSystems."/.snapshots" = btrfsVol "subvol=snapshots";

  fileSystems."/var/lib/llm-models" = {
    device = pool;
    fsType = "btrfs";
    options = [
      "subvol=models"
      "nodatacow"
      "noatime"
    ];
  };

  fileSystems."/var/lib/microvms" = {
    device = pool;
    fsType = "btrfs";
    options = [
      "subvol=microvms"
      "nodatacow"
      "noatime"
    ];
  };

  # Windows 11 guest image (modules/nixos/windows-vm). Same trade as microvms
  # above, including why this is not nofail; needs one manual
  # `sudo btrfs subvolume create /mnt/btrfs/vms` on this machine.
  fileSystems."/var/lib/libvirt/images" = {
    device = pool;
    fsType = "btrfs";
    options = [
      "subvol=vms"
      "nodatacow"
      "noatime"
    ];
  };

  # btrbk operates on the top level so every subvolume is reachable below it.
  fileSystems."/mnt/btrfs" = {
    device = pool;
    fsType = "btrfs";
    options = [
      "subvolid=5"
      "noatime"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/EFI";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  # Sized above RAM so hibernation has somewhere to go. Labelled to match what
  # disko creates
  swapDevices = [
    { device = "/dev/disk/by-partlabel/swap"; }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
