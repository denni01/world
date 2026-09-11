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

  # Display-only modules for cards that are compute-only — CUDA needs just
  # nvidia and nvidia_uvm. See modules/nixos/windows-vm/README.md.
  boot.blacklistedKernelModules = [
    "nvidia_drm"
    "nvidia_modeset"
  ];

  # The blacklist above is not enough: it only stops udev autoloading by alias,
  # and nvidia-modprobe loads nvidia_modeset explicitly on behalf of nvidia-smi
  # and CUDA. Loaded, with a cable in the passed card, its teardown oopses the
  # kernel — so refuse the load outright. /bin/true does not exist here.
  boot.extraModprobeConfig = ''
    install nvidia_modeset ${pkgs.coreutils}/bin/true
    install nvidia_drm ${pkgs.coreutils}/bin/true
  '';
}
