# MSU-2 SoC submission package

**Deliverable:** Exploring System on Chip Architectures – Simulation and Emulation Results with Code  
**Due date:** 31 October 2026  
**Package prepared:** 2026-10-27  
**Package status:** Evidence package candidate for final review.

## What this package contains

- The 22-slide evidence review and slide guide.
- Source for the sustained board benchmark pinned to the exact source revision
  named in the run manifest, plus Vivado simulation and block-design scripts.
- The exercised Linux operator-menu bundle, its binaries/overlays, and its
  internal SHA256 manifest.
- Linux/bare-metal fixed-trial results, paired 60-second results, raw serial
  captures, CSVs, build/run manifests, simulation logs, and matching reports.
- The validated ratio-2 PL XSA and implementation reports, plus the board
  validation and J55 loopback records.
- Bounded 2c/2d/2f/2g reports and the current SOW activity status.
- A separate ILA status note and Vivado failure log from 27 October. This is
  explicitly open work and contains no captured ILA trace.

## Main result claims and limits

1. The ZCU102 Linux and bare-metal SPI paths completed the documented
   fixed-trial payload ladder with byte-for-byte RX verification and zero
   transfer errors.
2. The paired sustained comparison completed 33 Linux and 33 bare-metal
   60-second points with zero recorded errors, timeouts, short transfers, or
   mismatches. Task 2e remains partial because the clock/payload stress
   envelope has not been established.
3. The CDMA-to-AXI-SPI result is a passing six-size internal-loopback
   simulation. It does not claim physical DMA throughput or a PIO/DMA
   crossover.
4. Latency and jitter findings are bounded to the recorded configurations;
   they do not establish hard real-time guarantees or isolate a universal
   Linux-only cost.
5. The presentation's evidence cutoff is 23 October 2026. The 27 October ILA
   investigation is recorded separately as an unsuccessful build attempt.
   The live design has no new ILA bitstream/`.ltx` or captured logic trace.
6. Bare-metal handoff, reliable clock/payload limits, and full secure-boot
   validation remain open. This package does not claim the whole Task 2 or a
   hardware-rooted secure boot chain is complete.

## Suggested review order

1. `01_Presentation/` for the concise results story.
2. `02_Documentation/SOW_STATUS_20261016.md` for activity-level status.
3. `04_Evidence/2a_linux_baremetal_comparison/` and
   `04_Evidence/2e_paired_sustained/` for the main board results.
4. `04_Evidence/2b_cdma_simulation/` for the simulation result.
5. `03_Source/` and the `04_Evidence/` manifests/checksums for code and
   reproducibility.
6. `05_Open_Items/` for unresolved ILA and other boundaries.

## Reproduction pointers

- CDMA simulation: see `04_Evidence/2b_cdma_simulation/README.md` and
  `03_Source/project/hardware/sim/run_task2b_cdma_loopback.tcl`.
- Fixed-trial analysis: see
  `04_Evidence/2a_linux_baremetal_comparison/SOW_2A_FINAL_COMPARISON_20261014.md`
  and `03_Source/project/scripts/compare_task2a_runs.py`.
- Paired sustained report includes the parser command and exact hardware,
  software, source, image, and clock identity. The precise as-run source
  snapshot is under `03_Source/as_run_2e/`.
- The original combined development `BOOT_AXI_SUSTAINED_20261016.BIN` is
  deliberately not included. Its SHA-256 and component details remain in the
  paired run manifest and checksum records; the individual as-run application
  ELF, Linux executable, source, bitstream, and XSA evidence are included.

## Integrity

`SHA256SUMS` covers every file in this package except `SHA256SUMS` itself.
Verify from this directory with `sha256sum -c SHA256SUMS`. Result folders also
retain their original manifests/checksum files. Those original checksums are
preserved as received and are not replaced by the package-level manifest.
