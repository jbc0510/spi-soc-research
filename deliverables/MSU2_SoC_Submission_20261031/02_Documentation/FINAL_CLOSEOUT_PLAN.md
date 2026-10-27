# MSU-2 SoC deliverable closeout plan

**Deliverable:** *Exploring System on Chip Architectures – Simulation and Emulation Results with Code*  
**Due:** 31 October 2026  
**Status:** Closeout by evidence consolidation; ILA instrumentation is a follow-on item.

## Scope decision

Keep the stated deliverable date and title. Submit the completed, bounded
simulation and ZCU102 emulation evidence with the source, raw captures, result
tables, build records, and reproducibility notes. Do not make a new ILA
bitstream a submission gate. The Vivado 2025.1 ILA build failed before
synthesis, and fixing the encrypted IP delivery plus the AXI/MISO wiring would
take time without changing the validity of the already completed results.

The ILA work remains useful follow-on instrumentation. Its current status and
full failure record are in [`../tmp/ila_trace_capture/TEST_RESULTS.md`](../tmp/ila_trace_capture/TEST_RESULTS.md).

## Evidence to anchor the submission

| Result | Status and defensible claim | Primary evidence |
|---|---|---|
| Linux versus bare-metal SPI performance (2a) | Complete as a bounded ZCU102 comparison. Both paths completed 11 payload sizes × 1,000 transfers with RX verification and zero transfer errors. Observed rates vary with payload; this does not isolate a universal Linux-only overhead. | [`SOW_2A_FINAL_COMPARISON_20261014.md`](../results/linux_axi_spi_bringup_20261013/SOW_2A_FINAL_COMPARISON_20261014.md), paired CSV in the same directory, and revalidation report under `results/linux_axi_spi_revalidation_20261016/` |
| PIO/CDMA mechanisms (2b) | Simulation passes for six internal-loopback payload sizes with byte-for-byte RX checking. This is simulation evidence, not physical DMA throughput or a PIO/DMA crossover. | [`task2b_cdma_sim_20261014/README.md`](../results/task2b_cdma_sim_20261014/README.md), testbench at `hardware/sim/tb_keyhole.sv` |
| Real-time suitability (2c) | Complete as a bounded latency/jitter assessment. It characterizes observed behavior and does not establish hard real-time guarantees or jitter causation. | [`SOW_2C_REALTIME_SUITABILITY_20261014.md`](../results/SOW_2C_REALTIME_SUITABILITY_20261014.md) |
| Benchmark framework (2e) | Paired sustained comparison is complete: 11 payloads × 3 × 60-second windows for each backend; all 66 points pass RX checks. The stress envelope remains open. | [`SOW_2E_PAIRED_SUSTAINED_RESULTS_20261017.md`](../results/task2e_sustainable_runner_20261016/SOW_2E_PAIRED_SUSTAINED_RESULTS_20261017.md), raw captures, CSVs, manifest, parser, and hashes in that directory |
| Hardening, determinism, appliance/security (2d, 2f, 2g) | Present as design assessments and prototypes with explicit open implementation/validation boundaries. Do not describe the live platform as secure boot or the whole Task 2 as closed. | `results/SOW_2D_*`, `results/SOW_2F_FREQSWEEP_20260908.md`, `results/SOW_2G_*`, and [`MSU2_TASK2_SOW_STATUS_20261016.md`](../results/MSU2_TASK2_SOW_STATUS_20261016.md) |

The project status record counts four activities as bounded assessments or a
design deliverable and three as partial. The submission should preserve that
status and avoid turning bounded findings into platform-wide claims.

## Code and presentation

- Shared benchmark contract and applications: `common/`, `linux/src/`, and
  `bare_metal/src/`.
- Reproducible simulation: `hardware/sim/` and its run Tcl.
- Build and result processing: `scripts/` plus the run-specific manifests and
  `SHA256SUMS` files under `results/`.
- Current presentation: [`MSU2_Task2_Evidence_Review_20261023_v54.pptx`](MSU2_Task2_Evidence_Review_20261023_v54.pptx), with its slide guide at
  [`../tmp/ila_trace_capture/SLIDE_GUIDE.md`](../tmp/ila_trace_capture/SLIDE_GUIDE.md). It includes the Vivado-generated block design and marks the ILA/physical measurement boundary. Its evidence cutoff is 23 October; engineering work after that date is captured in the closeout notes, not retroactively represented as presentation evidence.

## Closeout sequence through 31 October

1. **Freeze the evidence set.** Select the specific result folders and source
   revision; rerun only the existing hash checks and reproduction commands
   that are needed to confirm the selected package.
2. **Archive run outputs.** Confirm the raw board captures and CSVs are in the
   host repository, match their manifests, and are readable from a clean copy.
3. **Finish the narrative.** Use the existing deck and results to present the
   design, experiment method, measured comparisons, simulation, code path, and
   limits. Keep the slide 2 Vivado diagram. Describe the ILA as proposed and
   unbuilt; do not imply trace data exists.
4. **Assemble one handoff.** Include the final presentation, source code,
   reproducibility instructions, artifact inventory, SOW status, and hashes.
5. **Submit by the committed date.** Preserve the remaining stress-envelope,
   bare-metal handoff, ILA, physical timing capture, and secure-boot work as
   explicitly named future validation.

## Completion criteria

- A reviewer can locate the source for each reported result and reproduce the
  simulation or host-side analysis from the included commands.
- Raw evidence, derived CSVs, manifests, and artifact hashes agree.
- The presentation matches the submitted evidence and keeps simulation,
  board emulation, and unverified items clearly separated.
- No unresolved ILA or security work is represented as completed.
