# Task 2g boot-flow audit

This audit examines the generated PetaLinux boot script and the default U-Boot boot policy used by the existing host build. It is a configuration review only; no boot artifact was written to or executed on the ZCU102.

## Finding

The compiled `boot.scr` first tries `image.ub` with `bootm`, but proceeds to load and boot separate `Image`, `system.dtb`, and optional ramdisk/rootfs images with `booti` if FIT boot returns. Its QSPI, NAND, and NOR paths likewise try `bootm` and then read raw kernel/initramfs payloads and invoke `booti`. The MMC/USB branch also imports `uEnv.txt` and runs its `uenvcmd`. The compiled default environment has `bootcmd=run distro_bootcmd` and searches `jtag mmc0 mmc1 qspi0 nand0 usb0 usb1 scsi0 pxe dhcp`. That path includes script, extlinux, and EFI discovery. A FIT-only `boot.scr` alone would not establish a fail-closed boot policy.

The generated U-Boot configuration has `CONFIG_BOOTCOUNT_LIMIT=y`, but the captured initial environment has no `bootlimit` or `upgrade_available` values. Enabling that Kconfig option alone does not establish a bounded A/B trial. The build has no configured persistent slot selector, health confirmation, or tested rollback policy. Those remain open; this report does not claim A/B recovery.

## Evidence and reproduction

`boot.scr` and `u-boot-initial-env.txt` are the generated PetaLinux deploy artifacts; trailing whitespace was removed from the text environment copy for clean review. `python3 scripts/task2g_audit_bootflow.py --input results/task2g_bootflow_audit_20261015/boot.scr --output results/task2g_bootflow_audit_20261015/audit.json` validates the legacy U-Boot script header, extracts its script text, and emits the fallback findings. `python3 -m unittest discover -s tests -p 'test_task2g_bootflow_audit.py' -v` checks that raw boot fallbacks and environment imports are detected, and that a FIT-only script is not flagged. The captured environment file records the broad `boot_targets`, distro boot command, and initial U-Boot variables.

The captured script hash and all evidence-file hashes are in `SHA256SUMS`. The audit is intentionally conservative and lexical: it identifies concrete bypass primitives, but does not emulate the complete U-Boot command interpreter or prove the behavior of every compiled environment path.

## Required next work

Create a PetaLinux-owned boot policy that permits only authenticated FIT boot from the selected slot, blocks untrusted environment and alternate-target paths, and halts recovery safely when verification fails. Then define and test persistent A/B state transitions (trial decrement, healthy confirmation, rollback, interrupted update). Verify the resulting boot artifact and behavior in U-Boot sandbox first; board execution remains outstanding until a console or network connection is available.
