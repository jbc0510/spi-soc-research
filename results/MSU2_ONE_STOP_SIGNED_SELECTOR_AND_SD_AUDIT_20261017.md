# One-stop signed selector prototype and SD-card audit

**Date:** 2026-10-17

**Status:** The signed two-mode FIT passes required-key checks and tamper rejection. The fixed menu is compiled in the actual PetaLinux ZynqMP U-Boot build. The initial full candidate, corrected full candidate, custom no-PL candidate, and stock PetaLinux no-PL candidate have all been tried; the operator reports the same partial UART text (`Zynq MP First St...`) and no U-Boot banner. Removing the PL partition and replacing the selector U-Boot/system DTB with stock copies did not change the reported symptom. Host Bootgen readback shows the no-PL images' FSBL and PMUFW partition metadata match the platform-generated PetaLinux boot image. The failure point remains unknown because there is no host-side raw UART capture or processor execution-state evidence. The BootROM-to-U-Boot chain remains unauthenticated.

## What is now confirmed

The workstation detected the ZCU102 card as `/dev/mmcblk0p1`, label `BOOT`, a 58.2 GB FAT partition. I copied every original file into `results/sd_card_host_backup_20261017/`; `diff -qr` reported no differences and `SHA256SUMS` records each file. The partition was initially read-only. After building and checking the candidate, I remounted it read-write, preserved the original boot image as `BOOT.BIN.pre_task2g_20261017`, installed the candidate `BOOT.BIN` and `msu2-dual-mode.itb`, verified their hashes, and cleanly unmounted the card.

The original `BOOT.BIN` (now preserved on-card as `BOOT.BIN.pre_task2g_20261017`) had SHA-256 `f64730ce205bbfb5de28bcf44c13d3511adaa6b4b47d34a284178c95fc90c39e`, matching `results/task2e_sustainable_runner_20261016/BOOT_AXI_SUSTAINED_20261016.BIN` byte-for-byte. Its `bootgen -read` output identified an FSBL, the ratio-2 J55 bitstream, and the sustained SPI-test ELF. Its partition records had `ac_offset=1`; the displayed authentication-certificate sections contained no certificate data. This original image was not evidence of an authenticated boot chain.

The card's Linux `image.ub` remains unchanged at SHA-256 `446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0`, matching the previously audited unsigned FIT. Its required-key signature check fails because it has no signature subnode. `boot.scr` matches the prior generic distro-boot script hash `6c555e630e15ae1c7446f606cb99cfe5c52a0fde4e9deb2fa4e418c5d598b608`. The card now also has the new `msu2-dual-mode.itb` and selector BOOT.BIN; the original BOOT.BIN remains available for recovery.

## Signed two-mode selection prototype

The new reproducible host test is `scripts/task2g_signed_selector_sandbox_test.py`. It creates a temporary RSA key, builds a FIT with separate Linux and standalone SPI-test configurations, embeds the public key as required in the U-Boot control FDT, and selects each configuration through U-Boot 2025.01-Xilinx sandbox `bootm`.

Both configurations passed `fit_check_sign`; sandbox accepted the signed Linux selection and loaded the standalone firmware selection with `autostart=no`. After a byte in the standalone payload was changed, sandbox rejected that selection before transfer. Raw logs, signed/tampered FIT files, the test control FDT, summary, and checksums are in `results/task2g_signed_selector_sandbox_20261017/`.

The signed FIT hash is `c05259459ec16450b1aad9ef370d3ec3fb51641da864ba5e5d3966332f91ebb2`. The test ELF is a fixture: no application code executed in the host sandbox. This proves that one required-key FIT can carry both selection types and that selected payload integrity is enforced by `bootm`; it does not test menu display, A53 execution, Linux boot, or SPI on the board.

## Security boundary and next work

This does not yet meet the requested secure one-stop boot. The U-Boot sandbox test uses a trusted control FDT supplied directly to the host process. The live card's U-Boot/FSBL chain has not been shown to be authenticated by the ZynqMP BootROM root of trust. A required FIT key only protects programs after trusted U-Boot starts. The menu must also be fixed in authenticated U-Boot policy: standard U-Boot boot-menu entries are read from environment variables, so a persistent or externally supplied environment must not be able to replace the choices or launch unsigned paths. The FIT must not be bypassed through generic distro scripts, raw `booti`/`bootelf`, or mutable external programs.

