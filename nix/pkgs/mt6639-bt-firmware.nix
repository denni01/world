# Bluetooth firmware for the onboard MT6639 (the Bluetooth half of the MT7927).
#
# The driver is mainline since 7.1, but linux-firmware only takes vendor blobs
# from the copyright holder and MediaTek has not submitted this one. Without it
# hci0 comes up with an all-zero address.
#
# Committed rather than fetched: it is redistributable firmware for hardware you
# own, and it was extracted from ASUS's Windows driver package for this board,
# which is not a durable source. Evaluates to null when absent so a fresh clone
# still builds, minus Bluetooth.
{ lib, runCommand }:

let
  blob = ../firmware/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin;
in
if !builtins.pathExists blob then
  null
else
  runCommand "mt6639-bt-firmware" { meta.license = lib.licenses.unfreeRedistributableFirmware; } ''
    install -Dm444 ${blob} \
      $out/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin
  ''
