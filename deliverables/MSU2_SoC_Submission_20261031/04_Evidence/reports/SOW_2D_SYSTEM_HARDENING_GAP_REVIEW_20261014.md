# SOW Task 2d — System Hardening Gap Review

**SOW activity:** “System Hardening — Design a minimal software environment that supports secure boot, reliable updates, and automated recovery mechanisms.”

**Disposition (corrected 2026-10-15): Task 2d's design criterion is complete** based on `SOW_2D_SYSTEM_HARDENING_DESIGN_20261014.md`. This gap review remains valid for implementation: the repository does not yet contain a deployed and hardware-validated appliance with verified boot, atomic image updates, or automatic recovery across the boot image and root filesystem. Those implementation gaps belong to the later minimal-appliance activity (Task 2g).

## Confirmed evidence

- The Linux SPI benchmark ran on the ZCU102 with an initrd root filesystem. The Linux build configuration in the available PetaLinux project selects `CONFIG_SUBSYSTEM_ROOTFS_INITRD=y`, and its generated boot arguments use `/dev/ram0`.
- The September 2026 recovery test corrupted the CRC of the preferred U-Boot environment copy. U-Boot selected the remaining valid copy and preserved the marker value. This establishes a bounded fallback behavior for one environment copy.
- U-Boot did not repair the corrupted environment copy after boot. The same report records a silent fallback, one trial, and no test of `image.ub`, kernel, or rootfs update interruption.
- The recorded configuration reports `CONFIG_FIT_SIGNATURE` unset. The deployed test environment therefore has no verified FIT boot evidence.
- The Linux-side `fw_printenv` utilities were copied to temporary storage and were not included in the initrd image; the environment editing configuration also did not persist across reboot.

## Current security and recovery boundary

The environment-copy fallback should be described as recovery evidence for U-Boot environment CRC corruption only. It is not verified boot: the code and boot assets have no demonstrated chain of trust rooted in an immutable key. It is not a reliable software update mechanism for `BOOT.BIN`, `image.ub`, kernel, device tree, or root filesystem. It is not automated recovery because the invalid copy remains corrupted and no service detects or repairs the lost redundancy.

The SOW separately names “Minimal Appliance Development and Security” later in Task 2. That clause overlaps secure-boot and update themes; this review keeps the activities distinct by mapping Task 2d to hardening and recovery requirements and reserving deployable-minimal-rootfs and integrity implementation to Task 2g. Evidence is not counted twice as criterion closure.

## Implementation work remaining under Task 2g

1. Implement the approved trust-anchor and key-enrollment procedure on a designated test unit; do not burn ZynqMP eFuses as an unreviewed experiment.
2. Build the signed boot chain with the intended signature-verification options enabled, then demonstrate acceptance of an authentic image and rejection of a modified image on the test target.
3. Implement the designed A/B layout with atomic slot selection, health confirmation, and rollback across `BOOT.BIN`, kernel, device tree, and rootfs.
4. Implement detection and repair for a damaged update slot or environment record, and test interruption/corruption at relevant write stages.
5. Repeat recovery trials and preserve before/after hashes, boot logs, firmware/kernel configuration, and the exact SD-image manifest.

## Workstation inventory observation

A PetaLinux 2025.2 project is present outside this repository at `/home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux`. Its generated project config is available for read-only inspection and currently selects initrd rootfs. The project occupies about 23 GB and is outside this repository’s writable workspace; this review did not modify it, build from it, write to the SD card, or change the ZCU102.

## Sources

- Governing SOW: `/home/opentitan/Downloads/MSU-2_SOW_Final (1).docx`, revision 2026-02-23.
- `results/SOW_2G_RECOVERY_20260909.md`
- `results/SOW_2G_FWENV_20260908.md`
- PetaLinux generated configuration: `/home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux/project-spec/configs/config`
- PetaLinux generated boot image manifest: `/home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux/images/linux/bootgen.bif`

This is an implementation gap review, not a claim that the proposed architecture has been deployed. It does not reopen Task 2d's completed design criterion.
