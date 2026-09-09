# 6.25 vs 15.625 MHz — Occurrence Triage
**Date:** 2026-09-09 · **Host:** bxqp8b3-ub22 · **HEAD at start:** 4501706
**Method:** repo-only, read-only. No board, no build.

## Scope correction

The prior record (`docs/session-recaps/SESSION_RECAP_20260820.md:267`,
`docs/sessions/CONTINUATION_MORGAN_20260825.md:108`) states **six files**.
Searching all tracked content finds **sixteen** files containing `6.25` and
**fifteen** containing `15.625`.

    git --no-pager grep -c -E '6\.25'    -- .     43 occurrences, 16 files
    git --no-pager grep -c -E '15\.625'  -- .     24 occurrences, 15 files

Control: per-file counts sum to the totals, so the searches are not returning a
tooling artifact. `15\.625` cannot match `6\.25` as a substring, so the two
counts are independent.

Ten files were outside the documented six, including **README.md** — the
repository's front door. Working the six-file list and stopping would have
closed this item with README uninspected.

## The premise of the item is wrong

The item is recorded as "6.25 is stale, 15.625 is current." There are **four
distinct derivations** in the repo, and two of them are legitimate:

| value | derivation | status |
|---|---|---|
| 6.25 MHz | PL0 100 MHz / C_SCK_RATIO 16 | retracted design intent |
| **6.25 MHz** | **PL0 50 MHz / 8** | **CORRECT — a different, in-spec build** |
| 15.625 MHz | PL0 250 MHz / 16 | established from live CRL_APB registers |
| 15.625 MHz | 62.5 MHz / 4 | numerical coincidence, deliberately flagged |

`results/clock_sweep_inspec/sweep_6.25mhz_inspec.csv:3` reads "True SCK = 50/8 =
6.25 MHz, in-spec." That is not the retracted figure. **Classification by value
is therefore impossible**, and a bulk edit would have corrupted a correct data
file — including its filename, which asserts its operating point and is
referenced by md5 chains.

`results/LINUX_JITTER_PROVENANCE.md:188` records that 62.5/4 also equals 15.625,
"numerically identical to PL0/16. Timing alone cannot [distinguish]." That is a
live caveat on the CURRENT value, not only the retracted one. Retain.

## Regex artifacts — NOT occurrences

Seven of the 43 `6.25` hits are substring matches inside longer decimals. Do not
edit these.

| location | actual text | what it is |
|---|---|---|
| `results/axi_results.csv:11` | `11836.25` | latency, microseconds |
| `results/spi_bench_spidev1.0_20260825_190101.csv:31` | `776.257` | latency, microseconds |
| `docs/sessions/SESSION_20260825_MORGAN.md:384` | `776.257` | pasted CSV row |
| `sd-images/BOOT.BIN` | `15.625 us` | **microseconds, not MHz** |
| `sd-images/BOOT_linux_rebuild.bin` | `15.625 us` | microseconds |
| `sd-images/BOOT_qspi_pmu.bin` | `15.625 us` | microseconds |
| `sd-images/BOOT_vitis_pmu.bin` | `15.625 us` | microseconds |

All four binaries characterized individually with `strings -a`, not inferred from
one another. `sd-images/spi_loopback_test` is the one binary carrying a **genuine**
embedded literal (`ext_spi_clk/C_SCK_RATIO = 6.25 MHz`), identical to
`results/spi_benchmark_clean.c:115` — it is a compiled artifact of that defect,
not an independent one.

## Classification

### Already corrected — the model to copy

`README.md:20`. States the corrected value, shows the arithmetic, names the
retracted assumption it replaced, cross-references the section it used to
contradict, AND adds that 15.625 MHz is *derived* from registers rather than
observed on the wire. No action.

### Historical and self-labelled — leave alone

| file | occ | why it is fine |
|---|---|---|
| `results/CLOCK_DISCREPANCY_FINDINGS.md` | 12 | retraction banner at line 18 precedes every occurrence |
| `results/Clash_clock_answers.md` | 5 | line 47 states the design-time 6.25 never ran on silicon |
| `docs/session-recaps/SESSION_RECAP_20260820.md` | 7 | correct as written; records the correction itself |
| `docs/sessions/CONTINUATION_*.md`, `SESSION_20260825_MORGAN.md` | 8 | session records; correct in context |
| `results/CROSSBOOT_REPRO_20260827.md` | 3 | uses 15.625 correctly, from register readback |
| `results/clock_sweep/sweep_1mhz_matched.csv`, `sweep_control_restore.csv` | 2 | explicitly say "NOT 6.25" |
| `results/clock_sweep_inspec/sweep_6.25mhz_inspec.csv` | 1 | correct, different build (50/8) |
| `results/LINUX_JITTER_PROVENANCE.md:188` | 1 | correct and valuable; retain |

### CURRENT AND WRONG — needs correction

**`results/PAYLOAD_CEILING_FINDINGS.md`** — lines 5, 31, 116. Highest priority.
The Platform header asserts "@ 6.25 MHz (C_SCK_RATIO=16, 100 MHz fabric clock)"
as plain fact with no retraction anywhere in the file, and line 31 draws a
conclusion from it. **The file refutes itself:** line 31 calls ~10.9 Mbps
"consistent with the 6.25 MHz native SCK", but single-lane standard SPI carries
one bit per clock, so 6.25 MHz caps throughput at 6.25 Mbps. 10.9 > 6.25.
`results/CLOCK_DISCREPANCY_FINDINGS.md:41-42` already caught exactly this
("faster than 6.25 MHz allows ... implied SCK is stable at ~11 MHz"). At
15.625 MHz, 10.9 Mbps is ~70% wire efficiency, which is plausible.

