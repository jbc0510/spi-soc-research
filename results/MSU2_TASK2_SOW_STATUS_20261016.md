# MSU-2 Task 2 SOW status as of 17 October 2026

## Conclusion

The 23 February 2026 Statement of Work defines seven Task 2 activities. The repository’s labels 2a–2g are internal shorthand mapped in order to those activities; they are not headings in the SOW itself. Evidence supports closing four activities as bounded assessments or a design deliverable. Three remain partial. No finding here closes Task 2 as a whole or the separate Task 1 requirements.

## Activity-by-activity status

| SOW activity | Internal label | Status | Evidence and boundary |
|---|---|---|---|
| Characterize Performance Gaps — quantify Linux SPI-stack overhead relative to direct hardware execution | 2a | Complete as a bounded comparison | Revalidated 16 October: the same ZCU102 AXI Quad SPI and J55 loopback ran 11 payload sizes × 1,000 trials on Linux and bare metal, with zero transfer errors, timeouts, or receive mismatches. The report describes the measured path difference; timer and CPU-point differences prevent attributing it to a universal kernel-only cost. |
| Analyze Data Transfer Mechanisms — assess PIO and DMA across payload sizes | 2b | Complete as a performance-characteristics assessment | Physical PIO results cover 11 payload sizes. PL AXI CDMA simulation covers six sizes. The attempted ZDMA-to-PS-SPI measurements failed the wire-time and integrity checks and are correctly treated as invalid performance data. No physical CDMA throughput or PIO-versus-DMA crossover is claimed. |
| Evaluate Real Time Suitability — analyze latency and jitter for deterministic execution | 2c | Complete as a bounded suitability assessment | Captured measurements characterize best-effort latency and variability. They do not establish a hard deadline, hard real-time behavior, or the cause of observed jitter. |
| System Hardening — design a minimal environment that supports secure boot, reliable updates, and automated recovery | 2d | Design complete; implementation is separate and open | The architecture/design is documented. Existing environment-copy fallback evidence is limited to one CRC-corruption case. It does not prove verified boot, atomic image updates, or automated recovery across boot assets and root filesystem. |
| Comparative Benchmarking Framework — unified harness, identical patterns, sustainable throughput, latency, CPU utilization | 2e | Partial — paired benchmark complete; stress envelope open | Both backends completed 33 sustained points each across 11 sizes × 3 × 60-second windows, plus the fixed 1,000-trial integrity/latency ladder, with zero errors or mismatches. Clock/CPU configuration evidence and paired rates are documented. The planned reliable clock/payload stress test has not run; therefore maximum reliable operating limits and the associated Task 2e criterion remain open. |
| OS Optimization and Determinism Analysis — tune OS; compare kernel settings, interrupt handling, CPU-frequency scaling; compare standard driver and optimized DMA | 2f | Partial | Four CPU-frequency points were measured and interrupt handling was assessed on the tested polling path. The configured preemption model was not varied; this requires a kernel rebuild. A valid physical comparison of the standard driver and optimized DMA remains open. Frequency correlation does not establish jitter causation. |
| Minimal Appliance Development and Security — essential filesystem, robust update, pre-execution integrity verification | 2g | Partial | Host A/B update and U-Boot signed-FIT prototypes pass their defined tests, and a separate four-case software demo ran on the target CPU. The live board audit found the active SD image unsigned and generic fail-open boot targets. There is no integrated hardware-rooted trust chain, persistent A/B update/rollback, or target power-loss/recovery validation. |

## Evidence references

- Performance comparison: `results/linux_axi_spi_revalidation_20261016/README.md`, `results/linux_axi_spi_revalidation_20261016/linux_vs_baremetal_fixed_trial_20261016.csv`, and prior analysis `results/linux_axi_spi_bringup_20261013/SOW_2A_FINAL_COMPARISON_20261014.md`
- PIO and DMA assessment: `results/SOW_2B_PIO_DMA_ASSESSMENT_20261014.md`
- Real-time suitability: `results/SOW_2C_REALTIME_SUITABILITY_20261014.md`
- Hardening design and implementation gap: `results/SOW_2D_SYSTEM_HARDENING_DESIGN_20261014.md` and `results/SOW_2D_SYSTEM_HARDENING_GAP_REVIEW_20261014.md`
- Benchmark framework: `results/SOW_2E_SUSTAINED_RUNNER_20261016.md`, `results/task2e_sustainable_runner_20261016/SOW_2E_PAIRED_SUSTAINED_RESULTS_20261017.md`, and `results/task2e_sustainable_runner_20261016/clock_readback_20261017.md`
- CPU-frequency/determinism findings: `results/SOW_2F_FREQSWEEP_20260908.md`
- Appliance/security prototypes and live audit: `results/SOW_2G_AB_UPDATE_PROTOTYPE_20261014.md`, `results/SOW_2G_UBOOT_FIT_SANDBOX_20261015.md`, `results/SOW_2G_ZCU102_HARDENING_DEMO_20261015.md`, and `results/task2g_live_board_audit_20261015/README.md`

## Next work, in order

1. Complete the Task 2e clock/payload stress test and report the measured reliable operating envelope before closing 2e.
2. Add a valid target-board DMA test if the selected design and available hardware resources support it; keep this distinct from the existing XSim CDMA result.
3. Decide whether to rebuild/test a different Linux preemption configuration. The existing frequency sweep alone does not satisfy that SOW axis.
4. Integrate signed boot and persistent A/B recovery with the real ZynqMP boot chain, then validate valid, tampered, interrupted, failed-health, and recovery cases on a designated test image.
5. Audit Task 1 deliverables separately before making any project-wide completion statement.

The document due dates and final-report requirement in the SOW are separate contract deliverables. This status report evaluates technical evidence; it does not claim that monthly or interim/final administrative reports have been submitted.
