
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
| Linux AXI Quad SPI | **MEASURED** — twice, agreeing within 2%. Retained as `results/axi_internal_results.csv`. Valid result. |
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
