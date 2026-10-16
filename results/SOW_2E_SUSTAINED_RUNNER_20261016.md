# Task 2e — sustained-throughput runner implementation

**Disposition:** Linux and bare-metal runners for the planned 60-second sustained SPI test have been implemented. The Linux runner passes host-only mock tests; the bare-metal runner builds as an AArch64 ELF against the validated September 29 XSA. Neither runner has been executed on the physical board, and Task 2e remains partial.

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

The current execution environment exposes no `/dev/ttyUSB*`, `/dev/ttyACM*`, or `/dev/serial/by-id` device, so a board run cannot be started from this session. No benchmark transfer was attempted. A paired run manifest and target-side validation still need to be completed. The Linux SPI ioctl has no userspace deadline in this runner; physical runs should only be started after confirming the controller and loopback are healthy, and the serial/host process should be monitored. A kernel-side stall could outlast the intended window.

The prior paired experiment definition remains in `results/SOW_2E_BENCHMARK_CLOSURE_EXPERIMENT_20261015.md`. Task 2e closure still requires valid physical sustained runs for both backends, a paired run manifest, and target-side integrity/clock confirmation. No new board or timing evidence is claimed here.