The custom no-PL diagnostic is installed as `BOOT.BIN`; it was reported to show the same partial banner. Its hash is `53f10f813fcc3b934710a5a6d05dd1f417ff3e73ae0475b8799d336f63113455`. The previous full selector image is preserved as `BOOT.BIN.full_selector_failed_20261017` (SHA-256 `8662dc9f693fcec9536d479a55f96ac50b76f6fb8b3edc6b4324244408e25b25`); the original remains `BOOT.BIN.pre_task2g_20261017` (SHA-256 `f64730ce205bbfb5de28bcf44c13d3511adaa6b4b47d34a284178c95fc90c39e`). `image.ub` remains unchanged at SHA-256 `446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0`. The card install record is `results/task2g_fsbl_handoff_diagnostic_20261017/sd_card_install.log`. Bootgen readback shows matching FSBL and PMUFW partition checksums, addresses, and attributes between this diagnostic and the platform-generated PetaLinux boot image. That verifies package metadata consistency for these stages, not successful execution on silicon. The reported result means PL configuration is not required to reproduce the symptom; it does not establish the exact failing stage.

The stock no-PL diagnostic `results/task2g_stock_no_pl_diagnostic_20261017/BOOT_STOCK_NO_PL_DIAGNOSTIC.bin` used the platform-generated U-Boot and system DTB with the same FSBL/PMUFW/BL31 and no PL partition. It was installed as `BOOT.BIN` and reportedly showed the same partial banner. This makes the custom selector U-Boot and PL bitstream less likely to be the sole cause, but does not identify the failure. The next useful action is to keep the UART terminal open and reset the board once, capturing all output from the first byte; the current host cannot see `/dev/ttyUSB0`. Its image hash is `2a10ff5726003b99992f588a66246842dc40e8bd8320f63f09926568d157ffb2`.

## Current dual-mode FIT candidate and menu configuration

`scripts/task2g_build_dualmode_fit.py` now builds a candidate FIT from the current card's `image.ub` and the unified menu ELF. It retains the current Linux kernel, system device tree, initramfs, and PL overlay as FIT payloads; signs the Linux, SPI-test, and PL-overlay configurations; embeds a required `msu2-test` public key in a copy of the U-Boot control DTB; and checks each configuration. The test flips one byte in the standalone SPI payload and requires the signature check to fail. The private key stays outside the repository and is never copied into the output.

Reproduction on this workstation:

```sh
python3 scripts/task2g_build_dualmode_fit.py \
  --source-fit results/sd_card_host_backup_20261017/image.ub \
  --spi-elf bare_metal/vitis/spi_axi_bm_unified_menu_20261017c/workspace/spi_axi_bm_app/build/spi_axi_bm_app.elf \
  --keys /home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux/build/conf/msu2-dev-signing \
  --control-dtb results/task2g_petalinux_fit_20261015/u-boot-control.dtb \
  --dumpimage .build/uboot-task2g-sandbox/tools/dumpimage \
  --mkimage .build/uboot-task2g-sandbox/tools/mkimage \
  --fit-check-sign .build/uboot-task2g-sandbox/tools/fit_check_sign \
  --output-dir results/task2g_dualmode_repro_20261017
```

The result is recorded in `results/task2g_dualmode_repro_20261017/summary.json` and `SHA256SUMS`. Source FIT SHA-256 is `446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0`; source SPI ELF SHA-256 is `9a1b1455a0b4255429e9c767db2f8ab7d0a54bc1bfa8b2f67bce75a85794c067`; signed FIT SHA-256 is `e6d065f82305e5216a3613e92b42d4749870f67c1df7b19bef950339d952a5ad`. The FIT host utility verified `linux`, `spi-test`, and `pl-overlay`; the tampered SPI payload was rejected.

The U-Boot sandbox payload-selection and tamper check can be repeated with:

```sh
python3 scripts/task2g_sandbox_boot_dualmode_fit.py \
  --source-fit results/task2g_dualmode_repro_20261017/msu2-dual-mode.itb \
  --sandbox-uboot .build/uboot-task2g-menu-sandbox/u-boot \
  --sandbox-control-template .build/uboot-task2g-menu-sandbox/arch/sandbox/dts/test.dtb \
  --keys /home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux/build/conf/msu2-dev-signing \
  --dumpimage .build/uboot-task2g-sandbox/tools/dumpimage \
  --mkimage .build/uboot-task2g-sandbox/tools/mkimage \
  --output-dir results/task2g_dualmode_sandbox_20261017
```

