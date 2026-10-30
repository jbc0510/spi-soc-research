#!/usr/bin/env bash
# Swap ONLY the bare-metal ELF to the polled-SPI build (boot.scr already correct).
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"; TS=$(date +%Y%m%d_%H%M%S)
FAT=""
for c in /media/opentitan/BOOT /media/$USER/BOOT /run/media/$USER/BOOT; do
  [ -d "$c/msu2_demo" ] && FAT="$c" && break
done
[ -n "$FAT" ] || { echo "ERROR: FAT boot partition not mounted (no msu2_demo/). Mount the SD and re-run."; exit 1; }
echo "FAT: $FAT"
ELF="$FAT/msu2_demo/spi_axi_bm_menu_aarch64.elf"
echo "current ELF: $(sha256sum "$ELF" | cut -d' ' -f1)"
cp -v "$ELF" "$FAT/msu2_demo/spi_axi_bm_menu_aarch64.elf.pre_nogic_$TS"
cp -v "$SP/fix3.elf" "$ELF"
sync
echo "new ELF    : $(sha256sum "$ELF" | cut -d' ' -f1)  (expect dc036961...)"
[ "$(sha256sum "$ELF"|cut -d' ' -f1)" = "$(sha256sum "$SP/fix3.elf"|cut -d' ' -f1)" ] && echo "ELF OK" || echo "ELF MISMATCH"
echo "boot.scr unchanged: $(sha256sum "$FAT/boot.scr"|cut -d' ' -f1)  (should still be 090de374...)"
echo "Done. Unmount: udisksctl unmount -b /dev/mmcblk0p1"
