# ZCU102 AXI Quad SPI Ratio-2 / J55 Rebuild

**Date:** 2026-09-28
**Branch:** `feature/ratio2-j55-rebuild`
**Source base:** `d826cbdc48803b7a219276ae494512fbb5399299`
**Vivado:** 2026.1, SW Build 6511674
**Target part:** `xczu9eg-ffvb1156-2-e`

## Purpose

This build produces a new, traceable AXI Quad SPI image for the ZCU102 without
overwriting any historical repository bitstream. It addresses the historical
external-loopback blocker by ensuring the repository J55 XDC participates in a
fresh implementation and by inserting an ILA probe on the internal SPI SCK net.

The design uses the existing `hardware/spi_bm_bd_2025p1.tcl` block design,
with only the AXI Quad SPI divider overridden for this build:

- PL0 design target: 100 MHz
- `C_SCK_RATIO = 2`
- Nominal/design-intent SCK: 50 MHz
- AXI Quad SPI register base: `0xA0000000`

**50 MHz is design intent only until measured on the board.**
## Implemented J55 Constraints

Vivado accepted and implemented the AXI SPI package-pin constraints:

| Signal | Package pin | I/O standard |
|---|---|---|
| SCK | F11 | LVCMOS18 |
| MOSI / IO0 | D12 | LVCMOS18 |
| MISO / IO1 | E10 | LVCMOS18 |
| SS0 | D11 | LVCMOS18 |

The implemented I/O report identifies these package pins in device banks 49/50.
Older XDC comments calling these package pins "Bank 28" were therefore corrected
as documentation only; the package-pin constraints themselves were not changed.

## ILA

The original XDC created `u_ila_0/probe0` without connecting it, causing:

`Chipscope 16-213: debug port u_ila_0/probe0 has 1 unconnected channels`.

A first attempt to probe top-level `SPI_0_sck_o` was rejected because that net
is between the I/O buffer and an IOB flip-flop. The final probe uses the internal
ratio-2 serial-clock net before the IOB:

`spi_benchmark_i/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/LOGIC_FOR_MD_0_GEN.SPI_MODULE_I/sck_o_int`
The AXI Quad SPI synthesis checkpoint proves that `sck_o_int` is driven by
`RATIO_OF_2_GENERATE.sck_o_int_reg/Q`.

Final debug mapping:

- ILA clock: PL0 / `clk_pl_0` at 100 MHz
- probe0: internal AXI SPI SCK (`sck_o_int`)
- probe1: AXI SPI MOSI (`SPI_0_io0_o`)
- matching probes file: `spi_ratio2_j55_wrapper.ltx`

## Implementation Result

- synthesis: PASS
- `opt_design`: PASS, 0 critical warnings, 0 errors
- `place_design`: PASS, 0 critical warnings, 0 errors
- `route_design`: PASS, 0 critical warnings, 0 errors
- bitstream generation: PASS
- routed nets: 4,870 / 4,870 fully routed
- routing errors: 0
- final WNS: +4.256 ns
- final TNS: 0.000 ns
- final WHS: +0.010 ns
- final THS: 0.000 ns
- Vivado verdict: all user-specified timing constraints are met

The AXI Quad SPI OOC synthesis emitted a warning that its 20 ns OOC clock period
differs from the design's 10 ns clock period. Final implementation timing is the
signoff evidence for this build and passes at the implemented design level.
## Artifacts

- `spi_ratio2_j55_wrapper.bit` — raw Vivado bitstream / JTAG programming
- `spi_ratio2_j55_wrapper.bit.bin` — FPGA-manager load image
- `spi_ratio2_j55_wrapper.ltx` — matching ILA debug probes
- `spi_ratio2_j55_wrapper.xsa` — hardware platform including bitstream
- `timing_summary_impl.txt` — final routed timing report
- `utilization_impl.txt` — implemented utilization
- `io_impl.txt` — implemented package-pin report
- `route_status_impl.txt` — final route status
- `hashes.txt` — SHA-256 and MD5 manifest

## Evidence Boundary

This build proves that Vivado 2026.1 can implement the ratio-2 AXI Quad SPI
design on `xczu9eg-ffvb1156-2-e`, with the specified package-pin constraints
and internal SCK/MOSI ILA probes, while meeting static timing.

It does **not** yet prove:

- that J55 electrically toggles on the physical ZCU102,
- that physical SCK is exactly 50 MHz,
- that external MOSI-to-MISO loopback passes,
- or the SPI corruption threshold.

Those claims require deployment to the board and direct measurement/testing.
