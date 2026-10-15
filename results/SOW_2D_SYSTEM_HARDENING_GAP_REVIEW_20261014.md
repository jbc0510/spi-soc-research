# SOW Task 2d — System Hardening Gap Review

**SOW activity:** “System Hardening — Design a minimal software environment that supports secure boot, reliable updates, and automated recovery mechanisms.”

**Disposition:** Task 2d remains open. The repository contains a measured U-Boot environment fallback demonstration, but no evidence of a hardened and deployable Linux appliance with verified boot, atomic image updates, or automatic recovery across the boot image and root filesystem.

## Confirmed evidence

- The Linux SPI benchmark ran on the ZCU102 with an initrd root filesystem. The Linux build configuration in the available PetaLinux project selects `CONFIG_SUBSYSTEM_ROOTFS_INITRD=y`, and its generated boot arguments use `/dev/ram0`.
- The September 2026 recovery test corrupted the CRC of the preferred U-Boot environment copy. U-Boot selected the remaining valid copy and preserved the marker value. This establishes a bounded fallback behavior for one environment copy.
- U-Boot did not repair the corrupted environment copy after boot. The same report records a silent fallback, one trial, and no test of `image.ub`, kernel, or rootfs update interruption.
- The recorded configuration reports `CONFIG_FIT_SIGNATURE` unset. The deployed test environment therefore has no verified FIT boot evidence.
- The Linux-side `fw_printenv` utilities were copied to temporary storage and were not included in the initrd image; the environment editing configuration also did not persist across reboot.

## Current security and recovery boundary

The environment-copy fallback should be described as recovery evidence for U-Boot environment CRC corruption only. It is not verified boot: the code and boot assets have no demonstrated chain of trust rooted in an immutable key. It is not a reliable software update mechanism for `BOOT.BIN`, `image.ub`, kernel, device tree, or root filesystem. It is not automated recovery because the invalid copy remains corrupted and no service detects or repairs the lost redundancy.

The SOW separately names “Minimal Appliance Development and Security” later in Task 2. That clause overlaps secure-boot and update themes; this review keeps the activities distinct by mapping Task 2d to hardening and recovery requirements and reserving deployable-minimal-rootfs and integrity implementation to Task 2g. Evidence is not counted twice as criterion closure.

## Work required to close Task 2d

1. Define a trust model and threat boundary, including the immutable trust anchor and key enrollment procedure. Do not burn ZynqMP eFuses as part of an unreviewed experiment.
2. Build a signed boot chain with the intended signature-verification options enabled in the actual bootloader, and show acceptance of an authentic image and rejection of a modified image on a test target.
3. Design a redundant or A/B update layout with atomic slot selection, health confirmation, and rollback after failed boot; include `BOOT.BIN`, kernel, device tree, and rootfs in the scope.
4. Add detection and repair for a damaged update slot or environment record, and test interruption/corruption at relevant write stages.
5. Repeat recovery trials and preserve before/after hashes, boot logs, firmware/kernel configuration, and the exact SD-image manifest.

## Workstation inventory observation

A PetaLinux 2025.2 project is present outside this repository at `/home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux`. Its generated project config is available for read-only inspection and currently selects initrd rootfs. The project occupies about 23 GB and is outside this repository’s writable workspace; this review did not modify it, build from it, write to the SD card, or change the ZCU102.

## Sources

- Governing SOW: `/home/opentitan/Downloads/MSU-2_SOW_Final (1).docx`, revision 2026-02-23.
- `results/SOW_2G_RECOVERY_20260909.md`
- `results/SOW_2G_FWENV_20260908.md`
- PetaLinux generated configuration: `/home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux/project-spec/configs/config`
- PetaLinux generated boot image manifest: `/home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux/images/linux/bootgen.bif`

This is an evidence and gap review, not a claim that Task 2d is complete.
