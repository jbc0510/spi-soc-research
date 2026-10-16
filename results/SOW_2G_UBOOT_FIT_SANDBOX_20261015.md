# Task 2g — U-Boot required FIT signature test

**Disposition:** The U-Boot 2025.01-Xilinx sandbox accepts a correctly signed FIT configuration and rejects both an unsigned FIT and a FIT whose kernel payload was modified. This closes a host-side verified-FIT prototype step. It does not close target secure boot or A/B update recovery.

## Evidence

The U-Boot source revision matches the `5e0d8abc7e` revision recorded in the available PetaLinux 2025.2 package metadata. The sandbox was configured with `CONFIG_FIT_SIGNATURE=y`, `CONFIG_RSA=y`, and legacy image format disabled. Its `bootm` implementation was run, not a Python model or an OpenSSL-only substitute.

| Case | U-Boot result | Outcome |
|---|---|---|
| Signed required configuration | `sha256,rsa2048:dev+ OK`; reached sandbox Linux handoff | Pass |
| Unsigned configuration | `Failed to verify required signature 'key-dev'`; no handoff | Pass |
| Modified kernel payload | `Bad hash value` / `Bad Data Hash`; no handoff | Pass |

The raw `bootm` logs, FIT fixture, control device tree containing the public test key, and SHA-256 manifest are in `results/task2g_uboot_fit_sandbox_20261015/`. The test signing private key is generated in a temporary directory and removed at completion.

## Current build audit

The available PetaLinux 2025.2 `image.ub` contains SHA-256 image hashes but no signed configuration. Its U-Boot ELF exposes ordinary FIT image verification symbols, but the produced image has no signature evidence and no target boot-chain test was possible in this session. The target `CONFIG_FIT_SIGNATURE` state still needs to be verified from the exact deployed U-Boot configuration or by an on-target test.

## Limits and remaining implementation

This test used a disposable development key and sandbox FIT payloads. It does not authenticate FSBL/PMU firmware/bitstream/TF-A/U-Boot with the ZynqMP BootROM, protect the FIT public key with a hardware root of trust, produce a target `BOOT.BIN`, or test booting the ZCU102.

The next target work is to integrate the FIT key into the U-Boot control FDT, build a signed kernel/DTB/initrd FIT, and create a redundant-slot layout with a verified inactive-slot writer, bootcount-limited trial selection, Linux health confirmation and rollback. Before changing target media, capture and verify the exact card image and environment pair. Physical interruption and power-loss tests remain mandatory for a recovery claim.

## Reproduction

See `linux/appliance/verified_update/README.md` and `scripts/build_task2g_uboot_sandbox.sh`. The build uses U-Boot 2025.01-Xilinx and only the sandbox runtime, host signing tools, and a temporary test key.
