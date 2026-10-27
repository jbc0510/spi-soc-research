#!/bin/sh
# Run on ZCU102 only after explicit operator approval for full FPGA programming.
set -eu
[ "${1:-}" = '--approved-full-program' ] || {
    echo 'Requires explicit approval and --approved-full-program' >&2; exit 2;
}
source_bit=/run/media/BOOT-mmcblk0p1/spi_ratio2_j55_lvcmos33_20260929.bit.bin
expected=c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd
firmware_name=msu2_ratio2_j55_c27bb684.bit.bin
manager=/sys/class/fpga_manager/fpga0
[ "$(cat /sys/bus/platform/devices/axi:msu2_pl0_clock/set_rate)" = 99990000 ]
[ "$(cat /sys/kernel/config/device-tree/overlays/msu2_pl0_clock/status)" = applied ]
[ "$(cat /sys/kernel/debug/clk/pl0_ref/clk_enable_count)" -ge 1 ]
# Refuse unexpected overlays or PL platform consumers pending investigation.
for overlay in /sys/kernel/config/device-tree/overlays/*; do
    [ "${overlay##*/}" = msu2_pl0_clock ] || exit 3
done
if ls /sys/bus/platform/devices | grep -Eq '^a[0-9a-f]{7}\.'; then
    echo 'Unexpected PL platform device; stop for review' >&2; exit 3
fi
[ "$(sha256sum "$source_bit" | cut -d ' ' -f 1)" = "$expected" ]
mkdir -p /lib/firmware
if [ -e "/lib/firmware/$firmware_name" ]; then
    [ "$(sha256sum "/lib/firmware/$firmware_name" | cut -d ' ' -f 1)" = "$expected" ]
else
    cp "$source_bit" "/lib/firmware/$firmware_name"
fi
[ "$(sha256sum "/lib/firmware/$firmware_name" | cut -d ' ' -f 1)" = "$expected" ]
echo MSU2_FULL_PROGRAM_BEGIN
printf '0\n' > "$manager/flags"
printf '%s\n' "$firmware_name" > "$manager/firmware"
echo MSU2_FULL_PROGRAM_RETURNED
cat "$manager/state"
[ "$(cat "$manager/state")" = operating ]
cat /sys/kernel/debug/clk/clk_summary
for id in 1116 1117 1118 1119; do
    echo RESET_ID="$id"
    echo pm_reset_get_status "$id" > /sys/kernel/debug/zynqmp-firmware/pm
    cat /sys/kernel/debug/zynqmp-firmware/pm
done
dmesg | tail -30
echo MSU2_PROGRAM_STAGE_COMPLETE_NO_AXI_PROBE
# No controller overlay, reset request, AFI modification, or PL MMIO follows.
