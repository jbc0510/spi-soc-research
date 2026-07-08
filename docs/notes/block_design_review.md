# ZCU102 SPI Benchmark — Block Design Review

**Project:** MSU-2 (spi-soc-research) · **Source:** `spi_benchmark_wrapper.xsa`
**Reviewed:** 2026-05-28 · **Method:** XSA `.hwh` inspection (no editable BD on stile)
**Part:** xczu9eg-ffvb1156-2-e (Zynq UltraScale+ MPSoC)

---

## Summary

The bitstream carries **two PL-side SPI paths in a single design**: the AXI Quad SPI
(PL hardware path) and PS SPI1 routed out through EMIO. This is consistent with the
three-interface benchmark (MIO is pure PS and needs no PL; EMIO and AXI both surface here).

The headline Phase 6 result — AXI Quad SPI 14.2× faster than the PS SPI software stack at
large payloads — holds, with one interpretation caveat noted below regarding SCK rate.

---

## AXI Quad SPI configuration

| Item | Value | Notes |
|---|---|---|
| IP | `axi_quad_spi` v3.2, instance `axi_quad_spi_0` | |
| SPI mode | Standard (mode 0), single-bit | `C_SPI_MODE=0` — not dual/quad |
| FIFO depth | 256 bytes, TX & RX | `C_FIFO_DEPTH=256` |
| Transfer width | 8-bit | `C_NUM_TRANSFER_BITS=8` |
| Slave selects | 1 | `C_NUM_SS_BITS=1` |
| SCK ratio | ÷16 | `C_SCK_RATIO=16` (hardware-fixed) |
| AXI interface | AXI4-Lite, 32-bit | `C_TYPE_OF_AXI4_INTERFACE=0`, `C_S_AXI_DATA_WIDTH=32` |
| Internal loopback | Available via control register | TX→RX internal wrap, standard mode only |

## Clocking

- `s_axi_aclk` and `ext_spi_clk` both driven by `pl_clk0` at **99,990,005 Hz (~100 MHz)**.
- With `C_SCK_RATIO=16`: **SCK = 100 MHz ÷ 16 = 6.25 MHz**.
- **Caveat:** This is *not* 1 MHz. The PS controllers (MIO/EMIO) have programmable baud
  dividers and genuinely run at the spidev-requested 1 MHz. The AXI Quad SPI's ÷16 is a
  build-time fixed divider; unless the path is clocked down elsewhere, the AXI benchmark
  runs at 6.25 MHz on the wire. **Resolve before publication:** either confirm the AXI
  path is actually at 1 MHz, or report true per-interface SCK rates and frame the
  comparison as "each at its configured rate." A reviewer will catch a clock mismatch.

## Address map

| Field | Value |
|---|---|
| Base | `0xA0000000` |
| High | `0xA000FFFF` (4 KB register aperture used) |
| Master | PS `zynq_ultra_ps_e_0` via `M_AXI_HPM0_FPD` |
| Segment | `SEG_axi_quad_spi_0_Reg` |
| Interface | AXI4-Lite (`AXI_LITE`) |

Confirm this base matches the PL device-tree overlay and the `spi_benchmark_axi_ext` binary.

## Interconnect

Single-master / single-slave **SmartConnect** (`smartconnect_0`):
`PS M_AXI_HPM0_FPD (maxigp0)` → SmartConnect → AXI Quad SPI AXI4-Lite slave @ `0xA0000000`.

## Interrupt routing

- `axi_quad_spi_0.ip2intc_irpt` (EDGE_RISING) → `zynq_ultra_ps_e_0.pl_ps_irq0`.
- `PSU__USE__IRQ0 = 1` (enabled). No concat needed (single source).
- The AXI Quad SPI driver is therefore **interrupt-driven** (not polled). The hardware path
  wins 14.2× *despite* carrying ISR overhead — worth one sentence in the paper.

## SPI signal mapping (for loopback)

Standard-mode mapping of the Quad SPI IO lines:

| Signal | Port | Role |
|---|---|---|
| MOSI | `SPI_0_io0` (`io0_o` out) | controller output |
| MISO | `SPI_0_io1` (`io1_i` in) | controller input |
| SCK | `SPI_0_sck` | clock |
| SS | `SPI_0_ss` (1 bit) | slave select |

Each is a 3-state set (`_i`/`_o`/`_t`) since the IP can be master or slave.
**External loopback jumper:** connect the physical pin carrying `io0_o` (MOSI) to the
physical pin carrying `io1_i` (MISO).

EMIO path also present: `emio_spi1_sclk_i`, `emio_spi1_mosi_i` (PS SPI1 → EMIO → PL).

## Gap: physical pin LOCs

**The XSA contains no XDC** — package-pin assignments are not recoverable from stile.
The constraints file lives only in the original Vivado project on the Morgan State
workstation (`~/zcu102_spi_benchmark/vivado/zcu102_spi_bm/zcu102_spi_bm.xpr`).
The MOSI/MISO/SCK/SS physical header pins must be read from that XDC before the jumper test.

---

## Implications for Objective 2 (>64KB stress testing)

1. **FIFO is not the first wall.** At 256 B, the driver chunks large transfers (fill → drain →
   refill). FIFO depth does not bound transfer size directly.
2. **spidev `bufsiz` is the likely first failure at exactly 65536.** The kernel was built with
   `spidev.bufsiz=65536`; a single transfer >64 KB will be rejected/truncated by spidev — a
   *software* limit, not hardware. To exceed it, raise `spidev.bufsiz` or split transfers.
3. **Run both loopback modes to localize failures:**
   - *Internal* (control-register loopback bit): tests AXI/FIFO/driver datapath, **no pins
     needed** — can run the moment the board boots, before sourcing pin LOCs.
   - *External* (physical MOSI↔MISO jumper): adds the PL I/O buffers and physical layer.
   - Corruption in external-only → physical/IO layer. Corruption in both → datapath/driver.

---

## Action items (Morgan State workstation)

1. Read the XDC for physical pin LOCs of `SPI_0_io0` (MOSI) and `SPI_0_io1` (MISO).
2. Export the block design as PDF for the paper figure.
3. Run `write_bd_tcl -force ./hardware/tcl/spi_bm_bd.tcl` and commit — makes the BD
   reproducible from git (the root cause of why the canvas was unrecoverable on stile).
4. Resolve the AXI SCK rate question (6.25 MHz fixed vs. 1 MHz requested).
