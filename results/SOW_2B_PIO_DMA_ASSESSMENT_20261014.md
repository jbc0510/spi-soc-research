# MSU-2 Task 2b — PIO and DMA transfer-mechanism assessment

**Status: Task 2b is closed as a performance-characteristics assessment.** PIO is measured on the target across 11 payload sizes; the viable CDMA path is characterized in simulation across six sizes; the attempted ZDMA-to-PS-SPI path is documented as invalid for performance measurement. Target-board DMA performance and a direct physical PIO-versus-DMA comparison are not claimed.

## Governing requirement

The controlling document is `MSU-2_SOW_Final (1).docx`, revision 2026-02-23, in the workstation Downloads folder. Task 2b says: “Analyze Data Transfer Mechanisms — Assess the performance characteristics of Programmed I/O (PIO) and Direct Memory Access (DMA) across varying payload sizes.” This assessment separates measured PIO data, simulated CDMA characteristics, and the invalid ZDMA result, with the evidence class explicit for each result. The criterion asks for an assessment across sizes; it does not explicitly require a physical DMA sweep. Hardware DMA throughput and direct physical PIO-versus-DMA comparison remain open under Task 2f's separate driver-performance comparison.

## PIO baseline: measured on the validated AXI Quad SPI

The PIO measurements are the Linux and bare-metal `XSpi_Transfer` results reported in [`SOW_2A_FINAL_COMPARISON_20261014.md`](linux_axi_spi_bringup_20261013/SOW_2A_FINAL_COMPARISON_20261014.md), using the same September 29 bitstream, AXI Quad SPI at `0xA0000000`, J55 external loopback, 11 payload sizes, and 1,000 trials per size. Both runs passed with zero transfer errors, timeouts, or receive mismatches. The physical SCK measurement associated with this bitstream is approximately 51 MHz at J55 pin 4.

| Payload | Bare-metal PIO mean | Linux PIO mean | BM effective payload rate | Linux effective payload rate |
|---:|---:|---:|---:|---:|
| 1 B | 6.922 µs | 28.031 µs | 0.144 MB/s | 0.036 MB/s |
| 8 B | 16.913 µs | 30.373 µs | 0.473 MB/s | 0.263 MB/s |
| 16 B | 28.318 µs | 33.492 µs | 0.565 MB/s | 0.478 MB/s |
| 64 B | 96.974 µs | 64.577 µs | 0.660 MB/s | 0.991 MB/s |
| 128 B | 188.494 µs | 106.333 µs | 0.679 MB/s | 1.204 MB/s |
| 256 B | 371.533 µs | 189.646 µs | 0.689 MB/s | 1.350 MB/s |
| 512 B | 584.968 µs | 358.919 µs | 0.875 MB/s | 1.427 MB/s |
| 1,024 B | 1.008 ms | 0.697 ms | 1.016 MB/s | 1.468 MB/s |
| 4,096 B | 3.548 ms | 2.726 ms | 1.154 MB/s | 1.502 MB/s |
| 16,384 B | 13.709 ms | 10.840 ms | 1.195 MB/s | 1.512 MB/s |
| 65,536 B | 54.350 ms | 43.287 ms | 1.206 MB/s | 1.514 MB/s |

Effective payload rate is payload bytes divided by the end-to-end API latency; it is not wire throughput. Full statistics, errors, and per-run records remain in the linked Task 2a comparison CSV and source CSV/logs.

## DMA evidence and what it supports

| Candidate path | Evidence | Supported conclusion | Not supported |
|---|---|---|---|
| ZynqMP ZDMA → PS Cadence SPI FIFO | Round 4 and Round 5 board runs swept 11 payload sizes. All 11 failed the SPI wire-time floor; Round 5 reports 10 RX-mismatch sizes. The 65,536-byte transfer completed in about 474 µs although the 0.9766 MHz SCK wire floor was about 0.54 s. Readback confirms the attempted burst configuration reached hardware. | This ZDMA/SPI pairing does not pace writes to SPI and is invalid for SPI performance measurement. It is a negative architecture result, not a slow DMA implementation. | No valid ZDMA throughput, latency, or crossover point. Its reported completion times must not be compared with PIO. |
| PL AXI CDMA keyhole → enhanced AXI Quad SPI | Vivado simulation in `hardware/sim/R6_SIM_FINDINGS.md` and `hardware/logs/r6sim_1e_20260810_1106.log` showed a 16-beat FIXED write held the address at DTR and accepted 16 words; INCR control accepted 5 of 16 with successful AXI status. The October 14 fresh-build sweep verified 1, 8, 16, 64, 128, and 256-byte internal-loopback transfers with zero mismatches. | In this model, FIXED keyhole writes to DTR complete when SPE is enabled, enhanced mode emits one SPI byte per 32-bit AXI beat, and effective payload rate rises from 0.346 MB/s at 1 byte to 0.778 MB/s at 256 bytes. The result characterizes the IP behavior at 100 MHz input clock and configured 16:1 SCK ratio. | No target-board CDMA test, external J55 loopback, CPU-offload result, silicon validation, or physical PIO-to-DMA crossover. The source is an AXI VIP memory model and SPI uses internal loopback; simulated rates are not directly comparable with the physical PIO results. |

