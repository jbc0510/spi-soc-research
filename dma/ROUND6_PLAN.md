# Round 6 Plan — PL DMA pivot: AXI CDMA (KeyHole) -> AXI Quad SPI

Status as of 2026-08-04, after round-5 close (see ANCHOR_RESULT_round5.md).

## Gate checks — DONE
- Vivado synthesis license for xczu9eg CONFIRMED on stile 2026-08-04:
  probe synth passed ("Got license for feature 'Synthesis' and/or
  device 'xczu9eg'", 0 errors). May-report license risk is retired.
- Vitis 2025.1 working on stile; build->bootgen->SD->UART pipeline proven.

## Design direction (verified against AMD PG034, AXI CDMA)
- AXI CDMA is MM-to-MM and has KeyHole Write/Read: FIXED-address AXI
  transactions, supported in Simple and SG modes. Constraint: set
  Max Burst Length = 16 when keyhole is enabled; do not toggle the
  keyhole bit mid-transfer.
- This is the supported PL analog of exactly what ZDMA lacks — extends
  the paper's hard-vs-soft theme to the DMA engines themselves.
- NOT AXI DMA: that IP is MM<->AXI-Stream, and AXI Quad SPI has no
  stream port (same interface-class mismatch that sank ZDMA).
- Keyhole fixes addressing, not flow control: benchmark still paces
  per chunk (<= Quad SPI FIFO depth 256), CPU orchestrates chunks only.
  The measurable win vs PIO is CPU utilization + burst FIFO service.

## Session plan (microsteps)
1. Open spi_benchmark.bd (migrated 2025.1 Tcl) — no edits, confirm intact.
2. Add axi_cdma: simple mode, KeyHole Write+Read on, Max Burst 16,
   32-bit data width. Wire: S_AXI_LITE <- PS master; M_AXI -> smartconnect
   -> { AXI Quad SPI S_AXI, PS S_AXI_HP (DDR) }. Assign addresses, validate.
3. Behavioral sim of one keyhole chunk into the Quad SPI FIFO — confirm
   AWADDR holds constant in the waveform BEFORE any bitstream.
4. Optional: ILA on the CDMA->QuadSPI AXI channel (hardware evidence).
5. Synth/impl/bitstream/XSA (batch Tcl), commit with md5s.
6. Vitis: rebuild platform from new XSA in ws2, port benchmark to CDMA
   regs (chunk-paced), reuse anchor/verdict framework unchanged.

## Process reminders
- Paste blocks < 3 KB (cat > / cat >>). Start screen with
  `screen -L -Logfile <path>` BEFORE powering the board.
- Round-4 physics_fail check: RESOLVED (=11, per ANCHOR_RESULT_round4.md line 9).
