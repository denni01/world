# PIA OpenVPN profile

`us_east.ovpn`, vendored verbatim from
<https://www.privateinternetaccess.com/openvpn/openvpn-strong.zip> — the same
treatment as `sandbox/allowlist.nix`. No secrets here; credentials never go in
this directory.

The `-strong` bundle, not the default: that one is `aes-128-cbc`/`sha1` on UDP
1198, strong is `aes-256-cbc`/`sha256` on UDP **1197**.

## Changing region

Replace this file, then update `piaEndpoint` and `piaPort` in
`hosts/workvm/default.nix` to match its `remote` line. The kill switch permits
exactly one host and port, so a mismatch fails closed.

The hostname is a rotating pool, which is why the kill switch resolves it at
service start rather than pinning an address here.
