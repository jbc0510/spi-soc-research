# Linux Jitter Provenance — Published Claim, Falsification, Root Cause

**Status:** the Linux jitter figures published in the July 2026 MSR are
CORRECTED. This document is the full chain of evidence. It is self-contained;
you do not need to read the git log.

**Date of correction:** 2026-08-10
**Commits:** 0dc3d8f (retraction), 5429d33 (harness), ae5af5b (resume doc)

---

## 1. The claim as published

The July 2026 MSR reported, as a completed progress item:

- Linux SPI jitter of **1.2–3.6 µs** across the payload range
- Bare-metal jitter of **sub-0.5 µs**
- A **3× to 140× determinism advantage** for bare-metal, described as
  supported by measured data on both sides

The Linux figures were attributed to the PS EMIO and PS MIO paths, and were
carried in `results/emio_results.csv` and `results/mio_results.csv`.

---

## 2. What falsified it

All three lines of evidence are arithmetic on the committed CSVs. No new
measurement was required.

**(a) Throughput saturation differs by a factor of 14.**

At large payloads, wire time dominates and software overhead is negligible,
so the saturating throughput is a direct read on the serial clock:

| file | saturating throughput | implied clock |
|---|---|---|
| `emio_internal_results.csv` (jitter donor) | 10.88 Mbps | ≈ PL0/16 = 15.6 MHz |
| `emio_results.csv` (latency host) | 0.78 Mbps | 0.9766 MHz (PS rate) |

**(b) The latency ratio is FLAT across payload size.**

| payload | donor avg | host avg | ratio |
|---|---|---|---|
| 4,096 B | 3,026.9 µs | 42,137.2 µs | 13.92× |
| 16,384 B | 12,059.6 µs | 168,371.9 µs | 13.96× |
| 65,536 B | 48,185.9 µs | 673,310.4 µs | 13.97× |

A ratio that stays constant as payload grows is a **clock ratio**. Software
overhead would shrink as a fraction of a larger payload; it does not hold
flat. This is the same signature as the round-4 "14.2× AXI speedup" artifact
already documented in `results/CLOCK_DISCREPANCY_FINDINGS.md`.

**(c) The donor file matches the AXI file, not the PS files.**

`emio_internal_results.csv` agrees with `axi_results.csv` to within 2% at
every payload ≥ 256 B (256 B: 202.73 vs 203.41; 65,536 B: 48,185.95 vs
47,281.82). Same controller, same clock.

**Conclusion:** the file labeled `emio_internal_results.csv` is a capture of
the **Linux AXI Quad SPI path at PL0/16**, not a PS path. Its stddev column
was copied into two PS baseline files across a 14× clock difference. Jitter
expressed in absolute microseconds does not transfer between clock domains,
so the grafted values described neither path.
---

## 3. Root cause — three layers, all independent

**Layer 1: a filename asserted a controller.**
`linux/src/spi_benchmark_jitter.c` hardcoded its output path to
`emio_internal_results.csv` and its device to `/dev/spidev0.0`. Nothing in
the code verified which controller that node mapped to. Every downstream
artifact — the commit message, the graft, the MSR, the paper draft —
inherited the word "EMIO" from a string literal.

**Layer 2: the driver accepts and ignores speed requests.**
The harness requested 1 MHz via `SPI_IOC_WR_MAX_SPEED_HZ`. The `xilinx_spi`
driver acknowledges such requests and ignores them, because the AXI Quad SPI
serial rate is `C_SCK_RATIO = 16` fixed at synthesis. This behaviour was
already documented in the project's own SPI controller references as "a
subtle trap." It caught this capture too.

**Layer 3: the harness printed its request as if it were a measurement.**
The code set `spd = SPI_SPEED_HZ` and then printed `"Speed: %d Hz"` from the
same constant — never reading back, never deriving the achieved rate. That
printed line is the origin of "SCK: 1 MHz" in commit 86bd14c, recorded while
the wire ran at roughly 15.6 MHz.

Note also that 86bd14c states the capture used `/dev/spidev1.0` while the
source opens `/dev/spidev0.0`. Whichever node was used, measured throughput
proves it reached the AXI controller.

---

## 4. Plan versus execution

The process was not missing. `linux/JITTER_CAPTURE_RESUME.md`, written before
the capture, contains at step 4:

> verify which node is EMIO (SPI1). Harness has spidev0.0; EMIO is likely
> spidev1.0. If so, edit SPI_DEVICE, recompile, re-copy.

It says **likely**. It calls for verification and a recompile. Neither was
done, and no one re-read the source before writing the commit message.

