# SOW Task 2d — System Hardening Design

**SOW activity:** “System Hardening — Design a minimal software environment that supports secure boot, reliable updates, and automated recovery mechanisms.”

**Disposition: Task 2d design criterion complete.** This report specifies the minimal software environment, hardware-rooted secure-boot chain, signed update flow, and automatic trial-boot recovery. It is a design deliverable, not a claim of implemented or hardware-validated secure boot or update recovery. Deployment, target validation, and fault-injection tests remain open under the later minimal-appliance implementation activity (Task 2g).

## Design goals and threat boundary

The design must prevent an untrusted boot image from executing, keep a known-good bootable slot while a new release is staged, and recover automatically when an update or first boot fails. The board’s tested initrd image is a functional benchmark environment, not a hardened appliance. The design therefore treats all removable SD contents and update inputs as mutable and untrusted until authenticated.

## Proposed boot chain

1. **Immutable trust anchor:** provision the device with an approved ZynqMP RSA public-key hash and enable the hardware authentication policy in a controlled manufacturing procedure. Private signing keys remain outside the repository and build workstation’s routine developer environment.
2. **Authenticated first stage:** BootROM authenticates the FSBL. FSBL authenticates the PMU firmware, PL bitstream, Arm Trusted Firmware/BL31, and U-Boot partitions in `BOOT.BIN`.
3. **Authenticated OS payload:** U-Boot verifies a signed FIT containing the kernel, device tree, and root filesystem image as one selected configuration before booting it. A missing key, invalid signature, or unsupported configuration fails closed to the recovery slot.
4. **Measured release identity:** the boot service records the selected slot, version, image digests, and signature result in the console log and an append-only evidence record.

Boot-header authentication without an eFUSE trust anchor is suitable for controlled development tests, but is not the fielded trust model: AMD documents that this mode skips eFUSE public-key-hash and revocation checks and can be permanently disabled by programming `RSA_EN`. Do not treat a software-generated signature by itself as a hardware-rooted secure boot result.

## Proposed update and recovery flow

Use two bootable system slots plus a small recovery path. Keep the active slot read-only while the updater writes the inactive slot. After writing, flush storage, verify the complete image digest and signature, and run filesystem/image consistency checks. Only then atomically set a pending-slot marker and a bounded boot-attempt counter. On a trial boot, a health check verifies Linux startup and the AXI SPI loopback smoke test; only a passing check marks the slot good. A failed or interrupted trial causes U-Boot to select the previously confirmed slot. The recovery image can restore a signed release without altering user data.

The update protocol must never erase the only confirmed bootable copy. The existing redundant U-Boot environment mechanism is not sufficient by itself: it silently falls back when one copy is corrupt and does not repair it. The appliance should check both environment copies at boot and restore redundancy from a trusted source, or use a separately protected boot-control record with equivalent atomicity and recovery rules.

## Minimal software environment

Use a read-only, signed root filesystem with only the boot service, SPI runtime/driver dependencies, update verifier, recovery tools, logging, and required device-management services. Keep mutable state in a separately bounded data partition or volatile overlay. Disable unused network services and remove build/debug tools from the production image. The SPI benchmark binary and test vectors may remain in a separate verification package so the runtime root remains minimal.

## Acceptance tests for the implementation

| Test | Required result |
|---|---|
| Authentic release | Device boots the signed release and records the expected image identity. |
| Modified kernel, DTB, rootfs, or bootloader partition | Verification rejects the image before execution. |
| Wrong signing key or unsigned update | Update is rejected; the confirmed slot remains bootable. |
| Power loss during each inactive-slot write phase | Restart selects the confirmed slot or verified recovery image; no mixed release boots. |
| Trial image fails health check | Boot-attempt limit triggers rollback and records the reason. |
| One boot-control/environment copy corrupt | Boot continues from valid state, raises a health alarm, and restores redundancy. |
| Both copies corrupt or recovery media unavailable | Fail-safe recovery behavior is explicit and documented; no unsigned fallback is accepted. |

## Implementation boundary and current status

The existing September environment-copy test demonstrates a CRC fallback for one corrupted preferred copy, but it is one trial and the damaged copy remains damaged. The current benchmark image uses initrd rootfs, `CONFIG_FIT_SIGNATURE` is reported unset, and the Linux environment utilities are not provisioned in the image. These facts leave the boot-chain, signed update, trial-boot rollback, and automated repair tests unimplemented.

No target image was rebuilt, no SD card or board state was changed, and no eFUSE was programmed for this design. The PetaLinux 2025.2 project inspected on the workstation is outside the writable repository and selects an initrd rootfs; this report does not represent that generated project as modified.

## Sources

- Governing SOW: `/home/opentitan/Downloads/MSU-2_SOW_Final (1).docx`, revision 2026-02-23.
- Existing recovery evidence: `results/SOW_2G_RECOVERY_20260909.md` and `results/SOW_2G_FWENV_20260908.md`.
- AMD Zynq UltraScale+ MPSoC Software Developer Guide, [Boot Time Security](https://docs.amd.com/r/en-US/ug1137-zynq-ultrascale-mpsoc-swdev/Boot-Time-Security) and [Authentication](https://docs.amd.com/r/en-US/ug1137-zynq-ultrascale-mpsoc-swdev/Authentication).
- AMD Embedded Design Tutorial, [Enabling Boot Header Authentication](https://docs.amd.com/r/en-US/ug1209-embedded-design-tutorial/Enabling-Boot-Header-Authentication).

The design satisfies the SOW's “Design” activity for Task 2d. It does not close the separate Task 2g appliance implementation or claim the overall hardening approach is deployed or hardware-validated.
