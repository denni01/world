# GPUs: two RTX 3090s (10de:2204) at 0000:01:00.0 (top slot) and 0000:03:00.0
# (bottom slot), both headless and reserved for compute. The desktop runs on the
# Raphael iGPU at 0000:7a:00.0 — pinned in desktop.nix and POSTed by the BIOS.
# Both 3090s are compute capability 8.6 and sit in separate IOMMU groups (14 and
# 16), each alone with its own HDMI-audio function.
#
# 0000:01:00.0 leaves for the Windows guest while it runs — modules/nixos/windows-vm.
{
  config,
  lib,
  pkgs,
  ...
}:

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

  # Undervolt GPUs to allow for proper cooling
  powerCapWatts = 280;
  smClockCeiling = 1695;

  nvidiaSmi = lib.getExe' nvidiaDriver.bin "nvidia-smi";
  gpuTuning = pkgs.writeShellScript "nvidia-gpu-tuning" ''
    set -eu
    ${nvidiaSmi} --power-limit=${toString powerCapWatts}
    ${nvidiaSmi} --lock-gpu-clocks=0,${toString smClockCeiling}
  '';
in
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Loads the kernel module and blacklists nouveau. Correct for Wayland too,
  # despite the name. amdgpu needs no entry here — it is in-tree and binds the
  # iGPU on its own.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Ampere is supported by both modules; open is upstream's default from 560.
    # NixOS requires this be explicit.
    open = true;
    # Off deliberately: both 3090s are headless and the compositor is on the
    # iGPU, so KMS buys nothing here. Note this alone does NOT stop nvidia_drm
    # registering a DRM device per card — the modeset param only controls KMS —
    # which is why nvidia_drm is blacklisted in boot.nix.
    modesetting.enable = false;
    nvidiaSettings = true;
    package = nvidiaDriver;

    # Without persistence the driver deinitialises
    # whenever the last CUDA client exits, and takes the caps below with it —
    # which is exactly llama-swap's lifecycle, since a TTL unload leaves no
    # clients behind. The caps would silently reset before the next model
    # loaded. It also removes several seconds of driver re-init per model load.
    #
    # It also holds every GPU open, so the windows-vm hook stops it before
    # libvirt can unbind the card, and starts it again on release.
    nvidiaPersistenced = true;
  };

  systemd.services.nvidia-gpu-tuning = {
    description = "Power and clock caps for both RTX 3090s";
    wantedBy = [ "multi-user.target" ];
    # Ordering only. persistenced is what makes the settings stick, but applying
    # them is still worthwhile if it failed to start.
    after = [ "nvidia-persistenced.service" ];
    wants = [ "nvidia-persistenced.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = gpuTuning;
    };
  };

  # The caps do not survive a suspend/resume cycle, and hypridle suspends.
  powerManagement.resumeCommands = "${gpuTuning}";

  # Deliberately not set: hardware.nvidia.powerManagement (its suspend/resume
  # hooks target laptops and have a history of breaking headless cards), and
  # prime/offload (nothing renders on the 3090s — the iGPU drives the display
  # outright rather than being the cheap half of a hybrid pair).
}
