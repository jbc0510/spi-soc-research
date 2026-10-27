# Task 2g — live ZCU102 boot-chain audit

**Disposition:** The ZCU102 is running the previously validated AXI Quad SPI bitstream, but its active Linux boot path does not provide the signed-image or fail-closed behavior needed for Task 2g. The live board uses the stock PetaLinux 2025.1 `boot.scr` and an unsigned `image.ub`; its active U-Boot environment scans multiple boot targets and has no `bootlimit`/`upgrade_available` trial settings. No boot media, FPGA configuration, U-Boot environment, or persistent board state was changed.

## Confirmed on the board

The serial console identified `newQspi`, Linux `6.12.10-xilinx-g0a0f70e531c7`, and PetaLinux `2025.1+release-S05180137`. The kernel command line is `earlycon console=ttyPS0,115200 root=/dev/ram0 rw spidev.bufsiz=1048576`. The target clock reports an old system time (January 2025) while the SD artifacts carry 2026 timestamps; treat target time as untrusted for dating tests.

The kernel log says it loaded `/lib/firmware/msu2_ratio2_j55_c27bb684.bit.bin`; its SHA-256 is `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`, and `/sys/class/fpga_manager/fpga0/state` is `operating`. That hash matches the validated September 29 `.bit.bin` artifact. The separately captured Xilinx `.bit` container has a different file hash because it wraps metadata and stores 32-bit words in the opposite byte order. `python3 scripts/task2g_compare_xilinx_bit_payload.py --bit sd-images/baremetal/axi_ratio2_20260929/spi_ratio2_j55_wrapper.bit --bit-bin results/ratio2_j55_lvcmos33_20260929/spi_ratio2_j55_wrapper.bit.bin` verifies that reversing each payload word yields byte-for-byte equality with the validated `.bit.bin`; the machine-readable result is `bit_payload_identity.json`.

The active SD card exposes one partition, `/dev/mmcblk0p1`, mounted at `/run/media/BOOT-mmcblk0p1`; Linux itself runs from `/dev/ram0`. Board hashes are:

| File | SHA-256 | Finding |
|---|---|---|
| `BOOT.BIN` | `56db96f7530aa9cf4008d5494f1e1497d6fb6e76ece965d820b99b017e1539de` | Does not match the host-built PetaLinux 2025.2 BOOT container in this repo |
| `boot.scr` | `6c555e630e15ae1c7446f606cb99cfe5c52a0fde4e9deb2fa4e418c5d598b608` | Byte-identical to the audited stock boot script |
| `image.ub` | `446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0` | Byte-identical to repo `sd-images/image.ub`; required-key verifier reports no signature subnode |
| `system.dtb` | `687ae4bc9b543e934554ae0b2ee00e14b2c5ddce61a74da46f728fad912af9f8` | Live SD artifact |
| loaded FPGA firmware | `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd` | Matches the validated `.bit.bin` |

Read-only `fw_printenv` access used the already-present SD copy of `fw_printenv` and `libubootenv`, with a temporary config and library links under `/tmp`. The reported active values include:

```text
bootcmd=run distro_bootcmd
boot_targets=mmc0 jtag mmc0 mmc1 qspi0 nand0 usb0 usb1 scsi0 pxe dhcp
bootdelay=5
modeboot=sdboot
bootseq=0
bootlimit=<unset>
upgrade_available=<unset>
```

The root filesystem has no `fw_setenv`; the SD partition contains `uboot.env` and `uboot-redund.env`. No environment variables were changed. A host U-Boot `fit_check_sign` run against the live `image.ub` and the required-key control DTB failed with `No 'signature' subnode found` and `Failed to verify required signature 'key-msu2-test'`. Captured output and exit status are in `active_image_signature_check.log` and `active_image_signature_check_status.json`. This demonstrates the current SD FIT is unsigned; it does not demonstrate what the unmodified board U-Boot would do with the new host-built image.

## Conclusion and next work

The board currently has the validated SPI PL bitstream, while its active software boot chain is the prior PetaLinux 2025.1 image and generic distro boot policy. The signed PetaLinux 2025.2 host build has not been installed or booted. Its `BOOT.BIN` differs from the active board's `BOOT.BIN`, and the board's active U-Boot public-key policy is not yet established. Do not claim secure boot, signed target boot, A/B recovery, or Task 2g closure.

The next safe engineering step is to integrate a fixed FIT-only `bootcmd` into the actual PetaLinux U-Boot configuration, remove the generic script/extlinux/EFI/raw-kernel bypasses, confirm the selected SD medium and partition map, and exercise signed/unsigned/tampered/rollback cases in U-Boot sandbox. Only after that should a spare or recoverable SD image be prepared for a controlled target boot. Root-of-trust provisioning and power-loss testing remain outstanding.

## Evidence and reproducibility

`serial_session.log` is the raw console capture. `SHA256SUMS` covers the report, raw console capture, bit-payload identity result, and required-key signature-check logs. `python3 -m unittest discover -s tests -p 'test_task2g_bit_payload.py' -v` tests Xilinx `.bit` parsing and 32-bit word byte reversal. The live target commands were read-only apart from temporary `/tmp` symlinks and `/tmp/fw_env.config`; the serial session has been closed after capture.
