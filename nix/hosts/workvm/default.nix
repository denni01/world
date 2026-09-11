# workvm — a work environment whose egress is a VPN and nothing else.
#
# Stronger isolation than modules/nixos/sandbox/: that shares the host kernel,
# this has its own and no route to the LAN. Headless; reached over the
# loopback-forwarded ssh port, console via `journalctl -u microvm@workvm`.
{ pkgs, ... }:

let
  # Must match the `remote` line of pia/us_east.ovpn — see pia/README.md.
  piaEndpoint = "us-newjersey.privacy.network";
  piaPort = 1197;

  # OpenVPN resolves `remote` through resolved, which is strict DoT to Quad9,
  # which needs the tunnel this lookup is establishing. So strip the hostname and
  # feed literal addresses from remote.conf below — same lookup that fills the
  # kill-switch set, so the two cannot disagree.
  piaProfile = pkgs.runCommand "pia-us-east-noremote.ovpn" { } ''
    grep -v '^remote ' ${./pia/us_east.ovpn} > $out
  '';
in
{
  networking.hostName = "workvm";
  system.stateVersion = "26.05";

  microvm = {
    hypervisor = "qemu";
    vcpu = 4;
    mem = 8192;

    # QEMU user-mode (SLIRP): no tap, no bridge, no IP forwarding on the host, so
    # the LAN and the host are unreachable structurally rather than by rule.
    interfaces = [
      {
        type = "user";
        id = "vm-work";
        mac = "02:00:00:77:6b:01";
      }
    ];

    # Host loopback, not 0.0.0.0 — reaching this means first ssh'ing into proart.
    forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 2222;
        guest.port = 22;
      }
    ];

    shares = [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
      {
        tag = "share";
        source = "/home/dennis/share";
        mountPoint = "/share";
        proto = "virtiofs";
      }
      # Separate from /share and read-only: anything in the VM can read /share.
      {
        tag = "secrets";
        source = "/persist/secrets/workvm";
        mountPoint = "/run/secrets";
        proto = "virtiofs";
        readOnly = true;
      }
    ];

    # The root is a tmpfs; anything not on a volume is lost on restart.
    volumes = [
      {
        image = "/var/lib/microvms/workvm/home.img";
        mountPoint = "/home";
        size = 32768;
      }
      {
        image = "/var/lib/microvms/workvm/var.img";
        mountPoint = "/var";
        size = 8192;
      }
    ];
  };

  # OpenVPN over WireGuard because PIA publishes no static WireGuard config —
  # WireGuard would need a token exchange against their API on every boot.
  services.openvpn.servers.pia = {
    autoStart = true;
    updateResolvConf = false;
    config = ''
      config ${piaProfile}
      config /run/openvpn-pia/remote.conf

      auth-user-pass /run/secrets/pia-credentials

      # Otherwise PIA's pushed resolvers displace the DoT config below.
      pull-filter ignore "dhcp-option DNS"

      # Inert on 2.6, but compression inside TLS is VORACLE — do not rely on the
      # default. data-ciphers because 2.6 ignores the profile's `cipher` line.
      allow-compression no
      data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC

      connect-retry-max 5
      remap-usr1 SIGTERM
    '';
  };

  # DNS security, not filtering — Pi-hole is the host's ad blocker and is
  # unreachable from here anyway. Quad9 drops malicious domains and serves DoT.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "true";
      DNSOverTLS = "true";
      FallbackDNS = [ ];
    };
  };

  # The #hostname is required for strict DoT to verify the certificate.
  # IPv4 only: PIA's OpenVPN carries no IPv6, so a v6 resolver just times out.
  networking.nameservers = [
    "9.9.9.9#dns.quad9.net"
    "149.112.112.112#dns.quad9.net"
  ];

  # DHCP and RA hand out 10.0.2.3/fec0::3 as link resolvers with DefaultRoute,
  # which would let resolved route queries there instead of Quad9. Strict DoT
  # stops them being used in the clear today; this stops them being offered.
  systemd.network.networks."99-ethernet-default-dhcp" = {
    dhcpV4Config.UseDNS = false;
    dhcpV6Config.UseDNS = false;
    ipv6AcceptRAConfig.UseDNS = false;
  };

  # Default-drop egress. If OpenVPN dies the VM has no network rather than
  # quietly falling back to the clear.
  networking.nftables = {
    enable = true;
    ruleset = ''
      table inet killswitch {
        # Filled at runtime — ${piaEndpoint} is a rotating pool, so an address
        # pinned here or resolved at build time would go stale.
        set pia_endpoints {
          type ipv4_addr
        }

        chain output {
          type filter hook output priority filter; policy drop;

          oifname "lo" accept
          ct state established,related accept
          oifname "tun0" accept

          ip daddr @pia_endpoints udp dport ${toString piaPort} accept

          # The one pre-tunnel lookup, of ${piaEndpoint} itself. Unavoidable for
          # any VPN, and it discloses only what the endpoint address already does.
          ip daddr 10.0.2.3 udp dport 53 accept

          udp dport 67 accept
        }
      }
    '';
  };

  # Queries 10.0.2.3 directly: resolved needs the tunnel this unblocks.
  #
  # Retries instead of ordering after network-online.target, which microvm.nix
  # neuters by disabling systemd-networkd-wait-online — it would complete before
  # DHCP and fail OpenVPN closed via requiredBy.
  systemd.services.workvm-killswitch-resolve = {
    description = "Resolve the PIA endpoint into the kill-switch allow set";
    after = [ "nftables.service" ];
    requires = [ "nftables.service" ];
    before = [ "openvpn-pia.service" ];
    requiredBy = [ "openvpn-pia.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.dnsutils
      pkgs.nftables
    ];
    script = ''
      set -uo pipefail

      addrs=""
      for attempt in $(seq 1 15); do
        addrs=$(dig +short +time=2 +tries=1 @10.0.2.3 A ${piaEndpoint} \
                  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
        [ -n "$addrs" ] && break
        echo "attempt $attempt: ${piaEndpoint} not resolving yet, waiting for DHCP"
        sleep 2
      done

      # Fail rather than leave the set empty: a kill switch that fails open is
      # worse than a VM with no network.
      if [ -z "$addrs" ]; then
        echo "could not resolve ${piaEndpoint} after 30s" >&2
        exit 1
      fi

      nft flush set inet killswitch pia_endpoints
      install -d -m 0755 /run/openvpn-pia
      : > /run/openvpn-pia/remote.conf

      for a in $addrs; do
        nft add element inet killswitch pia_endpoints "{ $a }"
        echo "remote $a ${toString piaPort} udp" >> /run/openvpn-pia/remote.conf
      done
    '';
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };

    # On the persistent volume: /etc is tmpfs, so the defaults would be
    # regenerated every boot and every restart would look like a MITM.
    hostKeys = [
      {
        path = "/var/lib/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  users.users.dennis = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII+DyXEJ10jky82r5N2yCxXF2GkkF1XlMttQepLOIwHi denni01wolfe@gmail.com"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # /home and /var are volumes formatted after the activation that would have
  # created these, so tmpfiles has to; it runs after local-fs.target.
  systemd.tmpfiles.rules = [
    "d /home/dennis 0700 dennis users -"
    "d /var/lib/ssh 0755 root root -"
  ];

  environment.systemPackages = with pkgs; [
    git
    neovim
    ripgrep
    fd
    curl
    dnsutils
    tcpdump
  ];

  boot.kernelParams = [ "console=ttyS0" ];
}
