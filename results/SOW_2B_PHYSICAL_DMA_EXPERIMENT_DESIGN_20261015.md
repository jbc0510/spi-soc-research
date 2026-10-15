# Task 2b — Proposed physical CDMA-versus-PIO experiment

**Purpose:** Define the smallest safe board experiment that would add physical DMA evidence to the current Task 2b assessment and provide reusable measurements for Task 2f.

**Readiness:** The repository contains no CDMA-enabled `.bit`, `.bit.bin`, or XSA. The known September 29 images are PIO-only. The CDMA topology exists as a Vivado Tcl design and passed simulation; it has not been synthesized into an image for the ZCU102. Therefore this document is an experiment design, not a record of a physical run. Do not access `0xA0010000` or `0xA0020000` on the PIO-only image: those addresses are not established as mapped in that hardware, and the prior unclocked AXI access hung Linux.

## Research question

On the same AXI Quad SPI controller, at the same measured serial clock, does PL AXI CDMA keyhole write produce correct J55 loopback transfers across payload sizes, and how do its end-to-end latency, effective payload rate, and CPU cost compare with PIO?

This is a measured comparison only for the common payload range. It does not make the BRAM-sourced CDMA result representative of DMA from system DDR.

## Hardware configuration required

Build a separate, traceable design from the round-6 v3 topology in `hardware/add_cdma_r6_v3.tcl`, then export a new XSA and bitstream. Retain the September 29 PIO image and artifacts unchanged. Before considering a board run, audit the new XSA and implementation reports for:

- AXI Quad SPI in enhanced AXI4, non-XIP mode, standard SPI, FIFO depth 256, one SS, and the selected SCK ratio.
- AXI CDMA in simple mode, 32-bit data width, keyhole writes enabled, and maximum burst length 16.
- AXI interconnect topology and address map: QSPI `0xA0000000`, CDMA control `0xA0010000`, BRAM `0xA0020000`; PS HPM0 must reach all three.
- PL clock rate and reset-release path for the QSPI, CDMA, BRAM controller, and interconnect.
- No AXI width converter in the CDMA-to-QSPI FIXED-burst path; implementation timing passes.
- BRAM capacity supports 8,192 32-bit source words. Enhanced mode transmits the low byte of each word, so the DMA payload ceiling is 8,192 SPI bytes. BTT is four times the SPI payload size.

The current workstation record says the XCZU9EG synthesis feature was expired. A CDMA bitstream must not be represented as available until a successful, licensed implementation produces and hashes it.

## Test sequence

1. **Identify the exact image.** Record XSA and bitstream hashes, Vivado/Vitis versions, kernel or bare-metal build ID, and the device-tree/platform address map. Confirm the board reports the intended image before touching CDMA registers.
2. **Verify prerequisites at runtime.** Confirm the configured PL clock is enabled, reset is released through the designed mechanism, and the PS-to-PL path is initialized. Use documented driver or test-program interfaces. Do not use blind `devmem` probes.
3. **Run a one-byte smoke test first.** Execute one PIO loopback transfer and one CDMA loopback transfer, verify the expected SPI byte count and received byte, then stop on any AXI error, timeout, unexpected FIFO occupancy, or mismatch.
4. **Use external J55 loopback.** Connect MOSI to MISO as in the PIO baseline. Record measured SCK with the logic analyzer at J55; do not infer the wire clock from the PL clock or a divider setting alone.
5. **Run matched PIO and CDMA cases.** Use the CPU-driven path to the same enhanced-mode QSPI registers for the PIO control; verify the chosen PIO routine works with the enhanced AXI4 interface before collecting a curve. Do not assume the legacy `XSpi` driver is compatible without checking it against this mode. Use deterministic pseudo-random payload bytes with a recorded seed. Test 1, 8, 16, 64, 128, 256, 512, 1,024, 4,096, and 8,192 bytes. Run 1,000 trials per size if the smoke test is clean. Randomize or alternate PIO/CDMA order within each size to limit drift.
6. **Respect FIFO and full-duplex constraints.** Enhanced mode does not support simultaneous read and write transactions; the RX FIFO depth is 256 bytes. For payloads above 256 bytes, use 256-byte-or-smaller chunks and drain/verify each RX chunk before proceeding. Apply identical chunk boundaries to PIO and CDMA. Enable `SPICR.SPE` before each CDMA transfer; simulation shows CDMA can stall indefinitely if the TX FIFO fills while SPE is clear.
7. **Measure comparable quantities.** For each whole-payload trial, measure end-to-end latency from transfer start through final RX verification, with configuration and source-pattern generation outside the timed interval. Separately measure application wall time and process/thread CPU time. Report median, p95, p99, maximum, payload bytes/s, errors, timeouts, mismatches, and failed trials. Record SCK, PL clock, CPU operating point, and temperature if available.
8. **Stop at the first failure.** Preserve the serial log, status registers read through the test program, logic-analyzer capture, and test row. Do not retry a hung AXI access or continue to larger payloads until the failure is understood.

## Pass criteria and interpretation

- Both paths transfer the requested count with zero timeouts, AXI errors, FIFO overruns, and receive mismatches.
- The received bytes match the generated sequence at every tested size; the transfer count is established from SPI bytes, not CDMA BTT bytes.
- The measured SCK is equivalent for the PIO and CDMA cases on the shared image. If it differs by more than instrument uncertainty, no direct rate comparison is reported.
- Compare only 1–8,192 bytes. The existing PIO curve extends to 65,536 bytes, so the common-range comparison must be explicit.
- Separate transfer latency/rate from CPU time. Because the CPU prepares the BRAM source and drains RX, the test does not claim zero-CPU DMA or pure transmit-side offload. Include setup/copy/drain work in a separate application-level CPU metric.
- A clean result demonstrates the CDMA hardware path on this image and yields a valid measured curve for this BRAM-sourced architecture. It does not characterize DDR-sourced DMA or close Task 2f's standard-driver-versus-optimized-DMA evaluation by itself.

## Current decision

No physical DMA experiment can be run with the repository's currently available validated bitstreams: none contains the CDMA topology. The next prerequisite is a successful build and artifact audit for a separate CDMA image. The existing Task 2b assessment remains based on physical PIO, the previously measured negative ZDMA result, and simulated CDMA characterization; the physical experiment above is additional evidence, not a claim that it has already run.
