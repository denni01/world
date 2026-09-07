# opencode-sandbox app
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  netName = "ocsandbox";
  bridge = "br-ocsandbox";
  subnet = "172.28.0.0/16";
  gateway = "172.28.0.1";

  proxyPort = 3128;
  llamaPort = config.services.llama-swap.port;

  workspaceRoot = "/home/dennis/Developer";

  allowlist = import ./allowlist.nix;

  # Allow root domain and all subdomains
  domainsFile = pkgs.writeText "sandbox-allowed-domains" (
    lib.concatMapStringsSep "\n" (d: ".${d}") (lib.concatLists (lib.attrValues allowlist)) + "\n"
  );

  hostOpencodeConfig = builtins.fromJSON (
    builtins.readFile ../../../home/dotfiles/opencode/opencode.json
  );

  sandboxOpencodeConfig = lib.recursiveUpdate hostOpencodeConfig {
    autoupdate = false;
    provider."llama-swap".options.baseURL = "http://${gateway}:${toString llamaPort}/v1";
  };

  sandboxOpencodeConfigFile = pkgs.writeText "opencode-sandbox.json" (
    builtins.toJSON sandboxOpencodeConfig
  );

  sandboxImage = import ./image.nix {
    inherit
      pkgs
      gateway
      llamaPort
      proxyPort
      ;
    opencode = unstable.opencode;
  };

  imageRef = "${sandboxImage.imageName}:${sandboxImage.imageTag}";

  docker = "${config.virtualisation.docker.package}/bin/docker";

  opencodeSandbox = pkgs.writeShellApplication {
    name = "opencode-sandbox";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.coreutils
    ];
    text = ''
      workspace_root=${lib.escapeShellArg workspaceRoot}
      network=${lib.escapeShellArg netName}
      image=${lib.escapeShellArg imageRef}
      config_file=${lib.escapeShellArg (toString sandboxOpencodeConfigFile)}
      home_volume=opencode-sandbox-home

      die() {
        printf 'opencode-sandbox: %s\n' "$1" >&2
        exit 1
      }

      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        cat <<USAGE
      opencode-sandbox [DIR] [-- COMMAND...]

        Runs opencode with DIR mounted at /workspace. DIR defaults to $PWD and
        must be inside $workspace_root. With -- COMMAND, runs COMMAND instead.
      USAGE
        exit 0
      fi

      target=$PWD
      if [ "$#" -gt 0 ] && [ "$1" != "--" ]; then
        target=$1
        shift
      fi
      if [ "''${1:-}" = "--" ]; then
        shift
      fi

      # Assigning straight into $target would blank it when realpath fails.
      requested=$target
      target=$(realpath -e -- "$requested" 2>/dev/null) ||
        die "no such directory: $requested"
      [ -d "$target" ] || die "not a directory: $requested"

      # After realpath, so a symlink pointing out of the tree is caught.
      case "$target" in
        "$workspace_root" | "$workspace_root"/*) ;;
        *) die "refusing to mount $target: outside $workspace_root" ;;
      esac

      docker image inspect "$image" >/dev/null 2>&1 ||
        die "image $image not loaded — try: sudo systemctl restart docker-sandbox-image"

      docker network inspect "$network" >/dev/null 2>&1 ||
        die "network $network missing — try: sudo systemctl restart docker-sandbox-network"

      # -t against a pipe fails.
      tty_args=()
      if [ -t 0 ] && [ -t 1 ]; then
        tty_args=(--interactive --tty)
      fi

      exec docker run --rm "''${tty_args[@]}" \
        --network "$network" \
        --hostname sandbox \
        --user 1000:100 \
        --cap-drop ALL \
        --security-opt no-new-privileges \
        --pids-limit 512 \
        --volume "$target:/workspace" \
        --volume "$home_volume:/home/agent" \
        --volume "$config_file:/etc/opencode/opencode.json:ro" \
        --workdir /workspace \
        "$image" "$@"
    '';
  };
in
{
  systemd.services.docker-sandbox-network = {
    description = "Create the opencode sandbox docker network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      current=$(${docker} network inspect ${netName} \
        --format '{{(index .IPAM.Config 0).Subnet}} {{index .Labels "keep"}}' 2>/dev/null || true)

      if [ "$current" = "${subnet} true" ]; then
        exit 0
      fi

      if [ -n "$current" ]; then
        echo "sandbox network is '$current', expected '${subnet} true'; recreating"
        ${docker} network rm ${netName}
      fi

      # --internal removes the NAT rules: no route off the bridge at all. The
      # gateway address still works, which is how the sandbox reaches squid.
      ${docker} network create \
        --driver bridge \
        --internal \
        --subnet ${subnet} \
        --gateway ${gateway} \
        --opt com.docker.network.bridge.name=${bridge} \
        --label keep=true \
        ${netName}
    '';
  };

  virtualisation.docker.autoPrune.flags = [
    "--filter"
    "label!=keep"
  ];

  systemd.services.docker-sandbox-image = {
    description = "Load the opencode sandbox container image";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ${docker} image inspect ${imageRef} >/dev/null 2>&1; then
        exit 0
      fi

      ${sandboxImage} | ${docker} load

      # Superseded images stay tagged, so autoPrune will not collect them.
      ${docker} images --format '{{.Repository}}:{{.Tag}}' \
        | ${pkgs.gnugrep}/bin/grep '^${sandboxImage.imageName}:' \
        | ${pkgs.gnugrep}/bin/grep -v '^${imageRef}$' \
        | ${pkgs.findutils}/bin/xargs -r ${docker} rmi || true
    '';
  };

  systemd.sockets.llama-swap-sandbox = {
    description = "llama-swap, reachable from the opencode sandbox";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "${gateway}:${toString llamaPort}";
      FreeBind = true;
    };
  };

  systemd.services.llama-swap-sandbox = {
    description = "llama-swap sandbox forwarder";
    requires = [ "llama-swap-sandbox.socket" ];
    after = [ "llama-swap-sandbox.socket" ];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString llamaPort}";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
    };
  };

  services.squid = {
    enable = true;
    configText = ''
      acl sandbox src ${subnet}
      acl allowed_domains dstdomain "${domainsFile}"

      acl SSL_ports port 443
      acl Safe_ports port 80
      acl Safe_ports port 443
      acl CONNECT method CONNECT

      http_access deny !Safe_ports
      http_access deny CONNECT !SSL_ports

      # Stops the proxy being a pivot to pihole on 127.0.0.1:8080 or the LAN,
      # and defeats DNS rebinding onto an internal address.
      acl private_dst dst 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16
      acl private_dst dst ::1/128 fc00::/7 fe80::/10
      http_access deny private_dst

      http_access allow sandbox allowed_domains
      http_access deny all

      http_port ${gateway}:${toString proxyPort}

      cache deny all

      cache_log stdio:/var/log/squid/cache.log
      access_log stdio:/var/log/squid/access.log
      pid_filename /run/squid.pid
      cache_effective_user squid squid
      coredump_dir /var/cache/squid
    '';
  };

  systemd.services.squid = {
    after = [ "docker-sandbox-network.service" ];
    requires = [ "docker-sandbox-network.service" ];
  };

  networking.firewall.interfaces.${bridge}.allowedTCPPorts = [
    llamaPort
    proxyPort
  ];

  environment.systemPackages = [ opencodeSandbox ];
}
