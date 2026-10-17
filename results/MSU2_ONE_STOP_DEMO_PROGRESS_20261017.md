# MSU-2 one-stop demo console — progress report

**Date:** 2026-10-17
**Status:** Linux and bare-metal operator menus implemented; Linux host tests and bare-metal ELF build pass. Cross-mode boot selection and ZCU102 validation remain open.

## What is implemented

`linux/appliance/msu2_demo.py` provides one interactive Linux entry point for
the existing receive-verification/latency sweep and sustained-throughput
runner. It lets the operator select shared payload sizes, duration, and
repetition count for sustained runs, displays the planned duration, and starts
only after the operator types `RUN`. It presents a normal Linux operation
choice that exits to the shell. No test starts automatically at boot.

Every invocation of a test receives a unique evidence directory containing
`config.json`, captured `raw_output.log`, and `manifest.json` with timestamps,
exit code, system context, and SHA-256 hashes. Physical SCK, PL0 rate, topology,
and bitstream hash are explicitly recorded as unknown because the launcher
does not measure or infer them.

Operator instructions are in `linux/appliance/MSU2_DEMO_CONSOLE.md`.
The cumulative Task 2 evidence deck records this milestone on slide 17.

The bare-metal sustained application now waits at a UART menu instead of
starting the long sweep on boot. It offers the original 11-size, 60-second,
three-repetition run, a configurable single-payload test, and a one-second
single-payload smoke test. Every test requires the operator to type `RUN`.

## Verification

- `python3 linux/appliance/msu2_demo.py --self-test` passed. It exercised
  payload validation and verified unique run evidence creation using a fake
  test executable.
- Piping `0` to the menu returned to the normal console without launching a
  test.
- `python3 -m py_compile linux/appliance/msu2_demo.py` passed.
- `python3 -m unittest tests.test_sustainable_benchmark_host -v` passed all
  four existing host tests for sustained-runner success, API errors, RX
  mismatch, and invalid-argument rejection.
- Vitis 2025.1 built the bare-metal menu ELF against the pinned validated XSA.
  ELF SHA-256: `9a1b1455a0b4255429e9c767db2f8ab7d0a54bc1bfa8b2f67bce75a85794c067`.
- The bare-metal build is an ELF-only build; it did not package a BOOT.BIN.
  Neither menu has been installed or run on the ZCU102, and no SPI transfer
  was attempted in this step.

## Signing requirement

The Linux launcher and bare-metal ELF are development artifacts only; do not
copy either directly onto the live card or mutable target filesystem. The
Linux menu and its test programs must be included in the signed FIT-protected
Linux filesystem. The bare-metal program must be an authenticated selectable
image. U-Boot's FIT verifier checks the images selected by `bootm` against
required keys, but this only protects the menu and payload if the U-Boot code
and its control device tree are themselves authenticated by the earlier boot
chain. The [U-Boot FIT signature documentation](https://docs.u-boot.org/en/v2026.04/usage/fit/signature.html)
describes required-key checking; AMD's [Zynq UltraScale+ MPSoC security guide](https://docs.amd.com/r/en-US/wp543-fips-140-3-primer/Zynq-UltraScale-MPSoC-Security)
describes authenticating FSBL and establishing the hardware root of trust.
The current live chain has not passed that authentication test. No SD-card
file, boot image, U-Boot environment, eFUSE, or board state was changed here.

## Signed two-mode selection and SD-card audit update

After the card was moved to the workstation on 17 October, the complete BOOT
partition was copied read-only to `results/sd_card_host_backup_20261017/` and
verified byte-for-byte against the mounted source. The active `BOOT.BIN` hash
matches the previously tested sustained-run image; the card's Linux `image.ub`
matches the previously audited unsigned FIT. No card contents were changed.

`scripts/task2g_signed_selector_sandbox_test.py` now creates one signed FIT
with Linux and standalone SPI-test configurations. Required-key verification
passed for both. U-Boot sandbox accepted the signed Linux selection, loaded the
standalone selection with execution disabled, and rejected a modified
standalone payload before transfer. Captures and hashes are in
`results/task2g_signed_selector_sandbox_20261017/`. This is host-side bootm
integration evidence only; the actual U-Boot menu, target A53 execution,
hardware-rooted trust chain, and physical SPI paths are still untested.

## Remaining work before calling the one-stop deliverable complete

1. Define a signed boot flow that offers normal Linux and signed SPI-test
   mode. The menu code and every selectable payload must be authenticated, and
   unsigned/tampered variants must fail before the menu appears. The current
   board boot flow starts Linux without a chooser; the live boot chain is not
   verified as hardware-rooted.
2. Add the remaining approved test types, including a bounded payload-limit
   experiment, without describing the current 65,536-byte sustained sweep as
   a limit search.
3. Install the launcher and required binaries on the ZCU102, run each selected
   path on the physical J55 loopback, and collect target-side evidence.
4. Produce the final report and presentation slide after the integrated
   operator flow is implemented and validated.

This milestone is a working Linux menu prototype, not completion of Task 2e
or the overall one-stop demo deliverable.
