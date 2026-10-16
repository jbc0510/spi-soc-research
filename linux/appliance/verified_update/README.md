# Task 2g verified-boot and A/B implementation work

This directory is the implementation track for the SOW Task 2g requirements to keep the appliance bootable after an interrupted/corrupted update and verify software integrity before execution. It is separate from the Task 2d design report and the user-space contrast demo.

## Verified FIT prototype

The host test builds the matching Xilinx U-Boot 2025.01 sandbox with required RSA FIT signatures, signs a fixture, and executes `bootm` in that sandbox. The acceptance conditions are: the correctly signed configuration reaches the sandbox's Linux handoff; an unsigned configuration fails with `Failed to verify required signature`; a modified kernel payload fails with `Bad Data Hash` before handoff. The private test key is generated in a temporary directory and removed after the run.

The sandbox proves U-Boot's FIT verifier behavior. It does not prove that the ZCU102 BootROM authenticates the FSBL, that the target's U-Boot contains the public key, that the public key is protected, or that the test board boots the result.

The PetaLinux 2025.2 project now uses the exact validated September 29 XSA and has a signed kernel/DTB/initrd FIT. Its deployed bitstream hash matches the XSA bitstream, and the signed FIT's DTB matches the regenerated system DTB. The matching U-Boot control DTB contains the required `msu2-test` public key; U-Boot `fit_check_sign` accepts the image but rejects a modified kernel payload. See `results/SOW_2G_PETALINUX_FIT_20261015.md` and `results/task2g_petalinux_fit_20261015/` for raw host evidence. This is an image-integrity result; it is not target boot or hardware-rooted secure-boot proof. The PetaLinux build wrapper also reported unrelated exit-139 packaging failures, documented in the raw logs.

## Target architecture under implementation

The intended prototype keeps immutable boot firmware and redundant boot-control metadata separate from two system slots. Each slot contains one signed FIT holding the kernel, device tree and initrd. U-Boot selects the confirmed slot by default and selects the staged trial slot only after the inactive slot has been written, flushed and verified. A bounded trial boot uses persistent U-Boot bootcount; Linux confirms the trial only after the benchmark application's SPI loopback health check. If verification fails before handoff, U-Boot returns to the confirmed slot; if a trial boot fails after handoff, the boot counter triggers rollback on the next reset.

The existing evidence establishes redundant U-Boot environment files and Linux-side libubootenv on a prior SD image, but it does not establish that these settings match the currently loaded target image. Therefore, the board partition map, U-Boot environment backend, device-tree boot media, and available watchdog behavior must be re-audited before enabling the target update path.

`CONFIG_BOOTCOUNT_LIMIT` is enabled in the new U-Boot build, but this change does not configure slot variables or establish a persistent bootcount/rollback policy on the target. The external PetaLinux project's original config files were preserved and hashed in `.build/task2g_petalinux_config_backup/`; repository templates are under `petalinux/`. The development key is disposable and must not be promoted to production.

## Trust anchor boundary

The host test's RSA key is disposable. Production keys must be generated and protected under the project owner's approved key-management process. U-Boot's FIT public key must be authenticated by the earlier boot chain. A public key compiled into an unauthenticated U-Boot binary does not establish secure boot. AMD's RSA/eFUSE root-of-trust configuration is a separate provisioning action; the project must preserve a recoverable development unit until that procedure is approved and validated.

No SD partition, U-Boot environment, BOOT.BIN, eFUSE, or running board state is changed by this prototype.

## Reproduction

Build the U-Boot 2025.01-Xilinx revision identified in `results/SOW_2G_UBOOT_FIT_SANDBOX_20261015.md` into `.build`, then run:

```sh
scripts/build_task2g_uboot_sandbox.sh .build/uboot-task2g-source .build/uboot-task2g-sandbox
python3 scripts/task2g_uboot_fit_sandbox_test.py \
  --source-dir .build/uboot-task2g-source \
  --build-dir .build/uboot-task2g-sandbox
```

The captured sandbox run and hashes are under `results/task2g_uboot_fit_sandbox_20261015/`.
