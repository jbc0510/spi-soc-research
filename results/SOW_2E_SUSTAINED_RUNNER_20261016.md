# Task 2e — sustained-throughput runner implementation

**Disposition:** Linux and bare-metal runners for the planned 60-second sustained SPI test have been implemented. Linux completed all 11 shared payload sizes × three 60-second repetitions (33/33 points passed). A separate existing bare-metal fixed-trial application then completed a physical 11-size × 1,000-transfer regression on the exact validated September 29 PL bitstream, with 11,000 successful transfers and zero API errors, timeouts, or receive mismatches. The newly built 60-second bare-metal runner has not yet run on the board; its fixed-trial result uses a different measurement method, so Task 2e remains partial pending a paired sustained analysis. See `results/task2e_sustainable_runner_20261016/SOW_2E_BAREMETAL_BOARD_RUN_20261016.md`.

## What the runner does

`linux/src/spi_sustainable_benchmark.c` runs one payload size and one repetition per invocation. The payload must be one of the shared benchmark contract's 11 sizes. The default measurement window is 60 seconds; shorter windows may be used for controlled smoke tests, and the maximum is one hour. It configures mode 0 and 8-bit words, records the requested and read-back SPI speed, prepares the contract's incrementing TX pattern and poisoned RX buffer for every transaction, and verifies every completed receive buffer.

The wall window includes pattern preparation, SPI calls, and receive verification. Application payload rate is verified bytes divided by the observed wall interval. The output also records successful transfers, attempts, API errors, mismatches, benchmark-thread CPU time and share, and the longest SPI ioctl interval. A transfer error, short return, or mismatch stops the run immediately; the nonzero exit status makes the row unsuitable as a passing result. Each repetition should be a separate invocation so its stdout and exit code can be preserved independently.

Example for one 60-second run at 1 KiB, repetition 1 (requested SCK is a request, not a physical measurement):

```sh
./spi_sustainable_benchmark /dev/spidev1.0 1024 60 49995000 \
  1 > linux_1k_rep1.log 2>&1
```

The bare-metal firmware in `bare_metal/src/spi_sustainable_benchmark_bare_axi.c` runs the shared 11 sizes for three repetitions, 60 seconds per point, and stops on its first transfer error or mismatch. Its CPU field is explicitly `busy_wait_core_occupancy`, derived from the busy-wait execution model, not a PMU measurement. Save the full UART output. Record measured SCK, PL clock, CPU operating point, kernel/BSP identity, FPGA hash, controller identity, and loopback verification independently. Do not combine these application-level rates with the fixed-ladder `payload / mean API latency` rates.

## Physical Linux sustained results

The Linux runner was executed on the ZCU102 through `/dev/spidev1.0` with the validated bitstream SHA-256 `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`. The FPGA Manager reported `operating` immediately before every point; the runner used SPI mode 0, 8-bit words, and 49,995,000 Hz requested/read-back speed. The J55 SCK measurement for this exact ratio-2 bitstream is approximately 51 MHz from the September 29 hardware validation. It was not remeasured during these sustained runs. CPU policy was last read at the `userspace` governor and 1,200,000 kHz before the run set; per-point CPU-frequency sysfs snapshots were not recorded, so frequency stability across all 33 windows is not proven.

Each run lasted at least 60 seconds, byte-verified every completed transfer, and stopped on the first API error, short transfer, timeout, or receive mismatch. The 33 points completed with zero API errors and zero receive mismatches. Original UART bytes are preserved together in `linux_sustained_serial_raw.tar.gz`; the matching readable point transcripts are `linux_sustained_point_<payload>B_rep<repetition>_serial.log`. `linux_sustained_runs.csv` contains all point metrics plus `/proc/stat` deltas, and `linux_sustained_medians.csv` reports each repetition and the per-size median. `collect_task2e_linux_sustained.py` validates the transcripts and regenerates both CSVs.

| Payload | Rep 1 | Rep 2 | Rep 3 | Median MB/s | Median thread CPU share |
|---:|---:|---:|---:|---:|---:|
| 1 B | 0.0352 | 0.0734 | 0.0578 | 0.0578 | 86.54% |
| 8 B | 0.2665 | 0.2664 | 0.2643 | 0.2664 | 68.62% |
| 16 B | 0.4785 | 0.4723 | 0.4726 | 0.4726 | 66.42% |
| 64 B | 0.9824 | 0.9823 | 0.9811 | 0.9823 | 46.62% |
| 128 B | 1.1927 | 1.1919 | 1.1916 | 1.1919 | 38.91% |
| 256 B | 1.3350 | 1.3332 | 1.3321 | 1.3332 | 33.21% |
| 512 B | 1.4080 | 1.4080 | 1.4080 | 1.4080 | 18.07% |
| 1 KiB | 1.4492 | 1.4495 | 1.4492 | 1.4492 | 10.17% |
| 4 KiB | 1.4829 | 1.4831 | 1.4834 | 1.4831 | 3.63% |
| 16 KiB | 1.4924 | 1.4924 | 1.4922 | 1.4924 | 1.91% |
| 64 KiB | 1.4949 | 1.4949 | 1.4949 | 1.4949 | 1.47% |

