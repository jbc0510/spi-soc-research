#!/bin/sh
# recon_board.sh -- ZCU102 baseline capture. MSU-2 Task 2.
# Run on the BOARD over UART. Kept under 3 KB so it can be PASTED if the
# SD card cannot be written from the verify-site workstation.
# POSIX sh / busybox safe. Read-only. Absence is printed, not skipped.
p() { printf '%-30s %s\n' "$1:" "$2"; }
r() { if [ -r "$1" ]; then p "$2" "$(head -1 "$1" 2>/dev/null)"; else p "$2" ABSENT; fi; }
echo "=== ZCU102 BOARD RECON ==="
p BOARD "${MSU_BOARD:-UNSET: rerun MSU_BOARD=LPS or MORGAN}"
p hostname "$(hostname 2>/dev/null)"
p date_UNTRUSTED "$(date 2>/dev/null)"
echo "  RTC was UNSET on board #1 (read Jan 2025). Do not trust the above."
r /proc/version kernel
echo "  Board #1: 6.12.10-xilinx-g0a0f70e531c7 #1 SMP, NO PREEMPT string."
r /proc/cmdline cmdline
r /sys/module/spidev/parameters/bufsiz spidev_bufsiz
echo "  Board #1: 1048576"
r /sys/class/fpga_manager/fpga0/state fpga0_state
echo "  Board #1: unknown  (= NO bitstream loaded)"
p glibc "$(ldd --version 2>&1 | head -1)"
echo "  Board #1: 2.39"
echo "--- SPI MASTERS ---"
ls -1 /sys/class/spi_master/ 2>/dev/null || echo "  none"
for m in /sys/class/spi_master/*; do
  [ -e "$m" ] || continue
  echo "  $m"
  [ -e "$m/of_node" ] && echo "    of_node -> $(readlink -f "$m/of_node" 2>/dev/null)"
done
echo "--- SPIDEV NODES ---"
ls -l /dev/spidev* 2>/dev/null || echo "  NONE (board #1: none)"
echo "  If present, MAP each to an address before trusting any capture."
echo "  spidev1.0 mapped to AXI 0xa0000000, NOT PS SPI1, in the July work."
echo "--- DEVICE TREE SPI NODES ---"
ls -1 /proc/device-tree/axi/ 2>/dev/null | grep -i spi || echo "  none under /axi"
echo "--- BLOCK DEVICES / SD ---"
cat /proc/partitions 2>/dev/null || echo "  ABSENT"
echo "  Board #1: root=/dev/ram0; FAT partition NOT mounted at boot."
echo "  Mount by hand: mkdir -p /mnt/sd && mount /dev/mmcblk0p1 /mnt/sd"
echo "--- MOUNTS ---"
mount 2>/dev/null | grep -E 'mmc|ram|vfat' || echo "  no mmc/ram/vfat mounts"
echo "--- TOOLS PRESENT ---"
for t in fw_setenv fw_printenv md5sum hwclock mount dtc devmem; do
  if command -v "$t" >/dev/null 2>&1; then p "$t" PRESENT; else p "$t" ABSENT; fi
done
echo "  fw_setenv is REQUIRED for the SOW 2.g A/B pointer. If ABSENT,"
echo "  that is a finding: the design assumes it."
echo "--- RTC PERSISTENCE TEST (manual, 2 steps) ---"
echo "  1) date -s '<correct UTC>' && hwclock -w && hwclock -r"
echo "  2) power-cycle, then: hwclock -r ; date"
echo "  If it does NOT persist, setting the clock is a numbered per-boot"
echo "  step in every capture procedure and the time source must be named."
echo "=== END. Capture this whole transcript. Commit under docs/environment/. ==="
