# Boot loader and kernel.
{ pkgs, ... }:

{
  boot.loader.systemd-boot = {
    enable = true;
    # The ESP is 1 GiB and each generation costs a kernel plus an initrd.
    configurationLimit = 15;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Pinned to 7.2, not linuxPackages_latest: the onboard MediaTek MT7927 WiFi
  # has no driver before it, and pinning stops a flake update landing on a
  # kernel the NVIDIA module cannot build against.
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_7_2;

  # mt7925 firmware, which MT7927 reuses.
  hardware.enableRedistributableFirmware = true;
}
