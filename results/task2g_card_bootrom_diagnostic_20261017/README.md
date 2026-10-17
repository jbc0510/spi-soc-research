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

## Read-only FAT check from the host terminal

The operator ran `sudo fsck.fat -n /dev/mmcblk0p1`. It reported a primary/backup boot-sector difference only at byte offset 65 (`0x01` vs `0x00`), reported the dirty bit, and ended with `Leaving filesystem unchanged.` The final count was `49 files, 13842/1907917 clusters`; no further file-allocation errors were printed. Because `-n` was used, the dirty bit remains set and the command made no changes. The operator did not include whether the partition had been unmounted before the scan, so treat the result as preliminary if it was mounted.

Microsoft's FAT32 specification identifies byte 65 (`BS_Reserved1`) as reserved. That supports treating this single-byte difference as likely non-functional, consistent with `fsck.fat` calling the differences mostly harmless; it does not prove the BootROM accepts the card's complete on-media layout. The scan lowers the likelihood of general FAT allocation damage, but it does not explain the BootROM's `0x4B00` report.

## Limits and next diagnostic

The current agent command environment can read mounted files and sysfs metadata but cannot open `/dev/mmcblk0` or `/dev/mmcblk0p1`; `/dev` contains no block-device nodes and UDisks D-Bus access is denied. The operator's host-side `fsck.fat -n` result is now available, so do not repeat the same check. Do not repair or reformat based on this evidence alone. The next decisive diagnostic is a controlled BootROM/SD read test using a cleanly unmounted card and a fresh UART capture, with a raw image backup first if any filesystem repair is attempted.

After the host-side check, the card mount is no longer visible in this agent session. A repeated read-only XSCT/JTAG query returned an empty target list, so there is no live board register or UART state available at this moment. This should be treated as unavailable hardware access, not as a new board failure.

## Live board probe after the operator reconnected the SD card

The operator then observed the same repeated partial FSBL UART prefix. A read-only JTAG scan now sees the PS TAP, PMU, and PL targets, but reports `PS TAP (Cannot poll JTAG port: CBR not done, debug access not allowed)`. The APU/processor debug target is not exposed. The PMU target is visible, but XSCT memory reads fail with `MDM master access port not found`; no registers were changed. This establishes that CPU debug access is gated at the current boot stage. It is consistent with the earlier BootROM error, but does not independently prove which stage emitted the partial UART text or identify why SD image search failed.

No Linux SPI or AXI test can run in this state; the Linux kernel and selector menu have not been reached. The next discriminating test is to boot with the SD volume's dirty flag cleared after preserving its contents, then capture the complete UART output from reset. The prior `fsck.fat -n` did not clear the dirty flag.

No files on the card were modified during this diagnostic.

## Complete pre-check card image and offline boot-file verification

Before removing the card, a full raw image was created with `dd`. The first attempt was interrupted after 4,244,635,648 bytes; it was resumed at block 253 with `skip=253 seek=253 conv=notrunc,fsync` and completed with 62,534,975,488 bytes, exactly the device capacity reported by `lsblk`. The image is `/tmp/msu2_zcu102_sd_pre_fsck_20261017.img`. It is a host-side recovery copy and is not stored in this repository. Its whole-image SHA-256 check has not yet returned.

`fdisk -l` on the image confirms an MBR with one bootable FAT32-LBA partition, starting at LBA 2048 and ending at LBA 122138623. The partition boot sector has signature `55 aa` and a FAT32 BPB (512 bytes/sector, 64 sectors/cluster, 64 reserved sectors, two FATs, 14912 sectors/FAT, root cluster 2, backup boot sector 6). The FAT32 root directory was read directly from the image without mounting or writing it. The boot files extracted from that image have these hashes:

| File in card image | Bytes | SHA-256 | Comparison |
|---|---:|---|---|
| `BOOT.BIN` | 28,290,844 | `604df48f3e98f70e849df14c26562514149359b9a2a9e5921e4fcd1428e9abea` | Matches the previously verified stock platform image with the validated PL bitstream |
| `IMAGE.UB` | 55,510,056 | `446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0` | Matches the previously recorded Linux image |
| `BOOT.SCR` | 3,833 | `6c555e630e15ae1c7446f606cb99cfe5c52a0fde4e9deb2fa4e418c5d598b608` | Matches the previously recorded boot script |

The card was reinserted in the ZCU102 and the operator again observed repeated `Zynq MP First St` UART fragments without Linux output. Thus the captured boot-file contents match the expected artifacts, but boot still fails before Linux; the raw-image inspection does not test FAT metadata acceptance by BootROM or prove the cause. A read-only host `fsck.fat` rerun could not proceed because `sudo` required an interactive password unavailable to this session. No repair was attempted, and the complete image preserves the pre-repair state.

## FAT repair and boot-file revalidation

With the SD card back in the host, the operator ran `sudo fsck.fat -a -v /dev/mmcblk0p1` while the partition was unmounted. The checker again reported the primary/backup boot-sector byte-65 difference (`0x01/0x00`), reported the dirty bit, automatically removed the dirty bit, checked the free-cluster summary, and ended with `*** Filesystem was changed ***`, `Writing changes.`, and `49 files, 13842/1907917 clusters`. No lost-file recovery or other allocation error was reported. This repair was made only after the complete raw pre-repair image was captured.

The partition was then mounted for evidence collection, and the three boot-file hashes after repair still match the values extracted from the pre-repair image: `BOOT.BIN` `604df48f3e98f70e849df14c26562514149359b9a2a9e5921e4fcd1428e9abea`, `image.ub` `446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0`, and `boot.scr` `6c555e630e15ae1c7446f606cb99cfe5c52a0fde4e9deb2fa4e418c5d598b608`. No files were intentionally modified during this hash check, and the partition was unmounted before returning the card to the board. A second `fsck.fat -n` verification was attempted from the agent session but could not pass the host's interactive sudo prompt. The result of the next board boot is not yet known; clearing the dirty bit has not yet been shown to resolve the boot loop.

## References

- [AMD UG1087 — CSU_BR_ERROR register](https://docs.amd.com/r/en-US/ug1087-zynq-ultrascale-registers/CSU_BR_ERROR-PMU_GLOBAL-Register?contentId=GlaVzNfJeAhgKU8ebnisfQ)
- [AMD UG1267 — SD1 boot mode pin value](https://docs.amd.com/api/khub/documents/g76en4BfB6qIp2gHDRkQxg/content)
- [AMD support article 000035536 — BootROM code 0x4B](https://adaptivesupport.amd.com/s/article/000035536?language=en_US)
- [Microsoft FAT32 specification (PDF mirror), Extended BPB field at offset 65](https://www.scs.stanford.edu/~zyedidia/docs/_other/fat.pdf)
