# One-stop signed selector prototype and SD-card audit

**Date:** 2026-10-17

**Status:** Host-side FIT-selection prototype passed; SD card copied and audited read-only. The integrated U-Boot menu, boot-chain root of trust, and physical ZCU102 paths remain unvalidated.

## What is now confirmed

The workstation detected the ZCU102 card as `/dev/mmcblk0p1`, label `BOOT`, a 58.2 GB FAT partition mounted read-only at `/media/opentitan/BOOT`. I copied every file into `results/sd_card_host_backup_20261017/`. `diff -qr` reported no differences between the mounted source and the backup. The backup's `SHA256SUMS` records each copied file. The card itself was not modified.

The current card's `BOOT.BIN` SHA-256 is `f64730ce205bbfb5de28bcf44c13d3511adaa6b4b47d34a284178c95fc90c39e`, matching `results/task2e_sustainable_runner_20261016/BOOT_AXI_SUSTAINED_20261016.BIN` byte-for-byte. `bootgen -read` identifies an FSBL, the ratio-2 J55 bitstream, and the sustained SPI-test ELF. Its partition records have `ac_offset=1`; the displayed authentication-certificate sections contain no certificate data. This image is not evidence of an authenticated boot chain.

The card also contains the Linux `image.ub`, SHA-256 `446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0`, matching the previously audited unsigned FIT. Its required-key signature check failed because it has no signature subnode. `boot.scr` matches the prior generic distro-boot script hash `6c555e630e15ae1c7446f606cb99cfe5c52a0fde4e9deb2fa4e418c5d598b608`. Thus the card retains both the current bare-metal test image and old Linux files, but does not yet contain a working signed selector.

## Signed two-mode selection prototype

The new reproducible host test is `scripts/task2g_signed_selector_sandbox_test.py`. It creates a temporary RSA key, builds a FIT with separate Linux and standalone SPI-test configurations, embeds the public key as required in the U-Boot control FDT, and selects each configuration through U-Boot 2025.01-Xilinx sandbox `bootm`.

Both configurations passed `fit_check_sign`; sandbox accepted the signed Linux selection and loaded the standalone firmware selection with `autostart=no`. After a byte in the standalone payload was changed, sandbox rejected that selection before transfer. Raw logs, signed/tampered FIT files, the test control FDT, summary, and checksums are in `results/task2g_signed_selector_sandbox_20261017/`.

The signed FIT hash is `c05259459ec16450b1aad9ef370d3ec3fb51641da864ba5e5d3966332f91ebb2`. The test ELF is a fixture: no application code executed in the host sandbox. This proves that one required-key FIT can carry both selection types and that selected payload integrity is enforced by `bootm`; it does not test menu display, A53 execution, Linux boot, or SPI on the board.

## Security boundary and next work

This does not yet meet the requested secure one-stop boot. The U-Boot sandbox test uses a trusted control FDT supplied directly to the host process. The live card's U-Boot/FSBL chain has not been shown to be authenticated by the ZynqMP BootROM root of trust. A required FIT key only protects programs after trusted U-Boot starts. The menu must also be fixed in authenticated U-Boot policy: standard U-Boot boot-menu entries are read from environment variables, so a persistent or externally supplied environment must not be able to replace the choices or launch unsigned paths. The FIT must not be bypassed through generic distro scripts, raw `booti`/`bootelf`, or mutable external programs.

Next, integrate a fixed Linux/SPI-test selector into the target U-Boot build, place the Linux console and its test tools inside the signed Linux payload, and package the current menu-driven bare-metal ELF as a signed standalone FIT configuration. Validate the exact generated U-Boot control FDT and all negative cases in sandbox. Only then prepare a separate candidate card image and run the paths on the ZCU102. Keep the original `BOOT.BIN`, `image.ub`, and U-Boot environment backup unchanged. Do not report hardware-rooted secure boot without verifying the BootROM key policy and the complete FSBL-to-U-Boot trust chain.

## Reproduction

```sh
python3 scripts/task2g_signed_selector_sandbox_test.py
```

The test requires `.build/uboot-task2g-sandbox`, produced by the documented Task 2g U-Boot sandbox build. It refuses to overwrite an existing results directory and generates its private test key under a temporary directory that is removed on exit.
