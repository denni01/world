# GPU: RTX 3090 (10de:2204) at 0000:01:00.0 drives the only display. The Raphael
# iGPU at 0000:79:00.0 stays enabled but has nothing attached.
{ config, ... }:

let
  # Pinned: nixpkgs 26.05 ships 595.71.05, whose kernel module does not build
  # against Linux 7.2 (the kernel dropped strncpy; the driver still calls it).
  # Drop this once nixpkgs catches up:
  #   nix eval nixpkgs#linuxPackages.nvidiaPackages.production.version
  nvidiaDriver = config.boot.kernelPackages.nvidiaPackages.mkDriver {
    version = "595.91.07";
    sha256_64bit = "sha256-yiPIjdJLB6GRZE4eEc+3vN11NzBXSa9A+YABiwleYxM=";
    sha256_aarch64 = "sha256-fqkN7ONFXtTeXyu2mQxorrk362Epxq3bz88hhKYQzwQ=";
    openSha256 = "sha256-OB8Epd+qn/WywxsPiFpxEOAzlJqb6I1SyRoV3a8l71k=";
    settingsSha256 = "sha256-QzT8Cw1luuZGP9DUje3HN/0ngiayqHURj+bqPsxlJ5w=";
    persistencedSha256 = "sha256-3JQBaNmkwxvCXv9q8aHKas6VZM/JjLsuilC2t7ET0u0=";
  };
in
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Loads the kernel module and blacklists nouveau. Correct for Wayland too,
  # despite the name.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    open = true; # Ampere; NixOS requires this be explicit on 560+
    modesetting.enable = true; # also emits nvidia-drm fbdev=1 via moduleParams
    nvidiaSettings = true;
    package = nvidiaDriver;
  };
}
