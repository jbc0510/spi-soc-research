# Task 2e — sustained-throughput runner implementation

**Disposition:** Linux and bare-metal runners for the planned 60-second sustained SPI test have been implemented. The Linux runner passes host-only mock tests, and a guarded one-second physical J55 loopback smoke completed on the ZCU102 with 15,354 verified 64-byte transfers and zero API errors or receive mismatches. The bare-metal runner builds as an AArch64 ELF against the validated September 29 XSA but has not run on the board. Task 2e remains partial; the smoke is a bring-up check, not sustained benchmark evidence.

## What the runner does

`linux/src/spi_sustainable_benchmark.c` runs one payload size and one repetition per invocation. The payload must be one of the shared benchmark contract's 11 sizes. The default measurement window is 60 seconds; shorter windows may be used for controlled smoke tests, and the maximum is one hour. It configures mode 0 and 8-bit words, records the requested and read-back SPI speed, prepares the contract's incrementing TX pattern and poisoned RX buffer for every transaction, and verifies every completed receive buffer.

The wall window includes pattern preparation, SPI calls, and receive verification. Application payload rate is verified bytes divided by the observed wall interval. The output also records successful transfers, attempts, API errors, mismatches, benchmark-thread CPU time and share, and the longest SPI ioctl interval. A transfer error, short return, or mismatch stops the run immediately; the nonzero exit status makes the row unsuitable as a passing result. Each repetition should be a separate invocation so its stdout and exit code can be preserved independently.

Example for one 60-second run at 1 KiB, repetition 1 (requested SCK is a request, not a physical measurement):

```sh
./spi_sustainable_benchmark /dev/spidev1.0 1024 60 15623438 \
  1 > linux_1k_rep1.log 2>&1
```

The bare-metal firmware in `bare_metal/src/spi_sustainable_benchmark_bare_axi.c` runs the shared 11 sizes for three repetitions, 60 seconds per point, and stops on its first transfer error or mismatch. Its CPU field is explicitly `busy_wait_core_occupancy`, derived from the busy-wait execution model, not a PMU measurement. Save the full UART output. Record measured SCK, PL clock, CPU operating point, kernel/BSP identity, FPGA hash, controller identity, and loopback verification independently. Do not combine these application-level rates with the fixed-ladder `payload / mean API latency` rates.

The bare-metal ELF was built from the same September 29 XSA using Vitis 2025.1 and the existing build flow:

```sh
python3 scripts/build_spi_axi_bm_ratio2_vitis.py \
  --source bare_metal/src/spi_sustainable_benchmark_bare_axi.c \
  --workspace-name spi_axi_bm_task2e_sustain_20261016b \
  --timeout-seconds 240
```

Build output is preserved under `results/task2e_sustainable_runner_20261016/`, including the ELF, manifests, Vitis platform log, host mock log, and SHA-256 list. The build manifest identifies this as `BUILD_PASS_NOT_HARDWARE_VALIDATION`.

## Host checks completed

- Compiled with `cc -std=c11 -O2 -Wall -Wextra -Werror` against the shared benchmark contract.
- Invalid payload and invalid duration inputs return usage failure before opening the SPI device.
- A one-second host smoke test used an `LD_PRELOAD` ioctl shim that echoes TX bytes into RX. It completed 6,672,245 mock transfers at 64 bytes with zero mismatches and emitted a valid row. The reported 427.0 MB/s is shim/runtime speed, not SPI hardware performance; raw output is `results/task2e_sustainable_runner_20261016/host_mock_smoke.log`.
- The mock test suite also injects an API error and an RX mismatch; both stop the point after the first attempted transaction and return failure. All four tests pass with `python3 -m unittest tests/test_sustainable_benchmark_host.py -v`.
- Vitis 2025.1 platform and application build completed against the pinned XSA. The resulting AArch64 ELF has entry point `0x100000`, and its symbols, XSA metadata, source hash, and build identity are recorded in the build manifest.
- `git diff --check` passes.

These checks validate firmware compilation/linking, Linux argument gates, loop accounting, data comparison, and output formatting against a synthetic ioctl response. They do not validate bare-metal runtime behavior, a Linux SPI driver, physical loopback integrity, hardware throughput, or equivalence of the two sustained runs.

## Current blocker and remaining work

A live UART preflight was completed on October 16 and is preserved in `results/task2e_sustainable_runner_20261016/target_preflight.log`. It confirmed the target kernel and PetaLinux 2025.1 image, FPGA Manager state `operating`, `/dev/spidev1.0`, the platform device `a0000000.spi`, SPI child `spi1.0`, a 1 MiB spidev buffer, and 348,001 accumulated interrupts on the AXI SPI IRQ. The target libc exports GLIBC through 2.39, which covers the Linux runner's maximum required symbol version (2.38). The unprivileged shell could not read the live clock summary or current CPU frequency; use the earlier clock evidence in `results/linux_axi_spi_bringup_20261013/target_console.log` and README for that configuration.

The console user is `petalinux`; `/dev/spidev1.0` is `0600 root:root`. Authenticated sudo was used for a read-only preflight, a printable-escape UART upload, SHA-256 verification, and one guarded transfer smoke. The staged executable hash matched the host-built runner. The smoke was run at mode 0, 8 bits, requested/read-back 1 MHz, 64-byte payload, and a one-second measurement window. It completed 15,354 transfers / 982,656 verified payload bytes at 0.9826 application MB/s, with zero API errors and zero mismatches; maximum observed transfer call was 130.833 µs. The serial transcript is `target_smoke_attempt.log`. These numbers describe only this short run and CPU operating point; physical SCK was not measured, so they are not a sustained throughput result or an apples-to-apples comparison with the bare-metal baseline.

The Linux runner was cross-compiled to AArch64 and passed the four host mock tests. The physical smoke adds target-side loopback validation but does not establish sustained behavior. A paired run manifest and bare-metal target execution still need to be completed. The Linux SPI ioctl has no userspace deadline in this runner; physical runs should be monitored because a kernel-side stall could outlast the intended window.

The prior paired experiment definition remains in `results/SOW_2E_BENCHMARK_CLOSURE_EXPERIMENT_20261015.md`. Task 2e closure still requires valid physical sustained runs for both backends, a paired run manifest, and measured SCK plus CPU operating-point confirmation. The one-second smoke is recorded separately and is not substituted for those runs.
