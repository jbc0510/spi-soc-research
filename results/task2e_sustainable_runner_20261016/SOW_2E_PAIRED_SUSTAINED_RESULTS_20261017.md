# Task 2e — paired sustained SPI results

## Result

The planned 60-second no-delay test is now complete on both Linux and bare metal. Each backend ran the same 11 payload sizes three times, for 33 points per backend and 66 points total. Every completed transfer was checked against the transmitted bytes. All 66 points passed with zero API errors, timeouts, short transfers, or receive mismatches.

This completes the planned **bounded Task 2e comparative benchmark framework**. It includes the shared workload and pattern contract, validated fixed-trial latency/integrity ladder, 60-second sustained windows, raw evidence, reproducible parser, CPU-metric bases, and a clock/operating-point audit. The measurements establish the maximum rate observed under the tested 60-second workload/configuration; they do not establish an absolute hardware ceiling or isolate an OS-only performance effect. Per-window clock instrumentation and alternating backend order were not implemented, so causal and thermal claims remain out of scope.

## Hardware and software identity

- Target: ZCU102, external J55 MOSI-to-MISO loopback.
- PL design: validated September 29 AXI Quad SPI implementation; embedded bitstream SHA-256 `90f93479dd47c505b8f9e4fe6f4f18e853f8923d081f4b2037401ed3cb46994a`.
- Sustained-runner boot image: `BOOT_AXI_SUSTAINED_20261016.BIN`, SHA-256 `f64730ce205bbfb5de28bcf44c13d3511adaa6b4b47d34a284178c95fc90c39e`.
- Linux: PetaLinux 2025.1, kernel `6.12.10-xilinx-g0a0f70e531c7`; `/dev/spidev1.0`, mode 0, 8-bit words, 49,995,000 Hz requested/read-back SPI speed.
- Bare metal: Vitis 2025.1 A53 standalone, XSpi interrupt driver with a busy-wait completion loop; application ELF SHA-256 `220f85f57df652b146906c1bccb2ad5c4ce9407c5a8c875c01e98d00864fdb95`.
- PL0: 99.990 MHz, verified on the Linux run and supported for bare metal by the post-run read-only register snapshot plus the runner's lack of clock-programming operations. The same readback appears in the preceding bare-metal fixed-ladder capture. See `clock_readback_20261017.md`.
- Physical SCK: about 51 MHz was measured at J55 for this exact bitstream and ratio-2 configuration on September 29. The Linux run requested/read back 49.995 MHz. J55 SCK was not remeasured during the sustained sets, so the physical measurement is matching-configuration historical evidence, not a simultaneous measurement.
- CPU point: Linux used the userspace governor at 1.2 GHz, sampled before its set. A post-run A53 register snapshot supports a derived 1.19988 GHz bare-metal A53 clock; it was not sampled per point. Bare metal reports 100% dedicated-core occupancy because the firmware busy-waits; this is an execution-model metric, not a PMU reading.
- Timers: Linux `CLOCK_MONOTONIC_RAW`; bare metal `XTime_GetTime`.

## Sustained application payload rate

Rates are verified payload bytes divided by the measured 60-second window, including transaction setup and pattern generation/receive checking. They are application-level rates, not SPI wire rates. The table shows the median of three points per size.

| Payload | Linux median (MB/s) | Bare-metal median (MB/s) | Bare metal vs Linux |
|---:|---:|---:|---:|
| 1 B | 0.0578 | 0.1418 | +145.6% |
| 8 B | 0.2664 | 0.4677 | +75.6% |
| 16 B | 0.4726 | 0.5606 | +18.6% |
| 64 B | 0.9823 | 0.6559 | −33.2% |
| 128 B | 1.1919 | 0.6750 | −43.4% |
| 256 B | 1.3332 | 0.6849 | −48.6% |
| 512 B | 1.4080 | 0.8651 | −38.6% |
| 1 KiB | 1.4492 | 0.9995 | −31.0% |
| 4 KiB | 1.4831 | 1.1312 | −23.7% |
| 16 KiB | 1.4924 | 1.1698 | −21.6% |
| 64 KiB | 1.4949 | 1.1797 | −21.1% |

The results show a crossover: bare metal has the higher measured application rate for 1–16-byte messages, while Linux is higher from 64 bytes onward. The largest observed rate in this test was 1.4949 MB/s for Linux at 64 KiB and 1.1797 MB/s for bare metal at 64 KiB. These are maxima observed in this benchmark and configuration, not hardware ceilings.

## Reproduction and evidence

Run the validator from the repository root:

```sh
python3 scripts/parse_task2e_baremetal_sustained.py \
  results/task2e_sustainable_runner_20261016/baremetal_sustained_uart_capture_20261016.raw.log \
  results/task2e_sustainable_runner_20261016/linux_sustained_medians.csv \
  results/task2e_sustainable_runner_20261016
```

The validator checks the 33-record order, all 11 payloads × 3 repetitions, minimum window length, byte totals, zero-error counters, completion marker, and shared Linux payload set. It emits:

- `baremetal_sustained_uart_capture_20261016.raw.log` — raw UART output received after host-console attachment; startup header/metadata preceded attachment and is therefore absent.
- `baremetal_sustained_runs_20261016.csv` — validated individual bare-metal points.
- `baremetal_sustained_medians_20261016.csv` — per-size repetitions and medians.
- `linux_baremetal_sustained_comparison_20261016.csv` — paired rate and CPU-basis comparison.
- `paired_sustained_SHA256SUMS_20261017` — hashes for the raw inputs, derived tables, clock evidence, manifest, report, and final deck.

The paired setup, versions, clocks, CPU points, artifact identities, result file names, and claim boundaries are consolidated in `paired_sustained_manifest_20261017.json`. The read-only clock capture and register interpretation are preserved in `jtag_clock_snapshot_20261017.log` and `clock_readback_20261017.md`.

## Interpretation limits

1. Both backends used the same benchmark payload ladder and deterministic pattern, but the underlying driver APIs and timer sources differ. The comparison describes observed software paths; it does not show that Linux itself caused the large-message rate difference.
2. All Linux repetitions preceded all bare-metal repetitions. The experiment did not alternate backends, so order and thermal effects were not controlled.
3. The capture lacks startup metadata because serial attachment occurred after the runner began. The exact runner ELF and embedded PL image hashes are known from the built boot package, but startup readbacks are not part of this UART capture.
4. PL0 and A53 clock state was read back after the bare-metal set and agrees with the pre-run Linux clock evidence and matching-design prior SCK test. Per-window clock state and simultaneous physical SCK were not captured; this is a bounded configuration comparison, not per-window instrumentation or a clock-sweep limit test.
5. The reported 100% bare-metal busy-wait occupancy must not be compared numerically to Linux's benchmark-thread CPU share as if both were the same CPU-utilization instrument.

## Task 2e disposition

The fixed-trial integrity/latency ladder, 33 Linux sustained windows, 33 bare-metal sustained windows, CPU-metric definitions, raw capture, reproducible parser, comparison table, and clock/operating-point audit are present. **Task 2e is complete as a bounded comparative benchmark framework** under the conditions and limitations above. A separate clock/payload stress test may probe a maximum reliable operating envelope; it is a distinct follow-on experiment and is not needed to reinterpret these measured 60-second rates.
