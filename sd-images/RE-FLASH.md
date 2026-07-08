# Re-Flash a ZCU102 SD Card from sd-images/

The working boot image is backed up in this folder. A lost or new card is a
~10-minute job. There is no full-disk `.wic`; this builds the boot partition
from the loose files here.

## What's here

| File | Role |
|------|------|
| `BOOT.BIN` | FSBL + PMU + U-Boot + embedded bitstream |
| `image.ub` | FIT image: spidev-enabled kernel + ramdisk + DTB |
| `boot.scr` | U-Boot boot script (dated Mar 20 — see note) |
| `system.dtb` | Device tree (dated Mar 20 — see note) |
| `spi_benchmark_wrapper.bit.bin` | AXI SPI bitstream (FPGA-manager load) |
| `spi_benchmark_axi`, `_axi_ext`, `spi_loopback_test` | benchmark/test binaries |

> Note: `boot.scr` and `system.dtb` predate the May BOOT.BIN/image.ub. The
> current overlay-based flow may not use them (DTB is inside image.ub). Copy
> them for parity, but if a fresh card misbehaves where the original worked,
> suspect these two as stale leftovers first.

## Steps (on stile, blank microSD inserted)

```bash
# 1. IDENTIFY THE CARD — verify by size; wrong device wipes a real disk
lsblk                       # find the removable ~16-32 GB device
# run lsblk with the card OUT then IN and diff if unsure.
# Set DEV below (e.g. sdb or mmcblk0). DEV1 = first partition (sdb1 / mmcblk0p1).

DEV=sdX                     # <-- EDIT THIS

# 2. One bootable FAT32 partition
sudo wipefs -a /dev/$DEV
sudo parted /dev/$DEV --script mklabel msdos
sudo parted /dev/$DEV --script mkpart primary fat32 1MiB 100%
sudo parted /dev/$DEV --script set 1 boot on

# 3. Format (use ${DEV}1, or ${DEV}p1 for mmcblk*)
PART=${DEV}1                # <-- use ${DEV}p1 if DEV is mmcblkX
sudo mkfs.vfat -F 32 -n BOOT /dev/$PART

# 4. Copy boot files
sudo mkdir -p /mnt/sdboot
sudo mount /dev/$PART /mnt/sdboot
sudo cp ~/spi-soc-research/sd-images/{BOOT.BIN,image.ub,boot.scr,system.dtb} /mnt/sdboot/
sudo cp ~/spi-soc-research/sd-images/spi_benchmark_wrapper.bit.bin /mnt/sdboot/
sudo cp ~/spi-soc-research/sd-images/{spi_benchmark_axi,spi_benchmark_axi_ext,spi_loopback_test} /mnt/sdboot/

# 5. Flush + unmount
sync
sudo umount /mnt/sdboot
```

Set SW6 to SD boot (0010) and power on. Console:
`sudo picocom -b 115200 --noreset --flow n --lower-rts --lower-dtr /dev/ttyUSB0`
