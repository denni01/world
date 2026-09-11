# Host side of the Windows 11 guest, which owns the top RTX 3090. The domain
# itself is ./domain.nix; see ./README.md for why any of this is shaped the way
# it is.
#
#   sudo virsh start win11
#   looking-glass-client
{
  config,
  lib,
  pkgs,
  ...
}:

let
  domainXml = import ./domain.nix { inherit lib pkgs; };
  hookScript = import ./hook.nix { inherit config lib pkgs; };

  # 192.168.124/24: clear of the LAN, of docker, and of libvirt's own default.
  networkXml = pkgs.writeText "win11-network.xml" ''
    <network>
      <name>win11</name>
      <uuid>6f3a1c58-2b47-4d0e-9c11-8e5a4f27b3d9</uuid>
      <forward mode='nat'/>
      <bridge name='virbr-win11' stp='on' delay='0'/>
      <ip address='192.168.124.1' netmask='255.255.255.0'>
        <dhcp>
          <range start='192.168.124.2' end='192.168.124.254'/>
        </dhcp>
      </ip>
    </network>
  '';

  virsh = lib.getExe' config.virtualisation.libvirtd.package "virsh";
in
{
  boot.kernelParams = [
    # IOMMU is already on from BIOS; naming it here survives a firmware reset.
    "amd_iommu=on"
    "iommu=pt"

    # The guest's 32 GiB. 1 GiB pages cannot be allocated reliably after boot,
    # so this is static or nothing — the host loses 32 GiB even when idle.
    "default_hugepagesz=1G"
    "hugepagesz=1G"
    "hugepages=32"
  ];

  # Loaded early so a domain start never races a modprobe. Binds nothing on its
  # own: no ids=, no driver_override, and deliberately no softdep before nvidia.
  boot.kernelModules = [
    "vfio_pci"
    "vfio_iommu_type1"
    "vfio"
  ];

  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore";
    onShutdown = "shutdown";
    firewallBackend = "nftables";

    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true; # Windows 11 requires a TPM 2.0

      # As dennis, so QEMU can reach the session PipeWire socket for guest audio
      # and write /dev/shm/looking-glass without an extra ACL.
      #
      # runAsRoot is deliberately left at its default of true, which does NOT
      # mean QEMU runs as root — verbatimConfig below sets the user. Setting it
      # to false emits user/group = qemu-libvirtd ahead of verbatimConfig in
      # qemu.conf, and libvirt honours the first of a duplicated key, so the
      # lines below are silently ignored.
      verbatimConfig = ''
        user = "dennis"
        group = "kvm"
      '';
    };

    hooks.qemu.win11 = hookScript;
  };

  users.users.dennis.extraGroups = [
    "libvirtd"
    "kvm"
  ];

  networking.firewall.trustedInterfaces = [ "virbr-win11" ];

  # virsh otherwise defaults to qemu:///session, where the domain does not exist.
  environment.sessionVariables.LIBVIRT_DEFAULT_URI = "qemu:///system";

  # Keep host IRQs off the guest's CCD. Harmless while the VM is down.
  systemd.services.irqbalance.environment.IRQBALANCE_BANNED_CPULIST = "8-15,24-31";

  systemd.tmpfiles.rules = [
    # +C is inherited by new files only, so it has to precede the disk image.
    # hosts/proart/hardware.nix mounts the nodatacow subvolume underneath.
    "d /var/lib/libvirt/images 0755 dennis kvm -"
    "h /var/lib/libvirt/images - - - - +C"

    # QEMU sizes this itself; it just needs to exist and be ours. /dev/shm is
    # tmpfs, so it is recreated every boot.
    "f /dev/shm/looking-glass 0660 dennis kvm -"
  ];

  # PipeWire enumerates the passed card's HDMI audio as alsa_card.pci-0000_01_00.1
  # and holds it open, which blocks libvirt's detach of the function and wedges
  # the whole domain start. It is useless on a headless card, so claim it before
  # the sound stack ever sees it. By address, not vfio-pci.ids: 03:00.1 is the
  # same device ID and must stay with the host.
  systemd.services.vfio-bind-gpu-audio = {
    description = "Bind the passed GPU's HDMI audio function to vfio-pci";
    wantedBy = [ "multi-user.target" ];
    before = [
      "sound.target"
      "greetd.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      dev=0000:01:00.1
      echo vfio-pci > /sys/bus/pci/devices/$dev/driver_override
      if [ -e /sys/bus/pci/devices/$dev/driver ]; then
        echo $dev > /sys/bus/pci/devices/$dev/driver/unbind
      fi
      echo $dev > /sys/bus/pci/drivers_probe
    '';
  };

  systemd.services.libvirt-define-win11 = {
    description = "Define the win11 domain and network from the flake";
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # define updates an existing domain in place and leaves a running one alone,
    # so rebuilding mid-game is safe. net-start fails harmlessly if already up.
    script = ''
      ${virsh} net-define ${networkXml}
      ${virsh} net-autostart win11
      ${virsh} net-start win11 || true
      ${virsh} define ${domainXml}
    '';
  };

  environment.systemPackages = [
    pkgs.looking-glass-client
    pkgs.virt-manager
    # Only needed while installIso is set — the emulated display's console.
    pkgs.virt-viewer
  ];
}
