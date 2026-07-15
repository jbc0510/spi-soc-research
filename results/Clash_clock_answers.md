# Answers for Dr. Clash — SPI Benchmark Numbers & Clock Configuration

## Q1: What numbers am I receiving?

AXI Quad SPI, internal loopback, median of 1000 trials per size:

| Payload | Median latency | Throughput |
|---|---|---|
| 256 B | 207 us | 9.9 Mbps |
| 1 KB | 773 us | 10.6 Mbps |
| 4 KB | 3.03 ms | 10.8 Mbps |
| 64 KB | 48.2 ms | 10.9 Mbps |
| 1 MB | 771 ms | 10.9 Mbps |
| 4 MB | 3.08 s | 10.9 Mbps (max payload; ceiling is spidev bufsiz, not hardware) |

- Headline: AXI path is **14.2x faster** than the PS SPI (Linux cadence_spi) path
  at payloads >= 4 KB.
- Throughput plateaus at **~10.9 Mbps**.
- Open issue: 10.9 Mbps implies an effective SCK near **11 MHz**, which the clock
  configuration (below) does NOT predict (it predicts 6.25 MHz). This is the
  discrepancy the planned on-chip ILA measurement will resolve.

## Q2: What is the IOPLL and SPI clock set to in Vivado?

Clock chain: PS_REF_CLK -> IOPLL (VCO) -> PL0 fabric clock -> AXI SPI divider -> SCK

Confirmed values:
- **PS_REF_CLK** = 33.33 MHz (board oscillator, Si5341B)
- **IOPLL VCO** ~ 1000 MHz (standard ZynqMP operating point; confirmed: PL0_actual
  15.871 x DIVISOR0 63 = 999.9 MHz)
- **PL0 = IOPLL VCO / DIVISOR0**
- **SCK = PL0 / C_SCK_RATIO**, with C_SCK_RATIO = 16

Two builds exist:

| Build | PL0 DIVISOR0 | PL0 freq | C_SCK_RATIO | Nominal SCK |
|---|---|---|---|---|
| Benchmark build (the 14.2x data) | 10 | 99.99 MHz | 16 | **6.25 MHz** |
| 1 MHz clock-matched build (later) | 63 | 15.87 MHz | 16 | **0.99 MHz** |

(The benchmark build's PL0=100 MHz is git-confirmed in the block-design Tcl,
commits cb53535 and 77cd6e9. The 1 MHz build is the current live project.)

## The one open item

> **RESOLVED (2026-07-15):** SCK = **6.25 MHz**, confirmed by PL0_actual 99.99 MHz
> (block-design Tcl) × AXI SPI ratio 16 (ILA capture). The implied ~11 MHz was a
> **2N full-duplex byte-accounting artifact** (counting tx+rx = 2×len instead of
> len), now fixed in `results/spi_benchmark_clean.c` (header comment, fix #2). The
> throughput table above is left unchanged; only the implied-SCK interpretation of
> it was the artifact. See `results/CLOCK_DISCREPANCY_FINDINGS.md` resolution banner.

The configuration gives a nominal SCK of **6.25 MHz** for the benchmark build, but
the measured throughput (~10.9 Mbps) implies ~11 MHz, which is faster than 6.25 MHz
single-lane SPI physically allows. No valid C_SCK_RATIO at PL0=100 MHz produces
11 MHz, so the config cannot explain it. Leading hypothesis: the benchmark's timed
region does not capture the full on-wire transfer duration, inflating the implied
rate. **Planned resolution: on-chip ILA capture of the SCK net** (avoids the J55 pin
routing issues; needs an ILA core inserted + resynthesis, no external probe).
