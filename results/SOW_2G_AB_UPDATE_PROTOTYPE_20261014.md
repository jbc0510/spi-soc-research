# Task 2g — A/B update and recovery prototype evidence

**SOW activity:** “Minimal Software Stack — Implement a minimal software stack for the SoC to run the SPI benchmark application. Ensure that the software stack supports robust update and verify integrity.”

**Disposition:** A host-testable reference prototype now demonstrates signed inactive-slot staging, readback verification, bounded trial boots, confirmation, and rollback. Four fault-injection tests pass. This is implementation evidence for update logic, not a deployable ZCU102 update system and not closure of Task 2g.

## Implementation and test result

`linux/appliance/ab_update_prototype.py` accepts an image only after OpenSSL RSA/SHA-256 signature verification, writes it to the inactive file-backed slot, flushes the data, verifies its readback digest and signature, then atomically publishes pending-slot state. The confirmed slot is never the update target. A pending slot receives at most the configured number of trial selections; the caller can mark it healthy or reject it. State updates use a temporary file, `fsync`, atomic rename, and parent-directory `fsync`.

The test suite `tests/test_task2g_ab_update.py` passed all four cases on 2026-10-14:

| Case | Observed result |
|---|---|
| Signed release stages to inactive slot, trial selects, then confirms | Pass; B becomes confirmed while A remains untouched |
| Invalid signature | Rejected before slot or state changes |
| Injected interruption after a 512-byte inactive-slot prefix | Only B has a 512-byte prefix; A is unchanged, update is not pending, and boot still selects A |
| Trial boot limit and health rejection | Both return selection to confirmed A |

Reproduce from the repository root with:

```sh
python3 -m unittest discover -s tests -p 'test_task2g_ab_update.py' -v
python3 -m py_compile linux/appliance/ab_update_prototype.py tests/test_task2g_ab_update.py
```

## Boundary and remaining work

The prototype stores slot contents in ordinary host files and boot metadata in JSON. It does not call U-Boot, manage an SD-card partition table, validate power-loss atomicity on the target, enforce a hardware-rooted trust anchor, create a signed production image, or run the SPI health check on a trial boot. It is a reference model for update-state and fault behavior. It must not be described as secure boot or as a fielded recovery mechanism.

Task 2g remains open pending a minimal target image, authenticated boot configuration, a U-Boot-integrated A/B update path, automatic trial health check and rollback, recovery of boot-control redundancy, and target fault-injection evidence. The live board path was unavailable during this session (no serial devices exposed; SSH to the last known address refused), so no target update or reboot was attempted.

## Related evidence

- System-hardening architecture: `results/SOW_2D_SYSTEM_HARDENING_DESIGN_20261014.md`.
- Existing U-Boot environment fallback and limitations: `results/SOW_2G_RECOVERY_20260909.md` and `results/SOW_2G_FWENV_20260908.md`.
- Prototype: `linux/appliance/ab_update_prototype.py`.
- Fault-injection tests: `tests/test_task2g_ab_update.py`.
- Captured test output: `results/task2g_ab_update_prototype_20261014/test_run.log`.
