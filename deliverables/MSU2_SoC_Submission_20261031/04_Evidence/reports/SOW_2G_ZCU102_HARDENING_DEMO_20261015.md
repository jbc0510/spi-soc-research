# Task 2g — ZCU102 Linux hardening contrast demonstration

**Disposition:** The baseline-versus-hardened update-control demo was cross-compiled for AArch64 and executed on the physical ZCU102 under its running Linux image. All four scenarios passed on target. This is target-CPU software evidence; it does not establish authenticated boot or an integrated bootloader update path.

## Target identity and execution result

- Target: `newQspi`, AArch64, Linux `6.12.10-xilinx-g0a0f70e531c7`.
- The target provides `/usr/lib/libcrypto.so.3`; the demo dynamically loads this library and verifies an RSA/SHA-256 signed test fixture using the target's OpenSSL EVP API.
- The transfer was verified before execution: workstation and target binary SHA-256 were both `0ca6af020d16ea8174ec3d2f7ff625b1dd727870b1f28753898f51a98646f8e8`.
- All four comparison cases passed: valid signed update, tampered update, interrupted write, and injected trial-health failure.
- After execution, FPGA Manager still reported `operating`, `/dev/spidev1.0` remained present, and the test's `/tmp/msu2-hardening-*` directory had been removed.

Raw target output is in `results/task2g_board_contrast_20261015/target_run.log`. The target ELF, C source, build script, and test vector are preserved with SHA-256 hashes in that directory.

## What ran on the board

`linux/appliance/hardening_contrast_board.c` is an AArch64 Linux program. It dynamically loads the target's existing `libcrypto.so.3`, authenticates the known release fixture before staging, writes only file-backed slots under a unique `/tmp` directory, and compares the behavior with an intentionally unsafe baseline. It checks the inactive-slot bytes by reading them back and comparing them to the signed payload before publishing the in-memory pending flag. The release payload, signature, and public test key are embedded into the executable by `scripts/build_task2g_board_demo.py`.

The valid release was accepted in both paths. The baseline accepted altered bytes, partially overwrote active slot A during the interrupted-write case, and kept an image active after the injected health failure. The hardened path rejected the altered signature without changing either slot, kept A unchanged when an interrupted write touched only inactive B, and cleared the in-memory trial flag after the injected health failure.

Rebuild the target executable and run its host logic check with:

```sh
python3 scripts/build_task2g_board_demo.py
python3 -m unittest discover -s tests -p 'test_task2g_board_demo_host.py' -v
```

The target ELF uses the installed AMD AArch64 Linux GCC 13.3.0 toolchain and dynamically loads OpenSSL from the target at run time. The host test compiles the same C source against the workstation's `libcrypto` and checks the four expected outcomes; it supplements, but does not replace, the saved ZCU102 run.

## Evidence boundary

This run exercised actual ZCU102 CPU, Linux file I/O in `/tmp`, and target OpenSSL signature verification. It did **not** write an SD/eMMC partition, reboot the board, access SPI or FPGA MMIO, change the PL clock/reset, or test BootROM/FSBL/TF-A/U-Boot verified boot. The private test key was not transferred; the public test vector is not the project's production trust anchor.

The interruption case injects a short write and returns before pending-slot publication; it is not a physical power cut. The health-failure case explicitly injects a failed health result; the program does not boot an update or measure Linux/SPI health. A and B are temporary ordinary files and boot state is an in-memory flag, not persistent redundant boot metadata. Therefore this closes only the software-demo portion of Task 2g. Production hardening still requires integration with the real boot chain, a controlled trust anchor, persistent A/B state and recovery, and on-target boot/power-fault tests.

## Reproduction artifacts

- C target program: `linux/appliance/hardening_contrast_board.c`
- Cross-build and test-vector embedder: `scripts/build_task2g_board_demo.py`
- Host logic acceptance test: `tests/test_task2g_board_demo_host.py`
- Public signed fixture: `release_fixture.bin`, `release_fixture.sig`, `test_public.pem`
- Target executable and transcript: `hardening_contrast_board_aarch64`, `target_run.log`
- SHA-256 listing: `SHA256SUMS`