The same document also recorded the decision to write a NEW file and "do NOT
overwrite the original external-loopback averages." Commit e3aaeca then
copied the donor stddev into both PS baseline files anyway.

**The failure was a skipped verification under the momentum of a working
boot, not an absent procedure.**

---

## 5. Why the integrity check passed

`compare_spi.py` tested for a **flat** stddev column — the flat 1.0 µs
sentinel. The grafted values were not flat, so the check reported "No
integrity flags raised." Its near-identical-file check, which would have
caught the 2% agreement with `axi_results.csv`, compared only the four
tracked interface files; the donor was not among them.

"Zero flags" meant the sentinel was gone. It did not mean the data was sound.

---

## 6. Corrected state of Linux jitter

| path | status |
|---|---|
| Linux AXI Quad SPI | **MEASURED** — three captures at this clock: 10.880 / 10.884 / 11.093 Mbps @ 65536 B (`axi_internal_results.csv`, `mio_internal_results.csv` (§8), `axi_results.csv`). The first two agree to 0.04% but may be one configuration measured twice (§8) — treat the third as the independent check. Valid result. |
| Linux PS EMIO / MIO | **NEVER MEASURED.** Not-measured sentinel restored in both files. |
| Bare-metal PS SPI1 | **MEASURED**, sub-0.5 µs. Unaffected by any of this. |

Linux PS SPI1 jitter is **structurally unobtainable**. The ATF/TrustZone
configuration denies APU access to Node 36 / domain12; six independent fix
attempts all returned `-EACCES`. That column can never be filled from the
Linux side. It is a finding for the determinism objective, not a gap.

---

## 7. What changed so this cannot recur

- Device is `argv[1]`; the CSV path is **derived** from it. No filename
  asserts a controller.
- Speed and mode are **requested then read back**, with an explicit marker
  printed when readback differs from request.
- The CSV carries a provenance header: device, requested Hz, readback Hz,
  mode readback, achieved Mbps, and a line stating the file does not assert
  which controller was measured.
- **Achieved Mbps is computed from measured wire time** and warned on when it
  exceeds the request by more than 1.5×. A driver can echo back a request;
  it cannot fake elapsed time. Had this existed on 2026-07-08, the
  mislabeling would have been caught the same day.
- `compare_spi.py`'s sentinel flag now names the ATF wall as the reason and
  explicitly warns against copying stddev from another path.

**Generalized rule:** the project already required hardware register readback
before trusting design-time assumptions. That rule had been applied to the
bare-metal harness, which forces `SPI1_REF_CTRL` and re-reads to verify, but
never to the Linux harness, which requested and trusted. That asymmetry was
the bug.

---

## 8. Second unretracted twin — `mio_internal_results.csv`

Commit `1f5348e` added `results/mio_internal_results.csv` described as a
"second PS Cadence jitter capture". The arithmetic does not support that
label. Slope fitted 4096 -> 65536 B:

| File | slope (us/B) | Mbps @ 65536 B |
| --- | --- | --- |
| `axi_internal_results.csv` (proven AXI, sec. 2) | 0.735011 | 10.880 |
| `mio_internal_results.csv` | 0.734713 | 10.884 |
| `mio_results.csv` (PS-labelled) | 10.2734 | 0.7787 |

`mio_internal` tracks the proven-AXI file to **0.04%** at every one of the
eleven payloads, and diverges from the PS-labelled file of near-identical
name by **13.98x**.

**Ceiling argument.** PS SCK is 0.9766 MHz, so a PS capture cannot exceed
0.9766 Mbps of payload throughput. This file shows 10.884 Mbps. It is
therefore NOT the PS controller at the documented prescale, and the commit
message asserting "PS Cadence" is wrong.

**NOT CLAIMED: that this file is the AXI controller.** PS SPI at prescale /4
is 62.5/4 = 15.625 MHz, numerically identical to PL0/16. Timing alone cannot
separate the two. The file predates the v2 provenance header and carries no
`# device=` line, so controller identity is not recoverable from it -- the
same status as the emio/mio pair in section 6.

**Inference, flagged as inference.** Section 3 records that the retired
harness hardcoded both its output filename and `/dev/spidev0.0`. If this
capture came from that binary -- same day, 84 minutes after the file now
named `axi_internal_results.csv` -- it reached the same node and is the same
path. Plausible; not proven. No waveform, no header, no log.

**Disposition.** Contents left byte-for-byte unmodified (md5
`178e9e7e0afcb12cdd6e28c553475fa0`); it is evidence. Renamed in a following
commit so the filename stops asserting a disproven controller, per the
precedent of `0dc3d8f`. It was also a graft donor (`d109780`), retracted by
`0dc3d8f` along with the emio graft.
