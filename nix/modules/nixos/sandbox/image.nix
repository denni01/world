{
  pkgs,
  opencode,
  gateway,
  llamaPort,
  proxyPort,
}:

let
  uid = 1000;
  gid = 100;

  etcSkeleton = pkgs.runCommand "sandbox-etc" { } ''
    mkdir -p $out/etc
    cat > $out/etc/passwd <<EOF
    root:x:0:0:System administrator:/root:${pkgs.bashInteractive}/bin/bash
    agent:x:${toString uid}:${toString gid}:Sandbox agent:/home/agent:${pkgs.bashInteractive}/bin/bash
    nobody:x:65534:65534:Nobody:/var/empty:/run/current-system/sw/bin/nologin
    EOF
    cat > $out/etc/group <<EOF
    root:x:0:
    users:x:${toString gid}:
    nogroup:x:65534:
    EOF
    cat > $out/etc/nsswitch.conf <<EOF
    hosts: files dns
    passwd: files
    group: files
    EOF
    : > $out/etc/resolv.conf
  '';

  entrypoint = pkgs.writeShellApplication {
    name = "sandbox-entrypoint";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      mkdir -p "$OPENCODE_CONFIG_DIR"
      if [ -f /etc/opencode/opencode.json ]; then
        install -m 0644 /etc/opencode/opencode.json "$OPENCODE_CONFIG_DIR/opencode.json"
      fi

      if [ "$#" -eq 0 ]; then
        exec opencode
      fi
      exec "$@"
    '';
  };
in
pkgs.dockerTools.streamLayeredImage {
  name = "opencode-sandbox";
  tag = null;

  contents = [
    opencode

    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.findutils
    pkgs.diffutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.gnutar
    pkgs.gzip
    pkgs.less
    pkgs.which

    pkgs.git
    pkgs.openssh
    pkgs.curl
    pkgs.cacert

    pkgs.ripgrep
    pkgs.fd
    pkgs.jq

    pkgs.nodejs

    etcSkeleton
    entrypoint
  ];

  fakeRootCommands = ''
    mkdir -p ./tmp ./home/agent ./workspace ./var/empty
    chmod 1777 ./tmp
    chown -R ${toString uid}:${toString gid} ./home/agent ./workspace
  '';

  config = {
    Entrypoint = [ "${entrypoint}/bin/sandbox-entrypoint" ];
    WorkingDir = "/workspace";
    User = "${toString uid}:${toString gid}";

    Env = [
      "HOME=/home/agent"
      "USER=agent"
      "PATH=/bin:/usr/bin"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

      "HTTP_PROXY=http://${gateway}:${toString proxyPort}"
      "HTTPS_PROXY=http://${gateway}:${toString proxyPort}"
      "http_proxy=http://${gateway}:${toString proxyPort}"
      "https_proxy=http://${gateway}:${toString proxyPort}"
      "NO_PROXY=${gateway},127.0.0.1,localhost"
      "no_proxy=${gateway},127.0.0.1,localhost"

      "OPENCODE_CONFIG_DIR=/home/agent/.config/opencode"
      "OPENCODE_CONFIG=/home/agent/.config/opencode/opencode.json"
      "OPENCODE_DISABLE_MODELS_FETCH=1"

      "LLAMA_SWAP_URL=http://${gateway}:${toString llamaPort}/v1"
      "TERM=xterm-256color"
      "LANG=C.UTF-8"
    ];
  };
}
