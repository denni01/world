# Host: proart — ASUS ProArt X870E-CREATOR WIFI / Ryzen 9 7950X / 192 GiB / RTX 3090
{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ../../modules/nixos
  ];

  networking.hostName = "proart";

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # No X server; XWayland comes from programs.hyprland.xwayland.
  console.keyMap = "us";

  # Needed so zsh is a valid login shell. The config is a plain ~/.zshrc.
  programs.zsh.enable = true;

  users.users.dennis = {
    isNormalUser = true;
    description = "Dennis";
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    # Packages live in home/default.nix. useUserPackages routes those through
    # users.users.dennis.packages too, so both land in the same profile — one
    # list is enough.
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    vim # root's editor; the user's is neovim
    wget
    e2fsprogs # chattr/lsattr, needed by the scripts in scripts/
    pciutils
    usbutils
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # See the NixOS manual before ever changing this.
  system.stateVersion = "26.05";
}