It writes a separate sandbox-architecture FIT; the five payloads are extracted unchanged from the target candidate and their hashes are recorded in `results/task2g_dualmode_sandbox_20261017/summary.json`. Linux handoff was accepted by sandbox, the SPI menu ELF loaded with autostart disabled, and the altered SPI FIT was rejected before loading. This is host-only evidence; that sandbox FIT must never be installed on the ZCU102.

The second check, `scripts/task2g_sandbox_boot_dualmode_fit.py`, repackages the five exact payload byte streams into a host-only FIT tagged for the sandbox architecture. U-Boot sandbox accepted the Linux selection (then reported that sandbox cannot execute Linux), loaded the real SPI menu payload with `autostart=no`, and rejected a tampered copy before firmware loading. The extracted payload hashes match the original FIT's kernel, device tree, overlay, root filesystem, and the signed FIT's SPI image hash. Results and raw logs are in `results/task2g_dualmode_sandbox_20261017/`. The sandbox-tagged FIT is a test fixture and is not for the board.

The fixed menu proposal is in `linux/appliance/verified_boot/u-boot/`. It compiles a static two-choice menu, disables persistent environment backends and distro boot discovery, requires signed FIT configurations, and resets if a selected image returns or fails. The Kconfig fragment resolved with `AUTOBOOT_MENU_SHOW` and `BOOTMENU_DISABLE_UBOOT_CONSOLE` enabled, `BOOTDELAY=-2`, no persistent environment backend, required FIT signature support, and legacy image format disabled. A U-Boot 2025.01-Xilinx sandbox build with the actual static environment compiled successfully. The compiled default variables were inspected; the menu displayed both labels plus Quit, omitted the U-Boot-console entry, and executed the requested benign option. Logs are `compiled_selector_env_test.log` and `compiled_menu_display_test.log` in the candidate results directory.

The selector was first compiled into a generic ZynqMP AArch64 U-Boot ELF as an isolated toolchain check. The actual PetaLinux project was then rebuilt on 2026-10-17 with the selector Kconfig and fixed environment. Its deployed U-Boot contains the two menu entries and the required-signature verification code. The PetaLinux build log is `results/task2g_dualmode_repro_20261017/target_uboot_build.log`; the source recipe and config backups are recorded alongside it. The target U-Boot ELF SHA-256 is `70498b6e1dfe8392d6e1ca75b8384b9a21c61f668d34ad01a11e9b2d9ba120d3`.

The real project `bootgen.bif` loads `system.dtb` at `0x00100000`, the same address used by the ZynqMP board's external-FDT configuration. The signed FIT public key was therefore inserted into the exact `system.dtb` supplied to the candidate Bootgen package, as a required `conf` key. The candidate U-Boot control-FDT copy reports `required=conf`; the packaged system-DTB partition was extracted back out of `BOOT_SIGNED_SELECTOR.bin` and has the same `required=conf` key. Against that extracted partition, all three FIT configurations verified and a tampered SPI payload was rejected. The packaged U-Boot partition contains the fixed Linux/SPI menu entries and FIT signature-verification error paths.

The separate Bootgen candidate is `results/task2g_dualmode_repro_20261017/BOOT_SIGNED_SELECTOR.bin`, SHA-256 `8436f5ddad8143e48cae82fa9c375a831e16839172e81d3ebb9cf7e8fee6e718`, size 28,282,008 bytes. Its BIF uses the validated September 29 J55 bitstream, SHA-256 `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`. Bootgen generated the image, and its `-dump` output confirms the FSBL, bitstream, BL31, system DTB, and U-Boot partitions. Bootgen also emitted a nonfatal overlap warning for the PL bitstream and the system-DTB address range; the partition records identify the bitstream destination as PL and the DTB load address as `0x00100000`. Bootgen authentication verification reports that the image is not authenticated, which confirms that the candidate does not establish a hardware root of trust. The candidate and signed FIT were copied to the card and re-hashed there; the old BOOT.BIN remains on-card as `BOOT.BIN.pre_task2g_20261017` and in the full host backup. The signed FIT SHA-256 is `e6d065f82305e5216a3613e92b42d4749870f67c1df7b19bef950339d952a5ad`.

