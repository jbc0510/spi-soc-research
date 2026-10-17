# MSU-2 one-stop demo console — progress report

**Date:** 2026-10-17
**Status:** Linux-side operator console implemented and host-tested; full cross-mode boot selection and ZCU102 validation remain open.

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
- No SPI hardware or ZCU102 OS boot menu was exercised in this implementation
  step.

## Remaining work before calling the one-stop deliverable complete

1. Add the bare-metal operator menu and make its test choices/parameters
   compatible with the Linux menu's configuration and results schema.
2. Build and validate an OS/test-mode boot chooser using the same validated
   PL image. The current board boot flow starts Linux without a chooser. Any
   selector must preserve the Task 2g signed-boot policy; the existing active
   boot path is not yet a verified signed chain.
3. Add the remaining approved test types, including a bounded payload-limit
   experiment, without describing the current 65,536-byte sustained sweep as
   a limit search.
4. Install the launcher and required binaries on the ZCU102, run each selected
   path on the physical J55 loopback, and collect target-side evidence.
5. Produce the final report and presentation slide after the integrated
   operator flow is implemented and validated.

This milestone is a working Linux menu prototype, not completion of Task 2e
or the overall one-stop demo deliverable.