The old PS-SPI DMA notes in `dma/DESIGN_NOTES.md` describe exploratory PS SPI/GDMA assumptions and stale baseline numbers. They are not used as measured results for this assessment. The later round 4/5 anchor reports and final CDMA simulation findings are the evidence sources above.

## Assessment and current recommendation

PIO has a valid size sweep on the target hardware. The tested ZDMA route cannot provide a meaningful DMA comparison because it completes without SPI pacing and fails the physical timing/data-integrity checks. CDMA has a six-point simulated curve that shows the expected approach toward the model’s serial-clock ceiling as payload grows. That curve characterizes the peripheral-facing IP model; it does not establish target-board CDMA performance or a PIO-to-DMA crossover threshold.

For present use, select PIO for every validated payload from 1 through 65,536 bytes. This is a qualification-based recommendation: PIO is the only path in this evidence set with successful end-to-end J55 loopback across that range. Treat CDMA as an experimental path until a SPE-enabled size sweep verifies serial clocking, transfer completion, receive integrity, and CPU use. Do not select ZDMA-to-PS-SPI for transfers.

This recommendation is not a claim that PIO is intrinsically faster than CDMA. It records which path is presently validated and avoids inventing a DMA crossover from simulation constraints or a failed ZDMA implementation. The SOW’s later transfer-size-to-refined-software/DMA mapping deliverable and Task 2f’s standard-driver-versus-optimized-DMA comparison remain open pending valid DMA data.

## Task 2b closeout decision

The Task 2b mechanism assessment is complete: it combines the physical 11-size PIO curve, the failed physical ZDMA route as a negative result, and a six-size simulation curve for the viable CDMA-to-AXI-SPI topology. Vivado 2025.1/XSim runs when launched with host-level local IPC access; the identical smoke test failed in the restricted execution sandbox and passed outside it. No global tool, OS, or target-board settings were changed. The CDMA timing interval begins immediately before the BTT register write and ends after TX FIFO empty plus a 2 µs final-shift allowance. The model uses a 100 MHz input clock, 16:1 SCK ratio, AXI VIP memory, and internal SPI loopback. These points are useful for comparing the simulated CDMA design across sizes, but cannot establish target-board performance, CPU offload, or a crossover against physical PIO. The next step, if CDMA implementation is pursued, is a DMA-capable bitstream and hardware test; the expired synthesis feature currently blocks that. Task 2b closure does not close Task 2f’s standard-driver-versus-optimized-DMA comparison. No clock, reset, FPGA, or target-board state was changed for this assessment.

## Reproduction and evidence paths

- PIO calculation: `python3 scripts/compare_task2a_runs.py --linux results/linux_axi_spi_bringup_20261013/linux_benchmark_20261014.csv --baremetal results/linux_axi_spi_bringup_20261013/baremetal_baseline_extracted.csv --output /tmp/task2b_comparison.csv`
- PIO comparison and integrity metadata: `results/linux_axi_spi_bringup_20261013/linux_vs_baremetal_comparison_20261014.csv`, `artifact_hashes.sha256`, and `linux_build_manifest.json`.
- ZDMA board results: `dma/ANCHOR_RESULT_round4.md`, `dma/ANCHOR_RESULT_round5.md`, and `dma/logs/uart_round5_burstlen0.log`.
- CDMA simulation findings and source: `hardware/sim/R6_SIM_FINDINGS.md`, `hardware/sim/tb_keyhole.sv`, `hardware/sim/sim_keyhole_bd.tcl`, and `hardware/logs/r6sim_1e_20260810_1106.log`.
- October 14 simulation replay attempt: `SOW_2B_XSIM_RETRY_20261014_vivado.log` and `SOW_2B_XSIM_RETRY_20261014_direct.log`.
- October 14 simulator control test: `SOW_2B_XSIM_SMOKE_20261014_elab.log`, `SOW_2B_XSIM_SMOKE_20261014_runtime.log`, and `SOW_2B_XSIM_SMOKE_20261014_runtime_nolibpath.log`.
- Reproducible fresh-build CDMA test: `hardware/sim/run_task2b_cdma_loopback.tcl`; raw Vivado and XSim logs in `results/task2b_cdma_sim_20261014/`. The test uses the Xilinx AXI CDMA, AXI Quad SPI, and AXI VIP memory/master models; the 128-byte SPI test uses the core's internal loopback.
- Simulated CDMA payload curve: `results/task2b_cdma_sim_20261014/cdma_simulated_sweep.csv`. Timings are model timing only and are not combined with the physical PIO timing table.
- Optional physical follow-on experiment design and image-readiness gate: `results/SOW_2B_PHYSICAL_DMA_EXPERIMENT_DESIGN_20261015.md`. No CDMA-enabled bitstream is currently present in the repository.
- Vivado version on the Morgan workstation: 2025.1. The archived September 2026 synthesis log records the XCZU9EG synthesis feature as expired; a new FPGA build was not attempted for this assessment.
- SHA-256 of the controlling local SOW (`/home/opentitan/Downloads/MSU-2_SOW_Final (1).docx`): `047f1865e1c956fc97e39ce7d057b03c27ecdc7ba9ef99f7bb1229984faf8634`.
