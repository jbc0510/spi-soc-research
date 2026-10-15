# SOW Task 2e — Comparative Benchmarking Framework Status

**SOW activity:** “Comparative Benchmarking Framework — Develop a unified testing harness to measure SPI performance across both software environments.” The following SOW clauses call for identical test patterns and metrics including maximum sustainable throughput, transaction latency, and CPU utilization.

**Disposition:** The paired fixed-run benchmark and comparison framework is reproducible for latency, integrity, and effective payload rate. This criterion remains partially complete because maximum sustainable throughput has not been stress-tested and the present bare-metal capture has no directly measured CPU-utilization counter.

## Framework already in place

The shared `common/spi_benchmark_contract.h` defines one payload ladder (1 through 65,536 bytes), 1,000 attempts per size, the incrementing data pattern, poisoned receive buffer, byte-for-byte verification, and common result fields. The Linux `spi_benchmark_v3_rxverify` and Vitis AXI standalone benchmark use that contract. `scripts/compare_task2a_runs.py` checks payload order, attempts, success counts, transfer errors, timeouts, and RX mismatches before producing the paired comparison.

The October 2026 physical comparison used the validated AXI Quad SPI, the same bitstream and J55 external loopback, and 11,000 successful transfers in each software environment. It recorded per-transfer latency, minimum, maximum, standard deviation, API status, receive integrity, and effective payload rate. The maximum rate in this fixed payload ladder was 1.514 MB/s for Linux at 65,536 bytes and 1.206 MB/s for bare metal at 65,536 bytes. These are maxima observed in this benchmark run; the run was not designed to establish maximum sustainable throughput under a defined saturation or duration criterion.

## CPU-utilization analysis added

The Linux raw log includes `CLOCK_THREAD_CPUTIME_ID` and `CLOCK_MONOTONIC_RAW` totals for each 1,000-transfer loop. The new `scripts/task2e_analyze_framework_metrics.py` validates these records against the common payload contract and derives benchmark-thread CPU share as `thread CPU time / loop wall time × 100`. For the captured run, the value falls from 67.876% at 1 byte to 1.474% at 65,536 bytes. This is the benchmark thread’s CPU share normalized to one core during the measured loop; it is not whole-system utilization or power.

The existing bare-metal firmware loops on `irq_state.terminal` while each XSpi interrupt-driven transfer completes. That code structure indicates the benchmark core remains busy during the sweep, but the existing capture does not include a PMU or other measured CPU-utilization counter. The new CSV marks bare-metal CPU use as not measured instead of presenting a source-level inference as a measurement.

## Remaining closure work

1. Define “maximum sustainable throughput” operationally (payload, duration or transaction count, error criterion, and stability window) and run a repeated/continuous stress sweep on the physical loopback.
2. Add an explicit CPU-use measurement to the bare-metal harness and capture it under the same test interval; document its measurement basis and limitations alongside the Linux thread metric.
3. Turn the two backend binaries into a single orchestration workflow with a shared run manifest and schema. Current execution/capture procedures remain target-specific even though they share the payload contract and comparison validator.
4. Re-run the completed suite after the harness changes and preserve raw logs, per-transfer results, CPU counters, SCK configuration, CPU operating point, and hashes together.

The concrete paired closure experiment is specified in `results/SOW_2E_BENCHMARK_CLOSURE_EXPERIMENT_20261015.md`. It defines the 60-second sustained-throughput window, three repeats, CPU-metric basis, stop conditions, and run manifest. It has not been executed because the target was unreachable from the workstation session on 2026-10-15.

## Reproduction

Run the existing comparison validator first, then derive the CPU metrics:

```sh
python3 scripts/compare_task2a_runs.py \
  --linux results/linux_axi_spi_bringup_20261013/linux_benchmark_20261014.csv \
  --baremetal results/linux_axi_spi_bringup_20261013/baremetal_baseline_extracted.csv \
  --output /tmp/task2e_comparison.csv

python3 scripts/task2e_analyze_framework_metrics.py \
  --comparison /tmp/task2e_comparison.csv \
  --linux-log results/linux_axi_spi_bringup_20261013/linux_benchmark_20261014.log \
  --output results/linux_axi_spi_bringup_20261013/task2e_framework_metrics_20261014.csv
```

## Sources

- `common/spi_benchmark_contract.h`
- `linux/src/spi_benchmark_v3_rxverify.c`
- `bare_metal/src/spi_benchmark_bare_axi.c`
- `scripts/compare_task2a_runs.py`
- `scripts/task2e_analyze_framework_metrics.py`
- `results/linux_axi_spi_bringup_20261013/linux_benchmark_20261014.log`
- `results/linux_axi_spi_bringup_20261013/linux_vs_baremetal_comparison_20261014.csv`
- Full method and timer caveats: `results/linux_axi_spi_bringup_20261013/SOW_2A_FINAL_COMPARISON_20261014.md`

The new metric CSV is derived from existing captures and adds no new hardware measurement. This report does not claim maximum sustainable throughput or close the entire Task 2e criterion.
