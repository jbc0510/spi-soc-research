# Task 2e — sustained-throughput runner implementation

**Disposition:** A Linux-side runner for the planned 60-second sustained SPI test has been added and host-compiled. It has not been run against a physical SPI device, and Task 2e remains partial.

## What the runner does

`linux/src/spi_sustainable_benchmark.c` runs one payload size and one repetition per invocation. The payload must be one of the shared benchmark contract's 11 sizes. The default measurement window is 60 seconds; shorter windows may be used for controlled smoke tests, and the maximum is one hour. It configures mode 0 and 8-bit words, records the requested and read-back SPI speed, prepares the contract's incrementing TX pattern and poisoned RX buffer for every transaction, and verifies every completed receive buffer.

The wall window includes pattern preparation, SPI calls, and receive verification. Application payload rate is verified bytes divided by the observed wall interval. The output also records successful transfers, attempts, API errors, mismatches, benchmark-thread CPU time and share, and the longest SPI ioctl interval. A transfer error, short return, or mismatch stops the run immediately; the nonzero exit status makes the row unsuitable as a passing result. Each repetition should be a separate invocation so its stdout and exit code can be preserved independently.

Example for one 60-second run at 1 KiB (requested SCK is a request, not a physical measurement):

```sh
./spi_sustainable_benchmark /dev/spidev1.0 1024 60 15623438 \
  > linux_1k_rep1.log 2>&1
```

Run each of the 11 sizes three times, preserving each log separately. Record the measured SCK, PL clock, CPU operating point, kernel/build identity, FPGA hash, controller identity, and loopback verification independently. Do not combine these application-level rates with the fixed-ladder `payload / mean API latency` rates.

## Host checks completed

- Compiled with `cc -std=c11 -O2 -Wall -Wextra -Werror` against the shared benchmark contract.
- Invalid payload and invalid duration inputs return usage failure before opening the SPI device.
- A one-second host smoke test used an `LD_PRELOAD` ioctl shim that echoes TX bytes into RX. It completed 8,230,231 mock transfers at 64 bytes with zero mismatches and emitted a valid row. The reported 526.7 MB/s is shim/runtime speed, not SPI hardware performance; raw output is `results/task2e_sustainable_runner_20261016/host_mock_smoke.log`.
- `git diff --check` passes.

These checks validate compilation, argument gates, loop accounting, data comparison, and output formatting against a synthetic ioctl response. They do not validate a Linux SPI driver, physical loopback integrity, hardware throughput, or equivalence to a bare-metal sustained run.

## Current blocker and remaining work

The current execution environment exposes no `/dev/ttyUSB*`, `/dev/ttyACM*`, or `/dev/serial/by-id` device, so a board run cannot be started from this session. No benchmark transfer was attempted. The bare-metal firmware counterpart and a paired run manifest still need to be implemented and validated. The Linux SPI ioctl has no userspace deadline in this runner; physical runs should only be started after confirming the controller and loopback are healthy, and the serial/host process should be monitored. A kernel-side stall could outlast the intended window.

The prior paired experiment definition remains in `results/SOW_2E_BENCHMARK_CLOSURE_EXPERIMENT_20261015.md`. Task 2e closure still requires valid physical sustained runs for both backends, the bare-metal CPU-occupancy basis, and unified run metadata. No new board or timing evidence is claimed here.