The initial candidate and the corrected candidate were both reported by the operator as stopping at the same partial FSBL banner; no U-Boot banner or selector appeared. The host cannot currently access `/dev/ttyUSB0`, so no raw UART capture exists beyond the operator-provided terminal text. The exact stop point remains unresolved: the observation does not distinguish an FSBL partition-load/handoff failure from a later U-Boot console or execution failure. Host inspection confirms the target U-Boot ELF contains both selector labels and its deployed U-Boot DTB's `stdout-path` resolves to `serial0:115200n8` at `/axi/serial@ff000000`, matching the system DTB's serial path; this does not establish that U-Boot executed on the board.

The first candidate's PL partition used a byte-swapped `.bit.bin` as a Bootgen input. BootGen recorded its PL load address as `0x00000000` and warned that the PL partition's address range overlapped the system-DTB range. The freshly generated PetaLinux package instead records the PL load address as `0xffffffff`. This is a concrete packaging defect in the failed candidate and a plausible cause of the observed early stop, but the board log does not prove it was the root cause. A corrected candidate was packaged from the validated Xilinx `.bit` file using the target platform's `destination_cpu=pmu` PMUFW form. BootGen produced no overlap warning; the PL partition now has load address `0xffffffff`, length `0x0065216f`, and checksum `0xfecfb328`, exactly matching the PL partition metadata in the PetaLinux-generated package. The `.bit` input's payload was independently compared with the validated `.bit.bin`: reversing each 32-bit word reproduces the `.bit.bin` byte-for-byte. The reproducible packager is `scripts/task2g_package_signed_selector_bootbin.py`; it rejects non-`.bit` input, checks the PL load address and payload word count, rejects overlap warnings, and can confirm `.bit`/`.bit.bin` payload equivalence. The corrected package is `results/task2g_dualmode_package_script_20261017/BOOT_SIGNED_SELECTOR.bin`, SHA-256 `8662dc9f693fcec9536d479a55f96ac50b76f6fb8b3edc6b4324244408e25b25`.

The corrected candidate package has SHA-256 `8662dc9f693fcec9536d479a55f96ac50b76f6fb8b3edc6b4324244408e25b25`; it was installed on-card, but its subsequent boot was reported to stop at the same partial FSBL banner. The failed first candidate is preserved as `BOOT.BIN.selector_load0_failed_20261017` (SHA-256 `8436f5ddad8143e48cae82fa9c375a831e16839172e81d3ebb9cf7e8fee6e718`) and the original image as `BOOT.BIN.pre_task2g_20261017` (SHA-256 `f64730ce205bbfb5de28bcf44c13d3511adaa6b4b47d34a284178c95fc90c39e`). `image.ub` remains unchanged at SHA-256 `446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0`. The corrected candidate BOOT.BIN has no Bootgen authentication certificates, so FIT signatures are only checked after this U-Boot starts. Replacing U-Boot or its control FDT can bypass the prototype until a trusted ZynqMP boot chain is configured. Card installation hashes and actions are recorded in `results/task2g_dualmode_package_script_20261017/sd_card_install.log`.

## Controlled no-PL boot diagnostic prepared

To distinguish a failure associated with FPGA configuration from an earlier/later handoff problem, a diagnostic Bootgen image was built from the same FSBL, PMUFW, BL31, keyed system DTB, and selector-enabled U-Boot, while omitting the PL bitstream partition. The package was generated successfully with Bootgen 2025.1 and its `-read` log lists no PL partition. SHA-256: `53f10f813fcc3b934710a5a6d05dd1f417ff3e73ae0475b8799d336f63113455`. This image has not been installed or run on the board. A selector appearing with this image would implicate the PL configuration path as a contributing stage; the same failure would move attention to the FSBL-to-U-Boot chain or console path. Either result is diagnostic only and does not itself establish root cause. Build inputs and BIF are recorded in `results/task2g_fsbl_handoff_diagnostic_20261017/`.

## Reproduction

```sh
python3 scripts/task2g_signed_selector_sandbox_test.py
```

The test requires `.build/uboot-task2g-sandbox`, produced by the documented Task 2g U-Boot sandbox build. It refuses to overwrite an existing results directory and generates its private test key under a temporary directory that is removed on exit.
