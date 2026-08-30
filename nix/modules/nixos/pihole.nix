# Pi-hole, for this machine only — bound to loopback, not serving the LAN.
#
# Config is immutable: `settings` renders /etc/pihole/pihole.toml from the store
# and the NixOS package drops the update/reinstall commands from the `pihole`
# script. Dashboard changes that map to pihole.toml revert on the next rebuild;
# groups, clients and regex filters live in gravity.db and persist.
{ config, pkgs, ... }:

let
  # Upstream only signals FTL to reopen gravity.db when the file was absent, but
  # FTL creates an empty skeleton at startup, so a fresh install blocks nothing
  # until FTL restarts. Reloading is idempotent, so signal every time.
  reloadGravity = pkgs.writeShellScript "pihole-reload-gravity" ''
    pid=$(${config.systemd.package}/bin/systemctl show --property MainPID --value pihole-ftl.service)
    if [ -n "$pid" ] && [ "$pid" != 0 ]; then
      ${pkgs.procps}/bin/kill -s SIGRTMIN "$pid"
    fi
  '';
in

{
  services.pihole-ftl = {
    enable = true;

    # Query history is SQLite on CoW, snapshotted hourly and kept for months.
    # The 90-day default would be pinned in every one of those snapshots.
    queryLogDeleter = {
      enable = true;
      age = 7;
    };

    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "StevenBlack unified adlist";
      }
    ];

    settings = {
      dns = {
        # BIND binds the named interface instead of the wildcard, so nothing is
        # reachable off-box even if the firewall is opened by accident.
        interface = "lo";
        listeningMode = "BIND";

        # Never the router: it hands out DNS via DHCP, so upstream would loop.
        upstreams = [
          "1.1.1.1"
          "1.0.0.1"
          "9.9.9.9"
        ];

        domainNeeded = true;
        expandHosts = true;
      };

      # The router already serves DHCP; two on one segment is a bad time.
      dhcp.active = false;
    };
  };

  services.pihole-web = {
    enable = true;

    # No password: on a loopback-only bind, anything that can reach this port can
    # edit this file. Exposing it off-box needs webserver.api.pwhash, which lands
    # in the world-readable store and in git — so via sops-nix, not a literal.
    #
    # Served at /, not /admin: pihole-web sets webhome = "/".
    ports = [ "127.0.0.1:8080" ];
  };

  networking.hosts."127.0.0.1" = [ "pi.hole" ];

  # "none" stops NetworkManager overwriting resolv.conf from DHCP on reconnect,
  # handing it to networking.nameservers below.
  #
  # So if pihole-ftl will not start, this machine has no DNS at all: recover with
  # `echo nameserver 1.1.1.1 > /etc/resolv.conf` or an older generation. A VPN
  # pushing its own DNS is also ignored.
  networking.networkmanager.dns = "none";
  networking.nameservers = [
    "127.0.0.1"
    "::1"
  ];

  # NOCOW for the databases, as with /var/lib/docker. Inherited by new files
  # only, so it has to land before FTL first creates them.
  systemd.tmpfiles.rules = [ "h /var/lib/pihole - - - - +C" ];

  # Upstream re-adds every declared list each boot and treats "already present"
  # as fatal via `exit $any_failed`, failing the unit from the second boot on.
  # This masks list-add errors only — `set -eo pipefail` means gravity and login
  # failures exit separately. A bad list on a fresh install goes quiet, which the
  # gravity count check in README catches.
  systemd.services.pihole-ftl-setup.serviceConfig = {
    SuccessExitStatus = [ 1 ];
    ExecStartPost = "+${reloadGravity}"; # + = root, independent of the sandbox
  };
}
