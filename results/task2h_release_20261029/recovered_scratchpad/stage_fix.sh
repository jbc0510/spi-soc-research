#!/usr/bin/env bash
# Stage the validated handoff fix onto the FAT boot partition, with backups.
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)
# locate the mounted FAT boot partition
FAT=""
for c in /media/opentitan/BOOT /media/$USER/BOOT /run/media/$USER/BOOT /media/opentitan/*; do
  [ -d "$c/msu2_demo" ] && FAT="$c" && break
done
[ -n "$FAT" ] || { echo "ERROR: could not find mounted FAT boot partition (with msu2_demo/)"; echo "Mount the SD and re-run."; exit 1; }
echo "FAT partition: $FAT"
ELF="$FAT/msu2_demo/spi_axi_bm_menu_aarch64.elf"
SCR="$FAT/boot.scr"
echo "== current on-card hashes =="
sha256sum "$ELF" "$SCR" 2>/dev/null || true
echo "== backing up originals =="
cp -v "$ELF" "$FAT/msu2_demo/spi_axi_bm_menu_aarch64.elf.pre_mmufix_$TS"
cp -v "$SCR" "$FAT/boot.scr.pre_mmufix_$TS"
echo "== staging fixed artifacts =="
cp -v "$SP/fix.elf" "$ELF"
cp -v "$SP/boot.scr.fixed" "$SCR"
sync
echo "== new on-card hashes =="
sha256sum "$ELF" "$SCR"
echo "== verify match to source =="
[ "$(sha256sum "$ELF"|cut -d' ' -f1)" = "$(sha256sum "$SP/fix.elf"|cut -d' ' -f1)" ] && echo "ELF OK" || echo "ELF MISMATCH"
[ "$(sha256sum "$SCR"|cut -d' ' -f1)" = "$(sha256sum "$SP/boot.scr.fixed"|cut -d' ' -f1)" ] && echo "boot.scr OK" || echo "boot.scr MISMATCH"
echo "Done. Safely unmount: sudo umount '$FAT'"
