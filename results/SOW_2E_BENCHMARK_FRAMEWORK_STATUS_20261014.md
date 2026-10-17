# SOW Task 2e — Comparative Benchmarking Framework Status

**SOW activity:** “Comparative Benchmarking Framework — Develop a unified testing harness to measure SPI performance across both software environments.” The following SOW clauses call for identical test patterns and metrics including maximum sustainable throughput, transaction latency, and CPU utilization.

**Disposition as of 17 October 2026:** Task 2e is complete as a bounded comparative benchmark framework. The shared fixed-run and sustained-run workflows now provide validated latency, integrity, sustainable application payload rate, and CPU-use basis for both software environments. Bare-metal occupancy is explicitly derived from the dedicated busy-wait execution model, not a PMU counter. The evidence is not a universal hardware ceiling, per-window clock instrumentation, or causal isolation of Linux overhead.

## Framework already in place

The shared `common/spi_benchmark_contract.h` defines one payload ladder (1 through 65,536 bytes), 1,000 attempts per size, the incrementing data pattern, poisoned receive buffer, byte-for-byte verification, and common result fields. The Linux `spi_benchmark_v3_rxverify` and Vitis AXI standalone benchmark use that contract. `scripts/compare_task2a_runs.py` checks payload order, attempts, success counts, transfer errors, timeouts, and RX mismatches before producing the paired comparison.

The October 2026 physical comparison used the validated AXI Quad SPI, the same bitstream and J55 external loopback, and 11,000 successful transfers in each software environment. It recorded per-transfer latency, minimum, maximum, standard deviation, API status, receive integrity, and effective payload rate. The maximum rate in this fixed payload ladder was 1.514 MB/s for Linux at 65,536 bytes and 1.206 MB/s for bare metal at 65,536 bytes. These are maxima observed in this benchmark run; the run was not designed to establish maximum sustainable throughput under a defined saturation or duration criterion.

## CPU-utilization analysis added

The Linux raw log includes `CLOCK_THREAD_CPUTIME_ID` and `CLOCK_MONOTONIC_RAW` totals for each 1,000-transfer loop. The new `scripts/task2e_analyze_framework_metrics.py` validates these records against the common payload contract and derives benchmark-thread CPU share as `thread CPU time / loop wall time × 100`. For the captured run, the value falls from 67.876% at 1 byte to 1.474% at 65,536 bytes. This is the benchmark thread’s CPU share normalized to one core during the measured loop; it is not whole-system utilization or power.

The existing bare-metal firmware loops on `irq_state.terminal` while each XSpi interrupt-driven transfer completes. That code structure indicates the benchmark core remains busy during the sweep, but the existing capture does not include a PMU or other measured CPU-utilization counter. The new CSV marks bare-metal CPU use as not measured instead of presenting a source-level inference as a measurement.

## Closure work completed and scope limits

The closure experiment in `results/SOW_2E_BENCHMARK_CLOSURE_EXPERIMENT_20261015.md` operationally defined maximum observed sustainable rate as repeated 60-second continuous points across 11 payload sizes, with three repetitions, byte verification, stop-on-error behavior, raw logs, and per-size medians. The physical Linux and bare-metal sets completed all 33 points each with zero errors or mismatches. See the paired report and `results/task2e_sustainable_runner_20261016/clock_readback_20261017.md` for derived/register clock evidence and its limits.

The original execution plan proposed alternating backend order and simultaneous/per-window clock sampling. The actual runs were ordered Linux first, bare metal second. Clock register readback and matching-configuration J55 evidence support a bounded result, but no per-window instrumentation or thermal/order control is claimed. A separate maximum-reliable-envelope clock/payload stress test remains a follow-on experiment, not a prerequisite for the completed Task 2e framework criterion.

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

This initial status note was written before the paired 60-second sustained runs. The later physical results close Task 2e as a bounded comparative benchmark framework; see `results/task2e_sustainable_runner_20261016/SOW_2E_PAIRED_SUSTAINED_RESULTS_20261017.md`, `paired_sustained_manifest_20261017.json`, and `clock_readback_20261017.md`. This closure reports the maximum rate observed under the defined benchmark, not an absolute hardware limit.
