# Cross-Boot Reproducibility, ZCU102 #2 — 2026-08-27

Second identity-verified Linux SPI capture on ZCU102 #2, compared against the
first (`4cb2770`, 2026-08-25). MSU-2 Task 2, IAC/TAT P1-22-2393.
Measured at Morgan, `bxqp8b3-ub22`, repo commit `fef743e`.

## THE RESULT

**The capture reproduces across a full power cycle and a fresh PL load.**

Large payloads agree to within a few hundredths of a percent. The two runs are
separated by a power-off, a cold boot, a re-programmed bitstream, a re-applied
device-tree overlay, and two days.

| bytes | 08-25 avg µs | 08-27 avg µs | Δ avg | Δ min |
|---|---|---|---|---|
| 1 | 14.816 | 14.344 | −3.19% | +0.49% |
| 8 | 24.199 | 20.822 | −13.96% | +3.26% |
| 16 | 27.552 | 27.539 | −0.05% | −0.12% |
| 64 | 62.674 | 62.361 | −0.50% | −3.91% |
| 128 | 109.491 | 109.315 | −0.16% | +0.02% |
| 256 | 202.729 | 202.853 | +0.06% | +0.10% |
| 512 | 391.060 | 391.099 | **+0.01%** | −0.02% |
| 1024 | 767.542 | 767.780 | **+0.03%** | −0.03% |
| 4096 | 3026.348 | 3026.911 | **+0.02%** | +0.01% |
| 16384 | 12057.820 | 12059.789 | **+0.02%** | +0.03% |
| 65536 | 48178.186 | 48185.999 | **+0.016%** | +0.010% |

Achieved throughput at 65536 B: **10.88 Mbps on both days.**

### Small payloads move; their floors do not

Payloads below 128 B differ by up to 14% on the average. That is expected and
is not a different operating point: those transfers are dominated by fixed
per-transfer software cost, where scheduling noise is a large fraction of a
short interval.

**The minima barely move** — 8 B min +3.26%, 1 B min +0.49% — so the floor is
stable and the variation is in the tail. The 1 B stddev is 3.867 µs (08-25) and
2.903 µs (08-27), against a mean near 14.5 µs, which is consistent with that
reading.

Payloads at and above 128 B agree within ±0.06%; at and above 512 B, ±0.03%.

## DETERMINISM DATUM

**`nivcsw = 0` and `err_count = 0` on all 11 rows of both captures.**

That is 22,000 timed trials across two boots with **zero involuntary context
switches** and zero failed ioctls.

This is a SOW 2.f-adjacent baseline: the task asks about latency and jitter
under varying kernel settings, and this establishes the default-configuration
starting point. 2.f itself is NOT started, and this is not a substitute for it —
no kernel setting was varied, and a single configuration cannot answer a
question about variation.

The harness header is explicit that `cpu_pct` under-counts true system cost,
because hardirq and softirq time are never charged to the task. Cited so the
CPU column is not over-read.

## IDENTITY, VERIFIED BEFORE THE RUN — THIRD INDEPENDENT BOOT

```
readlink -f /sys/class/spidev/spidev1.0
  /sys/devices/platform/axi/a0000000.axi_quad_spi/spi_master/spi1/spi1.0/spidev/spidev1.0
```

**AXI Quad SPI at 0xA000_0000. NOT PS SPI1.** Established from hardware before
the benchmark was started, as on the two boots recorded in `4cb2770`.

The CSV itself does not assert this — its header carries
`CONTROLLER NOT ASSERTED BY THIS FILE` — so the assertion lives here, with the
sysfs path that supports it.

## MD5 CHAIN — UNBROKEN

```
binary   ff194b3828edc13d06ba26ef816c8616   repo == host == SD == board tmpfs
bitstream 61f2c33f6ce6138eee81a862a466ae4e   card == board /usr/lib/firmware
overlay  sha256 2912ee463b2f60652dd64fc8009d1836e8a5c7824008eb26940a753eeb09dfcd
         2009 bytes, extracted with dumpimage -T flat_dt -p 2; the sha256 is
         the hash the FIT builder recorded inside image.ub, so the index is
         confirmed rather than assumed
capture  fbf53662982ef10d1aaaca45a5d57361   board tmpfs == SD after sync ==
         host card read == repo
```

