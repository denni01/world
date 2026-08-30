# Platform tuning for a 16C/32T 7950X with 187 GiB of RAM.
{ pkgs, ... }:

{
  # amd-pstate-epp is the active driver; "performance" pins EPP rather than
  # fixing the frequency, so the hardware still clocks down at idle.
  powerManagement.cpuFreqGovernor = "performance";

  boot.kernel.sysctl = {
    # The one that matters here. The percentage defaults let ~37 GiB of dirty
    # pages accumulate on this much RAM before forcing writeback, which shows up
    # as multi-second I/O stalls.
    "vm.dirty_bytes" = 4294967296; # 4 GiB
    "vm.dirty_background_bytes" = 1073741824; # 1 GiB

    # Swap is hibernation headroom, not paging space.
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.max_map_count" = 2147483642;

    # Defaults are exhausted quickly by editors watching large trees.
    "fs.inotify.max_user_watches" = 1048576;
    "fs.inotify.max_user_instances" = 8192;

    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";

    "kernel.sysrq" = 1;
  };

  # If a large Nix build ever exhausts this, move the daemon's scratch space
  # with systemd.services.nix-daemon.environment.TMPDIR rather than growing it.
  boot.tmp = {
    useTmpfs = true;
    tmpfsSize = "64G";
  };

  services.irqbalance.enable = true;

  # Nuvoton NCT6799D — board temps, fans, voltages. k10temp binds on its own.
  boot.kernelModules = [ "nct6775" ];
  environment.systemPackages = [ pkgs.lm_sensors ];

  nix = {
    settings = {
      # Eight builds of four cores keeps the machine usable during a rebuild,
      # versus the default of up to 32 concurrent builds each using every core.
      max-jobs = 8;
      cores = 4;
      trusted-users = [ "@wheel" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise.automatic = true;
  };

  # Not set: zramSwap (pointless at this RAM size), services.fstrim (the mounts
  # already carry discard=async), mitigations=off (security defaults stay).
}
