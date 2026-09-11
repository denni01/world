# libvirt qemu hook for the win11 domain: hands the GPU over on the way in and
# takes it back on the way out. Installed to /var/lib/libvirt/hooks/qemu.d/win11.
{
  config,
  lib,
  pkgs,
}:

let
  gpu = "00000000:01:00.0";
  gpuBdf = "0000:01:00.0";
  hostCpus = "0-7,16-23"; # CCD0
  allCpus = "0-31";
  slices = "system.slice user.slice init.scope";

  nvidiaSmi = lib.getExe' config.hardware.nvidia.package.bin "nvidia-smi";
  modprobe = "/run/current-system/sw/bin/modprobe";
  systemctl = "/run/current-system/sw/bin/systemctl";
  sleep = lib.getExe' pkgs.coreutils "sleep";
in
pkgs.writeShellScript "win11-hook" ''
  set -eu

  [ "''${1:-}" = "win11" ] || exit 0

  case "''${2:-}" in
    prepare)
      # First, before anything touches the driver: nvidia_modeset must not be
      # loaded. With a cable in the passed card its teardown writes ELD to the
      # HDMI audio function, which is on vfio-pci, and oopses the kernel — a
      # dead task that cannot be reaped and a wedged libvirtd. boot.nix refuses
      # the load; this catches it if that ever stops working. Deliberately
      # ahead of nvidia-smi, which can itself pull the module in.
      if grep -q '^nvidia_modeset ' /proc/modules; then
        echo "win11: nvidia_modeset is loaded; refusing to start" >&2
        exit 1
      fi

      # Fail loudly rather than start half-broken: libvirt cannot unbind a card
      # the nvidia driver still has a client on.
      if [ -n "$(${nvidiaSmi} --query-compute-apps=pid --format=csv,noheader -i ${gpu} 2>/dev/null)" ]; then
        echo "win11: ${gpu} still has compute clients; refusing to start" >&2
        exit 1
      fi

      ${systemctl} stop llama-swap.service || true

      # Stopping the unit is not enough: persistence mode is set on the device
      # and survives the daemon, and it is itself a reference that blocks the
      # unbind. Clear it explicitly.
      ${systemctl} stop nvidia-persistenced.service || true
      ${nvidiaSmi} -pm 0 >/dev/null 2>&1 || true

      # The whole stack, not just persistenced. A loaded nvidia releases the card
      # with a non-zero usage count and the vfio-pci bind then deadlocks in
      # uninterruptible sleep, recoverable only by a hard reset. This runs before
      # libvirt touches the device, so it is already driverless and clean.
      for m in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
        ${modprobe} -r "$m" 2>/dev/null || true
      done
      if grep -q '^nvidia ' /proc/modules; then
        echo "win11: nvidia is still loaded; something holds a GPU" >&2
        exit 1
      fi

      # Fence the host onto CCD0 for as long as the guest owns CCD1. The domain
      # runs under machine.slice, which is left alone.
      for slice in ${slices}; do
        ${systemctl} set-property --runtime -- "$slice" AllowedCPUs=${hostCpus}
      done
      ;;

    release)
      for slice in ${slices}; do
        ${systemctl} set-property --runtime -- "$slice" AllowedCPUs=${allCpus} || true
      done

      # libvirt tried to reattach the card to a driver that was not loaded, so
      # clear the override itself before bringing nvidia back.
      echo > /sys/bus/pci/devices/${gpuBdf}/driver_override || true
      ${modprobe} nvidia || true
      ${modprobe} nvidia_uvm || true
      echo ${gpuBdf} > /sys/bus/pci/drivers_probe 2>/dev/null || true

      # drivers_probe returns before the GPU has finished initialising, and
      # persistenced enumerates once at startup. Starting it too early leaves
      # ${gpuBdf} without persistence, and the caps below then evaporate the
      # moment nvidia-smi exits — the card sits at its 420 W default.
      i=0
      until ${nvidiaSmi} -i ${gpu} --query-gpu=pci.bus_id --format=csv,noheader >/dev/null 2>&1; do
        i=$((i + 1))
        if [ "$i" -ge 30 ]; then
          echo "win11: ${gpu} did not come back within 30s" >&2
          break
        fi
        ${sleep} 1
      done

      ${systemctl} start nvidia-persistenced.service || true
      # The 280 W / 1695 MHz caps left with the card; nvidia.nix reapplies them.
      ${systemctl} restart nvidia-gpu-tuning.service || true

      # llama-swap is deliberately not restarted — it is manual-start by design.
      ;;
  esac
''
