# Networking.
{ lib, pkgs, ... }:

let
  # null unless firmware/mt7927/ is populated.
  mt6639Firmware = pkgs.callPackage ../../pkgs/mt6639-bt-firmware.nix { };
in
{
  networking.networkmanager.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  hardware.firmware = lib.optional (mt6639Firmware != null) mt6639Firmware;

  # Uses the module rather than the bare package so TCP+UDP 53317 is opened
  programs.localsend = {
    enable = true;
    openFirewall = true;
  };

  # checkReversePath = true emits STRICT rpfilter; only the literal "loose"
  # relaxes it. Strict mode drops packets arriving on any interface that is not
  # the preferred route back to the sender, which silently breaks peer discovery
  # whenever this machine is multi-homed (e.g. ethernet and WiFi on one subnet).
  networking.firewall.checkReversePath = "loose";

  systemd.user.services.nm-applet = {
    description = "NetworkManager applet";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  environment.systemPackages = [ pkgs.networkmanagerapplet ];
}
