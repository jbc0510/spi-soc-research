# Serial-Clock Discrepancy — Root-Cause Lead from UG1182

**Project:** MSU-2 (ZCU102 SPI Benchmark) · Contract FA-8075-18-D-0004
**Date:** 2026-06-03
**Status:** Strong hypothesis, pending design-config confirmation / direct measurement
**Author:** J. Conway

## The discrepancy

Two sources disagree on the AXI Quad SPI serial clock (SCK):

| Source | Implied SCK | Basis |
|---|---|---|
| IP configuration readout | 6.25 MHz | `C_SCK_RATIO`=16, assuming `ext_spi_clk` = 100 MHz |
| Measured transfer timing | ~11 MHz | Back-calculated from on-hardware latency |

The timing-implied value is **physically incompatible** with 6.25 MHz: a 4 KB
single-lane transfer needs at least `4096 x 8 / f_SCK` of bit-shift time. At
6.25 MHz that floor is 5,243 us, but the measured time is **2,974 us** — faster
than 6.25 MHz allows. The implied SCK is stable at ~11 MHz across large payloads
(10.1 MHz at 256 B rising to 11.1 MHz at 64 KB as fixed overhead amortizes).

## The lead from UG1182 (ZCU102 board user guide)

The board's clock sources (UG1182, Table 3-12 "ZCU102 Board Clock Sources")
show there is **no 100 MHz oscillator feeding the PL fabric**:

- `PS_REF_CLK` = **33.33 MHz** (Si5341B clock generator, U69) — the PS reference.
- Fixed clocks: CLK_74_25 (74.25 MHz), CLK_125 (125 MHz), and GTR reference
  clocks (100 MHz PCIe, 125 SATA, 26 USB3, 27 DP) — the 100 MHz here feeds the
  **GTR transceivers**, not the general PL fabric.
- `USER_SI570` = **300 MHz** default (programmable, U42) — the user clock to PL.

The "100 MHz fabric clock" assumed for the AXI SPI design is therefore **not a
board oscillator**. On Zynq UltraScale+, the PL fabric clock (`pl_clk0`) is
generated *inside the PS* by a PLL from the 33.33 MHz `PS_REF_CLK`, and routed to
the PL. Its frequency is set by the PS clock configuration in the design, not by
any fixed board source.

## Why this explains the data

If the real `pl_clk0` is not 100 MHz but higher, the divisor (÷16) yields a
higher SCK:

| Assumed `pl_clk0` | SCK (÷16) | 4 KB bit-shift floor | vs. measured 2,974 us |
|---|---|---|---|
| 100 MHz (assumed) | 6.25 MHz | 5,243 us | impossible (measured is faster) |
| **~176 MHz** | **~11 MHz** | **~2,979 us** | **consistent** |

A `pl_clk0` of ~176 MHz (≈ 5.28 x the 33.33 MHz reference, a plausible PS PLL
output) divided by C_SCK_RATIO=16 gives ~11 MHz SCK, whose 4 KB floor (~2,979 us)
matches the measured 2,974 us almost exactly.

**Working conclusion:** the IP divisor (÷16) is most likely correct; the *input*
clock to it was mis-assumed. The discrepancy is not a measurement artifact or a
FIFO effect — the fabric clock is simply not 100 MHz. The ~11 MHz timing-implied
SCK has been consistent with the data all along.

## What confirms it (do this before updating the paper)

The 176 MHz figure is back-calculated from timing; it is the value that *would*
explain the data, not yet a confirmed design fact. Confirm by either:

1. **Read `pl_clk0` from the Vivado design (fastest, no hardware).** Open the
   block design → Zynq UltraScale+ PS → Clock Configuration → Output Clocks →
   PL Fabric Clocks → `PL0` frequency. Whatever that reads is the true
   `ext_spi_clk` into the AXI SPI ratio divider. Cross-check against the
   constraints/clock report (`report_clocks`).
2. **Measure SCK directly (gold standard).** Logic-analyzer or on-chip ILA
   capture of the SCK line during a transfer.

Either resolves 6.25 vs. 11 MHz definitively.

## Downstream items gated on this

- **Paper §V.D (Serial-Clock Discrepancy):** currently flags this as unresolved.
  Once `pl_clk0` is confirmed, restate with the real fabric clock and SCK; the
  14.2x decomposition becomes legitimate using the *correct* clock ratio (likely
  ~11x, not 6.25x — meaning the residual driver-path component would be ~1.3x,
  not 2.3x; recompute once the clock is fixed).
- **`spi_benchmark_clean.c` header comment:** states "real SCK is fixed at
  ext_spi_clk/C_SCK_RATIO = 6.25 MHz" — based on the 100 MHz assumption. Correct
  once `pl_clk0` is confirmed.
- **Clock-max experiment:** the ratio sweep math depends on the true `pl_clk0`.
  If `pl_clk0` ≈ 176 MHz, then ratio 16 already gives ~11 MHz, and PG153's
  `ext_spi_clk` ≤ 100 MHz constraint may already be exceeded — which itself needs
  checking. Confirm `pl_clk0` before planning the sweep.

## One-line summary

The board has no 100 MHz PL oscillator (UG1182): `pl_clk0` is PS-synthesized from
33.33 MHz `PS_REF_CLK`. The measured ~11 MHz SCK is consistent with a real
`pl_clk0` of ~176 MHz ÷ 16, not the assumed 100 MHz ÷ 16 = 6.25 MHz. Confirm the
actual `pl_clk0` in the Vivado PS clock config (or by ILA) to close the issue.
