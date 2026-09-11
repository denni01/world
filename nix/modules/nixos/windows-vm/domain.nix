# The win11 domain XML. Tunables are the let bindings below; the CPU pinning and
# the hostdev entries are computed from them rather than typed out.
{ lib, pkgs }:

let
  # Point this at a Windows 11 ISO to boot the installer: it adds the install
  # media and an emulated display, since the guest has no NVIDIA driver yet.
  # Set back to null once Windows is installed.
  installIso = null;

  # 0000:01:00.0, top slot. Function 1 is its HDMI audio — same IOMMU group (14),
  # so it has to be passed too.
  gpuBus = "0x01";

  memGiB = 32;
  shmemMiB = 128; # 3840*2160*4*2 + 10 MiB, rounded up

  guestCcd = 1; # CCD1 = physical cores 8-15, its own 32 MiB L3
  guestCores = 8; # x2 threads = 16 vCPU
  smtOffset = 16; # sibling of host cpu N (N < 16) is N + 16
  emulatorCpus = "0-1,16-17"; # QEMU's own threads, on CCD0
  iothreadCpus = "2-3,18-19";

  installing = installIso != null;

  # vCPU 2n and 2n+1 are the two threads of one physical core, so the guest's
  # SMT topology matches the silicon and its scheduler pairs correctly.
  vcpupin = lib.concatStringsSep "\n    " (
    lib.concatMap (
      n:
      let
        core = guestCcd * 8 + n;
      in
      [
        "<vcpupin vcpu='${toString (2 * n)}' cpuset='${toString core}'/>"
        "<vcpupin vcpu='${toString (2 * n + 1)}' cpuset='${toString (core + smtOffset)}'/>"
      ]
    ) (lib.range 0 (guestCores - 1))
  );

  # managed='yes' on the GPU so it goes back to nvidia on shutdown. The audio
  # function is pinned to vfio-pci at boot by vfio-bind-gpu-audio.service, so
  # managed='no' — letting libvirt "restore" it to snd_hda_intel would hand it
  # straight back to PipeWire and wedge the next start.
  hostdevLines = fn: managed: [
    "<hostdev mode='subsystem' type='pci' managed='${managed}'>"
    "  <source>"
    "    <address domain='0x0000' bus='${gpuBus}' slot='0x00' function='${fn}'/>"
    "  </source>"
    "</hostdev>"
  ];

  cdromLines = path: dev: [
    "<disk type='file' device='cdrom'>"
    "  <driver name='qemu' type='raw'/>"
    "  <source file='${path}'/>"
    "  <target dev='${dev}' bus='sata'/>"
    "  <readonly/>"
    "</disk>"
  ];

  # virtio-win unpacks the ISO, so .src is the ISO itself.
  extraDevices = lib.concatStringsSep "\n    " (
    lib.optionals installing (
      cdromLines (toString installIso) "sda"
      ++ cdromLines "${pkgs.virtio-win.src}" "sdb"
      # Absolute pointer. With only the PS/2 mouse, SPICE grabs the cursor and
      # the only way out is a release chord. Install-only, like the display.
      ++ [ "<input type='tablet' bus='usb'/>" ]
    )
    ++ hostdevLines "0x0" "yes"
    ++ hostdevLines "0x1" "no"
  );

  # Normally none: the guest's only head is the passed 3090 on DisplayPort.
  video = if installing then "virtio" else "none";

  # An empty disk is not bootable, so the installer needs the cdrom ahead of it.
  bootOrder =
    if installing then "<boot dev='cdrom'/>\n    <boot dev='hd'/>" else "<boot dev='hd'/>";
