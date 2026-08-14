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