**`results/spi_benchmark_clean.c`** — lines 11 and 115. Line 115 is inside an
`fprintf(stderr, ...)`, so the program **prints a false SCK at runtime**.
Correction to an earlier reading of this defect: it is on stderr, and the CSV
header is a separate `printf` to stdout, so it does NOT enter the CSV unless the
streams are merged (`2>&1`). No CSV in the repo carries it. Real defect, but not
a data-integrity vector. `sd-images/spi_loopback_test` embeds the same string.

**`docs/notes/block_design_review.md`** — lines 36, 40, 115. Asserts
100/16 = 6.25 and says "Resolve before publication: either confirm the AXI ...".
It has been resolved by live register read. Needs a superseding banner, not
deletion — the design-intent record is worth keeping.

**`results/ILA_SCK_MEASUREMENT_PLAN.md`** — 6 occurrences. A plan to settle
"6.25 (config) vs ~11 MHz (timing-implied)". The register read answered the
question a different way. Mark superseded; do not delete.

### Clarity defect, not a factual conflict

`results/compare_spi.py:7` reads: the previous version's synthetic fallback "is
the origin of the bogus '15.625 MHz' curve". In context (lines 5-8) the curve was
bogus because it was **synthetic sample_*() data**, not because 15.625 is the
wrong frequency. Line 185 asserting AXI SCK = 15.625 MHz is consistent. A reader
will nonetheless misparse "bogus 15.625 MHz" as impeaching the value. Reword.

### Error introduced this session

`results/SESSION_RECAP_20260909.md:141` says the triage spans "six files",
repeating the prior record's scope claim without verifying it. Committed in
`4501706`. Corrected by this note; the recap line should be amended when that
file is next touched.

## ESCALATIONS — outrank the documentation cleanup

### E-1. The retraction mechanism and the benchmark build disagree

`results/Clash_clock_answers.md:38` records the 14.2x benchmark build as
PL0 divisor 10 -> 99.99 MHz -> SCK 6.25 MHz. The August MSR explains the 14.24x
retraction as a **16.0x clock artifact**, which requires PL0 = 250 MHz
(15.625 / 0.9766 = 16.0). At PL0 = 100 MHz the ratio would be ~6.4x, and 14.24x
could not be a clock artifact at all.

Both cannot be true of the same dataset. Either the 14.2x capture came from a
PL0 = 250 build and line 38 is wrong, or it came from a PL0 = 100 build and the
16.0x mechanism does not explain it.

**NOT RESOLVED HERE.** Resolving it requires the bitstream/build provenance of
the 14.2x capture, which was not examined. This bears on a claim already
delivered to the sponsor and should not sit in a documentation backlog.

### E-2. Does an ILA SCK capture exist or not

`results/CLOCK_DISCREPANCY_FINDINGS.md:120` records an "ILA verdict (Jun 3):
SCK = 16 samples @100 MHz = 6.25 MHz exactly."
`docs/sessions/SESSION_20260825_MORGAN.md:567` states "**No SCK measurement.**
15.625 MHz is derived from PL0_REF_CTRL and the [synthesis-frozen ratio]".
`README.md:20` agrees with the latter.

One of these is wrong about whether a hardware SCK measurement was ever taken.
This matters directly: if an ILA capture exists showing 16 samples per SCK
period, it constrains the ratio independently of the register read.

**NOT RESOLVED HERE.**

## Recommended order for the remaining work

1. `results/PAYLOAD_CEILING_FINDINGS.md` — self-refuting, arithmetic airtight
2. E-1 — MSR-relevant, needs build provenance, not a doc edit
3. E-2 — determines whether we have one or two independent lines of evidence
4. `results/spi_benchmark_clean.c` — prints a false value at runtime
5. `docs/notes/block_design_review.md` — superseding banner
6. `results/ILA_SCK_MEASUREMENT_PLAN.md` — superseded banner
7. `results/compare_spi.py:7` — reword
8. `results/SESSION_RECAP_20260909.md:141` — amend the "six files" claim

## DELIBERATELY NOT CLAIMED

- No file was edited in producing this note. Classification only.
- Occurrence counts are from `git grep` over tracked content at HEAD 4501706.
  Untracked files, other branches and git history were not searched.
- The `.bin` characterizations rest on `strings -a`, which finds printable
  sequences. A non-printable or differently-encoded numeric constant would not
  be found by either `grep` or `strings`, and none is claimed absent.
- E-1 and E-2 are stated as contradictions in the record. Neither is resolved,
  and no verdict is offered on which side is correct.
- Whether the ~10.9 Mbps figure in PAYLOAD_CEILING_FINDINGS.md is itself
  reliable was not assessed. Only its inconsistency with a 6.25 MHz SCK is.
- No SCK value in this note was measured on the wire during this session. The
  15.625 MHz figure remains derived from register reads and the
  synthesis-frozen C_SCK_RATIO, per README.md:20.