Rates are verified payload bytes divided by the measured wall window; they include transaction setup and pattern/receive validation in the application loop. They describe this Linux software path and current hardware configuration, not the wire's maximum. Linux execution occurred for all three repetitions before any new bare-metal sustained run, rather than alternating backends between repetitions as the experiment plan recommends. The Linux-vs-bare-metal comparison must disclose this order effect. The 1-byte rate and CPU share varied more between repetitions than larger points; all three remain included, and the median is used without omitting the variability.

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

These host checks validate firmware compilation/linking, Linux argument gates, loop accounting, data comparison, and output formatting against a synthetic ioctl response. Physical Linux and bare-metal regressions are documented separately below and in `results/task2e_sustainable_runner_20261016/SOW_2E_BAREMETAL_BOARD_RUN_20261016.md`; neither fixed-trial bare-metal results nor the Linux sustained set alone establish equivalence of the two sustained runners.

## Current blocker and remaining work

A live UART preflight was completed on October 16 and is preserved in `results/task2e_sustainable_runner_20261016/target_preflight.log`. It confirmed the target kernel and PetaLinux 2025.1 image, FPGA Manager state `operating`, `/dev/spidev1.0`, the platform device `a0000000.spi`, SPI child `spi1.0`, a 1 MiB spidev buffer, and 348,001 accumulated interrupts on the AXI SPI IRQ. The target libc exports GLIBC through 2.39, which covers the Linux runner's maximum required symbol version (2.38). The unprivileged shell could not read the live clock summary or current CPU frequency; use the earlier clock evidence in `results/linux_axi_spi_bringup_20261013/target_console.log` and README for that configuration.

The console user is `petalinux`; `/dev/spidev1.0` is `0600 root:root`. Authenticated sudo was used for a read-only preflight, a printable-escape UART upload, SHA-256 verification, and one guarded transfer smoke. The staged executable hash matched the host-built runner. The smoke was run at mode 0, 8 bits, requested/read-back 1 MHz, 64-byte payload, and a one-second measurement window. It completed 15,354 transfers / 982,656 verified payload bytes at 0.9826 application MB/s, with zero API errors and zero mismatches; maximum observed transfer call was 130.833 µs. The serial transcript is `target_smoke_attempt.log`. These numbers describe only this short run and CPU operating point; physical SCK was not measured, so they are not a sustained throughput result or an apples-to-apples comparison with the bare-metal baseline.

The Linux runner was cross-compiled to AArch64 and passed the four host mock tests. The physical sustained set adds target-side loopback validation for all 11 sizes and three repetitions. The Linux SPI ioctl has no userspace deadline in this runner; each physical point was monitored by a host-side serial watchdog and returned within the 80-second limit. A separate 11,000-transfer bare-metal board regression passed using the exact validated PL bitstream, but the 60-second bare-metal runner has not yet run, and no paired sustained manifest exists.

The prior paired experiment definition remains in `results/SOW_2E_BENCHMARK_CLOSURE_EXPERIMENT_20261015.md`. Task 2e closure still requires valid physical sustained runs for both backends, a paired run manifest, and per-point CPU operating-point confirmation. The Linux sustained half is complete; the bare-metal fixed-trial regression is complete, while the bare-metal sustained run and paired sustained comparison remain open.

## Bare-metal access state

After the Linux run set was captured and pushed, Linux was gracefully powered down to avoid downloading a bare-metal ELF at `0x100000` over live Linux memory. The initial JTAG recovery attempt failed after the A53 FPD powered down; its details remain in `results/task2e_sustainable_runner_20261016/baremetal_jtag_recovery_attempt.log`. A later physical power cycle restored JTAG visibility and all four A53 cores reported running Linux. Because the sustainable bare-metal ELF was not safely launchable over live Linux memory, the existing standalone SD boot image was used for the fixed-trial regression. The target SD `BOOT.BIN` now contains that standalone image; the original Linux image was preserved as `BOOT_linux_backup_20261013.bin` with its hash recorded in the bare-metal board-run report. The board currently runs the standalone test, and Linux must be restored by returning the backup file to `BOOT.BIN` before the next Linux experiment.
