# Flashing BOOT_baremetal.bin (bare-metal SPI benchmark)

FSBL + bare-metal SPI1 benchmark app for SD boot. Built because JTAG dow could
not load the app into DDR (low-memory remap); the FSBL does DDR init + load.

## On jerry0510
1. git pull
2. Insert ZCU102 SD card.
3. Back up Linux boot: cp <SD_BOOT>/BOOT.BIN <SD_BOOT>/BOOT.BIN.linux-backup
4. Copy ours: cp sd-images/baremetal/BOOT_baremetal.bin <SD_BOOT>/BOOT.BIN
5. sync, eject, card to ZCU102.
6. SW6 = OFF,OFF,OFF,ON (SD boot).
7. Power on. FSBL loads app to 0x100000, hands off at EL3.

## Restore Linux: cp <SD_BOOT>/BOOT.BIN.linux-backup <SD_BOOT>/BOOT.BIN

## Capture results (on stile, board running, JTAG-attach after boot)
App runs ~15-20s (NUM_TRIALS=20) then idles; results[] persists in DDR.
  targets 13 ; stop
  mrd 0x10e2d8 1   # g_done, want 0x0000d09e
  mrd 0x10e178 88  # results: 11 x (4x u64 LE) min,max,avg,stddev ns
Decode avg_ns/1000 -> us, diff vs results/emio_results.csv.
Addresses are the 0x100000-relink: results@0x10e178 g_done@0x10e2d8.
