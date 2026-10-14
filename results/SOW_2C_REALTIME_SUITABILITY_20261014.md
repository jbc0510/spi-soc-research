# SOW Task 2c — Real-Time Suitability Assessment

**Criterion:** “Evaluate Real Time Suitability — Analyze latency and jitter behavior to assess OS support for deterministic execution.”

## Finding

The measured Linux SPI path is functionally reliable in the captured runs, but its timing varies at microsecond scale and varies with CPU operating point. These measurements do not establish hard real-time behavior or a deadline guarantee. They support a bounded conclusion: this Linux configuration provides usable best-effort SPI service for the tested workloads, while the available evidence is insufficient to claim deterministic deadline execution.

## Evidence reviewed

The October 2026 Linux-versus-bare-metal comparison used the same ZCU102 AXI Quad SPI hardware, J55 external loopback, payload patterns, and 1,000 trials at each of 11 payload sizes. Each environment completed 11,000 transfers with zero API errors and zero receive mismatches. The comparison reports mean, minimum, maximum, and population standard deviation for each payload size. Linux standard deviation exceeded the bare-metal value at all 11 sizes. For example:

| Payload | Linux mean | Linux standard deviation | Linux min–max | Bare-metal standard deviation |
|---:|---:|---:|---:|---:|
| 1 B | 28.031 µs | 3.724 µs | 24.642–87.539 µs | 0.0368 µs |
| 64 B | 64.577 µs | 1.102 µs | 62.306–75.828 µs | 0.00884 µs |
| 65,536 B | 43.287 ms | 3.325 µs | 43.283–43.342 ms | 0.119 µs |

The different timer sources and execution paths matter: Linux uses `CLOCK_MONOTONIC_RAW` around an SPI ioctl, while bare metal uses `XTime_GetTime` around its XSpi interrupt path. No independent timer cross-calibration or measurement-overhead calibration was recorded. The absolute statistics describe the observed runs, but a precise cross-OS jitter ratio is not established.

A separate September 2026 Linux CPU-frequency sweep ran the same 11 payload sizes and 1,000 trials per size at four confirmed A53 operating points. At 64 KiB, standard deviation rose from 3.87 µs at 1,200 MHz to 5.17 µs at 600 MHz, 8.65 µs at 400 MHz, and 14.23 µs at 300 MHz. The capture reports zero errors and zero involuntary context switches across its 44,000 timed trials. This is evidence that timing variability in this measured setup changes with CPU frequency; it does not identify the mechanism causing that change.

## Interpretation and limits

The error-free transfer results establish functional success for the tested payloads and conditions. The observed spread and the CPU-frequency sweep show timing variability, so the data cannot support a claim of deterministic completion within a deadline. No deadline was specified or tested, and the captures do not include concurrent-load stress, missed-deadline counts, per-sample percentile/tail analysis, or a controlled comparison of Linux scheduling/preemption configurations. The aggregate statistics also cannot show the shape or frequency of rare latency outliers beyond the reported extrema.

The prior frequency-sweep report identifies the AXI SPI driver path as polling-based in that Linux image. Polling is a possible contributor to timing behavior, but the captures do not instrument or prove a causal mechanism. The earlier retracted Linux jitter claims documented in `results/LINUX_JITTER_PROVENANCE.md` are excluded from this assessment.

## Conclusion

For the tested ZCU102 configuration, Linux successfully performs the measured SPI transfers, but the current evidence establishes only best-effort timing behavior. It does not establish hard real-time suitability. Closing the hard-determinism question would require a defined deadline and workload, per-transfer latency samples or tail percentiles, concurrent-load tests, and controlled scheduling/preemption experiments with timer overhead characterized.

## Reproduction and source evidence

- October comparison summary: `results/linux_axi_spi_bringup_20261013/linux_vs_baremetal_comparison_20261014.csv`
- October Linux raw capture: `results/linux_axi_spi_bringup_20261013/linux_benchmark_20261014.log`
- October comparison report: `results/linux_axi_spi_bringup_20261013/SOW_2A_FINAL_COMPARISON_20261014.md`
- September frequency-sweep report: `results/SOW_2F_FREQSWEEP_20260908.md`
- September raw capture: `docs/environment/zcu102-2_2f_freqsweep_20260908.log`

This report reuses recorded evidence; it adds no hardware measurements and does not mark Task 2f complete.