in
pkgs.writeText "win11.xml" ''
  <domain type='kvm'>
    <name>win11</name>
    <uuid>f0e1d2c3-b4a5-4967-8899-aabbccddeeff</uuid>
    <metadata>
      <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
        <libosinfo:os id="http://microsoft.com/win/11"/>
      </libosinfo:libosinfo>
    </metadata>

    <memory unit='GiB'>${toString memGiB}</memory>
    <currentMemory unit='GiB'>${toString memGiB}</currentMemory>
    <memoryBacking>
      <hugepages>
        <page size='1' unit='G'/>
      </hugepages>
      <allocation mode='immediate'/>
    </memoryBacking>

    <vcpu placement='static'>${toString (guestCores * 2)}</vcpu>
    <iothreads>1</iothreads>
    <cputune>
      ${vcpupin}
      <emulatorpin cpuset='${emulatorCpus}'/>
      <iothreadpin iothread='1' cpuset='${iothreadCpus}'/>
      <!-- No vcpusched/fifo: it kills the guest a few seconds into firmware,
           silently. This host has RT throttling disabled
           (sched_rt_runtime_us == sched_rt_period_us), so 16 FIFO vCPUs own
           CCD1 outright with no preemption escape valve. Bisected; the pinning
           above is what the latency actually comes from. -->
    </cputune>

    <!-- Named explicitly rather than firmware='efi': libvirt's autoselection only
         sees QEMU's bundled edk2, whose vars template has no keys enrolled, so
         Secure Boot would be capable but not enforcing. Anti-cheat wants
         enforcing. OVMF_VARS.ms.fd ships with the Microsoft keys. -->
    <os>
      <type arch='x86_64' machine='q35'>hvm</type>
      <loader readonly='yes' secure='yes' type='pflash'>${pkgs.OVMFFull.fd}/FV/OVMF_CODE.ms.fd</loader>
      <nvram template='${pkgs.OVMFFull.fd}/FV/OVMF_VARS.ms.fd'>/var/lib/libvirt/qemu/nvram/win11_VARS.fd</nvram>
      ${bootOrder}
    </os>

    <features>
      <acpi/>
      <apic/>
      <!-- The single biggest Windows performance win in this file. -->
      <hyperv mode='custom'>
        <relaxed state='on'/>
        <vapic state='on'/>
        <spinlocks state='on' retries='8191'/>
        <vpindex state='on'/>
        <runtime state='on'/>
        <synic state='on'/>
        <stimer state='on'>
          <direct state='on'/>
        </stimer>
        <reset state='on'/>
        <frequencies state='on'/>
        <reenlightenment state='on'/>
        <tlbflush state='on'/>
        <ipi state='on'/>
        <vendor_id state='on' value='proart'/>
      </hyperv>
      <kvm>
        <hidden state='on'/>
      </kvm>
      <vmport state='off'/>
      <smm state='on'/>
    </features>

    <cpu mode='host-passthrough' check='none' migratable='off'>
      <topology sockets='1' dies='1' cores='${toString guestCores}' threads='2'/>
      <cache mode='passthrough'/>
      <feature policy='require' name='topoext'/>
    </cpu>

    <clock offset='localtime'>
      <timer name='rtc' tickpolicy='catchup'/>
      <timer name='pit' tickpolicy='delay'/>
      <timer name='hpet' present='no'/>
      <timer name='hypervclock' present='yes'/>
    </clock>

    <on_poweroff>destroy</on_poweroff>
    <on_reboot>restart</on_reboot>
    <on_crash>destroy</on_crash>

    <pm>
      <suspend-to-mem enabled='no'/>
      <suspend-to-disk enabled='no'/>
    </pm>

    <devices>
      <disk type='file' device='disk'>
        <driver name='qemu' type='raw' cache='none' io='io_uring' discard='unmap' iothread='1'/>
        <source file='/var/lib/libvirt/images/win11.raw'/>
        <target dev='vda' bus='virtio'/>
      </disk>
      ${extraDevices}

      <tpm model='tpm-crb'>
        <backend type='emulator' version='2.0'/>
      </tpm>

      <interface type='network'>
        <source network='win11'/>
        <model type='virtio'/>
      </interface>

      <video>
        <model type='${video}'/>
      </video>

      <!-- SPICE carries Looking Glass's keyboard and mouse, not video. -->
      <graphics type='spice' autoport='yes'>
        <listen type='address' address='127.0.0.1'/>
        <image compression='off'/>
        <gl enable='no'/>
      </graphics>
      <channel type='spicevmc'>
        <target type='virtio' name='com.redhat.spice.0'/>
      </channel>

      <shmem name='looking-glass'>
        <model type='ivshmem-plain'/>
        <size unit='M'>${toString shmemMiB}</size>
      </shmem>

      <sound model='ich9'>
        <audio id='1'/>
      </sound>
      <audio id='1' type='pipewire' runtimeDir='/run/user/1000'/>

      <!-- No tablet: it forces absolute positioning, which games handle badly. -->
      <input type='mouse' bus='ps2'/>
      <input type='keyboard' bus='ps2'/>

      <memballoon model='none'/>
    </devices>
  </domain>
''