Four independent reads of the capture, one value.

`/boot/devicetree/pl.dtbo` (2137 bytes) is NOT this overlay and was not used.

## CLOCK CHAIN RE-DERIVED ON THIS BOOT

Not inherited from the 2026-08-20 reading — re-read after the PL was programmed:

```
IOPLL_CTRL     0xFF5E0020  0x00015A00   FBDIV 90  -> 1500 MHz
PL0_REF_CTRL   0xFF5E00C0  0x01010600   DIV 6     -> 250 MHz  -> AXI SCK 15.625 MHz
SPI1_REF_CTRL  0xFF5E0080  0x01001800   DIV 24    -> 62.5 MHz -> PS SCK 0.9766 MHz
```

## HYPOTHESIS — PL0_REF_CTRL BIT 24

`PL0_REF_CTRL` read **`0x00010600`** on 2026-08-20 and **`0x01010600`** today.
Same board, same card, same procedure. One bit apart: bit 24.

The 2026-08-20 record flagged this as an open question and noted bit 24 was
*believed* to be CLKACT but **not verified against UG1085**. That verification
has still not been done.

**Hypothesis:** the 08-20 read was taken on a cold boot with the PL
**unprogrammed**; today's was taken **after** the bitstream was loaded and the
overlay applied. If bit 24 is the clock-enable, PL0's output is gated off until
something requires it, and programming the PL enables it. Both readings would
then be correct for their moment.

**This is an inference from two data points on different days. It is NOT
established.**

Two things would settle it, neither done:

1. Verify the bit-24 assignment in UG1085.
2. On a future boot, read `PL0_REF_CTRL` **before** programming the PL and
   again after. If it goes `0x00010600` -> `0x01010600`, the hypothesis holds.

**DIVISOR0 = 6 in both readings**, so 250 MHz and the 15.625 MHz AXI SCK stand
regardless of how bit 24 resolves.

## NEW OBSERVATION — KERNEL MESSAGE NOT PRESENT ON 08-25

```
[  269.271242] spidev spi1.0: setup: unsupported mode bits 20
```

Emitted when the harness attempts `SPI_LOOP` (bit 0x20). The harness already
handles this — it prints `warning: could not set SPI_LOOP (continuing)` and
records `spi_loop=0` in the header — but the kernel-side message does not
appear in the 08-25 log. Recorded, not investigated. Harmless: loopback on this
path must be established in hardware, not by ioctl.

## THE HARNESS FLAGS ITS OWN SPEED CAVEAT

Worth quoting because it is the frozen-divider behaviour, self-reported:

```
WARNING: achieved rate FAR EXCEEDS request -- the driver ignored
         the speed request. Do NOT label this capture with the
         requested rate.
```

Requested 1 MHz; readback 1 MHz; achieved 10.88 Mbps on a 15.625 MHz SCK. The
`xilinx_spi` driver acknowledges a speed request and ignores it, because
`C_SCK_RATIO = 16` is frozen at synthesis. Changing the actual serial clock
requires loading a different bitstream — `spi_benchmark_{1,12,25,50}mhz.bit.bin`
exist for that and were NOT used here.

## SESSION PROCEDURE NOTE

The board clock was set as the **first** action after login, per the standing
rule from `fef743e`:

```
date -u -s "2026-08-27 12:52:00"
hwclock -w -u
```

Verified by readback at both layers before proceeding. Without it the capture
filename and `capture_utc` header would have read 2025-01-08. The RTC does not
persist across a power cycle; this is mandatory every session.

## DELIBERATELY NOT CLAIMED

- That 2.f is started. It is not. One configuration is not a variation study.
- That the bit-24 hypothesis is established. See above.
- That the small-payload variation has been characterised. It was observed and
  a reading offered; no further trials were run.
- That anything was measured about PS SPI1. It remains unreachable from Linux.
- That the achieved rate reflects the requested rate. It does not.
- That the `unsupported mode bits 20` message has been investigated.

## SOW POSITION

SOW 2.e was moved from WRITTEN to EXECUTED by `4cb2770`. This capture does not
advance it further; it **corroborates** it, which is the point of a second run.

2.f remains NOT STARTED. 2.g remains DESIGN LOST and NOT IMPLEMENTED.
