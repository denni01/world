# Host side of the work VM. The guest itself is hosts/workvm/default.nix.
#
# Everything the VM *is* lives in the guest config; this file is only what the
# host has to provide for it: the systemd unit, the two directories that get
# shared in, and somewhere to keep the disk images.
#
{ inputs, ... }:

{
  imports = [ inputs.microvm.nixosModules.host ];

  microvm.vms.workvm = {
    config = {
      imports = [ ../../hosts/workvm ];
    };

    autostart = false;
  };

  systemd.tmpfiles.rules = [
    "d /home/dennis/share 0755 dennis users -"

    "d /persist/secrets 0700 root root -"
    "d /persist/secrets/workvm 0700 root root -"

    "d /var/lib/microvms 0755 root root -"
    "h /var/lib/microvms - - - - +C"
  ];
}
