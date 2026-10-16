# Task 2g — PetaLinux signed FIT build and tamper verification

**Disposition:** A signed FIT was built in the existing PetaLinux 2025.2 ZynqMP project. The matching U-Boot 2025.01-Xilinx verifier accepted the valid image using the public key in the generated U-Boot control DTB and rejected a one-byte kernel payload change before load. This closes the target-toolchain FIT-signing prototype step. It does not close Task 2g's trusted-boot chain or A/B recovery requirement.

## Build and verification

The existing project was configured with PetaLinux 2025.2, then its XSA was replaced with the authoritative September 29 export. The project XSA hash is `e8b4626edb5949bc8adb14ae259802cdd24b16ea3f02daf0dd8fdbeb1cc0e7d7`, exactly matching `results/ratio2_j55_lvcmos33_20260929/spi_ratio2_j55_wrapper.xsa`. The bitstream extracted from that XSA and the bitstream deployed by PetaLinux are byte-identical at SHA-256 `90f93479dd47c505b8f9e4fe6f4f18e853f8923d081f4b2037401ed3cb46994a`. The signed FIT's embedded Linux DTB has SHA-256 `61d6c8ec0c1a1e971b8c0a512247f5ab37097e00a7c842cc7b2edb34b7756f45`, matching the DTB regenerated from the imported XSA.

The build used `petalinux-build -c u-boot` and `petalinux-build -c kernel`. U-Boot compiled and deployed; its configure log confirms `CONFIG_FIT_SIGNATURE=y`, `CONFIG_BOOTCOUNT_LIMIT=y`, and legacy image format disabled. PetaLinux produced a kernel/DTB/initramfs FIT whose default configuration carries a `sha256,rsa2048:msu2-test` signature. The generated U-Boot control DTB contains `/signature/key-msu2-test` and the `required` property. Both wrapper commands returned nonzero because unrelated tasks exited with code 139 (packagegroup RPM during the U-Boot target and rootfs tar during the kernel target). The relevant U-Boot, device-tree, bitstream, FIT, and bootbin outputs were present and were independently audited; the wrapper-level failures are captured in the raw build logs.

The U-Boot `fit_check_sign` tool verified the built FIT successfully. The same tool was run after flipping one byte in the extracted kernel payload; it reported `Signature check bad`, `sha256 error!`, and `Bad Data Hash`. The payload was rejected before it could be accepted for loading. The reproducible check is:

```sh
python3 scripts/task2g_verify_petalinux_fit.py \
  --fit /path/to/petalinux-project/images/linux/image.ub \
  --control-dtb /path/to/petalinux-project/build/tmp/deploy/images/zynqmp-generic-xczu9eg/u-boot-zynqmp-generic-xczu9eg-2025.01-xilinx-v2025.1+git-r0.dtb \
  --fit-check-sign .build/uboot-task2g-sandbox/tools/fit_check_sign \
  --dumpimage .build/uboot-task2g-sandbox/tools/dumpimage
```

Captured FIT, public control DTB, tampered copy, raw verifier/build logs, metadata, and hashes are in `results/task2g_petalinux_fit_20261015/`. The full FIT contains kernel, DTB, and initramfs. FIT SHA-256: `ca4985971bc9c0914e428d0db7ed04601f8669c3f5660fc424b22084c7e37222`. Control-DTB SHA-256: `493d7a51669c9ab2e1cea9b675feeb63bade51864561b73e0191ff78f1ad75fe`. U-Boot ELF SHA-256: `0928834c26938157f768edb61e2f25f447b23f793f7facf3e2ef9fce9663b958`. The fresh `BOOT-*` container from the build's bootbin recipe has SHA-256 `e4a439814ac547670b05e12d467f9f37c07eb1f9e928b1bbf1c802815d692adc`; it was not tested on the board or authenticated by the BootROM.

The repository contains templates under `linux/appliance/verified_update/petalinux/`. The external PetaLinux project configuration and its pre-import XSA were backed up and hashed before modification under the ignored `.build/task2g_petalinux_config_backup/`. Its disposable signing key remains in the external project's ignored build tree and is not committed.

## What this establishes

- The PetaLinux build can create a signed FIT using the existing Xilinx release.
- The produced U-Boot build has FIT RSA verification enabled and embeds the corresponding public key as a **required** key.
- A valid FIT passes U-Boot verification; a changed kernel payload fails hash verification.
- `CONFIG_BOOTCOUNT_LIMIT` was enabled in U-Boot configuration as groundwork for a bounded trial boot; no slot policy or persistent rollback test was configured.

## What remains open

No artifact was programmed or booted on the ZCU102 in this step. The development signing key is not a protected production key, and the generated `BOOT.BIN` was not verified as BootROM-authenticated. A public key compiled into U-Boot is only useful if the earlier boot chain authenticates that U-Boot. The board's current SD layout and persistent U-Boot environment must be rechecked before an A/B design is deployed. This build does not configure slot selection, active/inactive update writing, persistent trial state, Linux health confirmation, rollback commands, or a watchdog policy. It also does not prove recovery after physical interruption or power loss.

Task 2g therefore remains open. The next work is to define an A/B media layout compatible with the actual card, make U-Boot's signed-slot selection and persistent bootcount policy explicit, build Linux-side inactive-slot staging and health confirmation, then validate signature failure, trial failure, interrupted writes, and recovery on a spare/recoverable target image. Hardware-rooted boot authentication and production key provisioning require a separately controlled key-management process; do not treat this development key as a trust anchor.
