# SD card / BootROM diagnostic — 2026-10-17

## Current finding

The ZCU102 reports `BOOT_MODE=0x0000000E` and `CSU_BR_ERROR=0x80004B00` over read-only JTAG. AMD UG1087 identifies `CSU_BR_ERROR` as the BootROM error register; the `BR_ERROR` flag is set and the error code is `0x4B00`. AMD's published support material associates BootROM error `0x4B` with no image found on SD/eMMC after the allowed search. The error register persists until PS_POR_B, so this alone does not timestamp the failure or prove it caused the currently observed UART fragment.

The host card mount `/media/opentitan/BOOT` contains the expected stock boot image with the validated J55 bitstream and expected Linux `image.ub`:

| File | SHA-256 | Result |
|---|---|---|
| `BOOT.BIN` | `604df48f3e98f70e849df14c26562514149359b9a2a9e5921e4fcd1428e9abea` | Matches verified stock platform image with validated PL |
| `image.ub` | `446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0` | Matches previously recorded Linux image |
| `boot.scr` | `6c555e630e15ae1c7446f606cb99cfe5c52a0fde4e9deb2fa4e418c5d598b608` | Generic PetaLinux U-Boot boot script |

The mounted volume is a single FAT32 partition (`PARTTYPE=0x0c`, `PARTUUID=13335a4f-01`) spanning the 58.2 GB card, beginning at sector 2048. Sysfs reports 122,138,624 sectors for the card and 122,136,576 sectors for partition 1, so the partition begins after the standard 2,048-sector (1 MiB) alignment gap and occupies the remainder of the card. The card block device reports `RO=0`; the mount currently appears read-only in this session. The expected boot files are visible at the filesystem root.

## Filesystem evidence

Host kernel logs repeatedly report:

- `FAT-fs (mmcblk0p1): Volume was not properly unmounted. Some data may be corrupt. Please run fsck.`
- `FAT-fs (mmcblk0p1): unable to read boot sector to mark fs as dirty`

This is evidence of an unclean FAT state, not proof that `BOOT.BIN` or its directory entry is corrupt. Hashes confirm the bytes of the visible files match their expected artifacts, but do not validate the FAT metadata or the card's full on-media consistency.

The kernel-log search returned no matching SD-card I/O-error lines; the recorded warnings concern the FAT volume's unclean state. This does not rule out errors outside the retained/query window.

## Limits and next diagnostic

The current command environment can read the mounted files and sysfs partition metadata but cannot open `/dev/mmcblk0` or `/dev/mmcblk0p1`; `/dev` contains no block-device nodes in this session and the UDisks D-Bus connection is denied. Direct partition-table and filesystem-check commands therefore cannot run here. Do not run a repair or reformat based on the current evidence. Before another board boot, perform a read-only FAT check (`fsck.fat -n`) with the card unmounted on a host session that has block-device access. Save the complete checker output. Only if the checker reports errors should repair be considered, after preserving a full card image and its current contents.

No files on the card were modified during this diagnostic.

## References

- [AMD UG1087 — CSU_BR_ERROR register](https://docs.amd.com/r/en-US/ug1087-zynq-ultrascale-registers/CSU_BR_ERROR-PMU_GLOBAL-Register?contentId=GlaVzNfJeAhgKU8ebnisfQ)
- [AMD UG1267 — SD1 boot mode pin value](https://docs.amd.com/api/khub/documents/g76en4BfB6qIp2gHDRkQxg/content)
- [AMD support article 000035536 — BootROM code 0x4B](https://adaptivesupport.amd.com/s/article/000035536?language=en_US)
