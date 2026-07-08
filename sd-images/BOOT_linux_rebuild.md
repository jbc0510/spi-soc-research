# BOOT_linux_rebuild.bin — build record

Built: 2026-07-08 13:38 UTC
Tool: /tools/Xilinx/2025.1/Vitis/bin/bootgen (v2025.1)
BIF:  sd-images/linux_rebuild.bif

## Components and md5sums

| Role    | File                                              | md5                              |
|---------|---------------------------------------------------|----------------------------------|
| FSBL    | sd-images/baremetal/fsbl_good.elf                 | a31a3b023d380757d9c8255f633d5679 |
| PMU     | sd-images/baremetal/pmufw_good.elf                | 34e313421653529b4956fb319f76a5d6 |
| BL31    | zcu102-spidev/images/linux/bl31.elf               | 98c810e2784bb6134fae1862cf53f2ef |
| U-Boot  | boot-package-tmp/u-boot-dtb.elf                   | dc0145e76935c4be530301415b13b3c9 |

## Output
BOOT_linux_rebuild.bin  md5: d0e6d7391db1343539ea2d59160c095c  size: 1.7M

## Notes
- fsbl_good.elf is identical to zcu102-spidev/images/linux/zynqmp_fsbl.elf (same md5)
- pmufw_good.elf is identical to zcu102-spidev/images/linux/pmufw.elf (same md5)
- u-boot-dtb.elf taken from boot-package-tmp (Mar 20 build) — same version as
  original sd-images/BOOT.BIN (proven bootable on this board)
- BOOT.BIN (original, a25d654) retained unchanged as reference
- image.ub (ffe0c75b) unchanged — spidev-enabled kernel, used with this BOOT.BIN
- Silicon validation pending: flash to SD, boot to Linux login prompt
