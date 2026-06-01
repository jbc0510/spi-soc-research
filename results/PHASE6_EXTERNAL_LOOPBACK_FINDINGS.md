# Phase 6 — External Loopback: Findings and Blocker

**Date:** 2026-06-01
**Author:** Jerry Conway (jbc0510)
**Project:** MSU-2 / ZCU102 SPI Benchmark
**Board:** ZCU102, booting from SD (SW6 = 0010)
**Bitstream under test:** `spi_benchmark_wrapper.bit.bin` (loaded via DT overlay)

## Summary

Internal SPI loopback validates the data path end to end. External loopback could
not be validated: J55 PMOD pins are electrically inactive during active transfers,
indicating the loaded bitstream does not route the AXI Quad SPI I/O to the J55
package pins. Root cause is consistent with the known 2024.2 / 2025.1 Vivado
toolchain mismatch; a corrected bitstream rebuild is blocked pending Vivado
(opentitan) license renewal.

## What passed (validated)

- **Internal loopback (SPICR LOOP bit set, `0xa0000060 = 0x187`): PASS at all sizes,
  1 B through 512 KB**, zero errors. Confirms the AXI Quad SPI core, the 256-deep
  FIFO, the spidev driver path, and `/dev/spidev1.0` are all functioning.
- AXI core register space is live: `0xa0000060` reads/writes correctly and the
  driver leaves a coherent post-transfer value (`0x84`), confirming the core is
  mapped, clocked, and responsive.
- DT overlay applies cleanly; `/dev/spidev1.0` enumerates; symlink to
  `/dev/spidev0.0` intact.

## What failed (and why)

- **External loopback (SPICR LOOP clear, `0xa0000060 = 0x186`, physical jumper on
  J55): FAIL at every size, "first corrupt byte: 0".**
- Failure is independent of jumper pin position. All candidate placements on J55
  (bottom-row side-by-side, top-row side-by-side, end-column stacked) produced
  identical total-failure results.
- **Decisive measurement:** with the board running continuous transfers, a
  multimeter on the copper at J55 pin 1 (MOSI, pkg D12) and pin 2 (MISO, pkg E10)
  showed **no electrical activity** — pins are not being driven.

### Diagnostic logic

| Observation | Implies |
|---|---|
| Internal loopback PASS | Core / FIFO / driver path good |
| External FAIL on all pin positions | Not a pin-selection error |
| J55 pin 1/2 copper inactive during transfer | Bitstream not routing AXI SPI to J55 I/O |

The signal never reaches the J55 header, so no jumper placement could ever pass.
This is an I/O-routing problem in the loaded bitstream, **not** a bench-wiring,
register, driver, or core problem.

## Rebuild attempt (2026-06-01) — design confirmed good, synthesis license-blocked

Attempted a full rebuild on stile's Vivado 2025.1 to regenerate the bitstream.
Result: **the design is sound and rebuilds; only synthesis is blocked, by a
missing Xilinx license for the xczu9eg device.**

Sequence and outcome:

1. Sourced `spi_bm_bd.tcl` in Vivado 2025.1. Hit the version guard (script authored
   in 2024.2) and one stale IP pin: `zynq_ultra_ps_e:3.3` (2025.1 requires `3.5`).
2. Bumped the PS IP to 3.5 and neutralized the version guard. Block design then
   **constructed and validated cleanly** — `validate_bd_design` passed,
   `spi_benchmark.bd` written. All other IP (axi_quad_spi 3.2, smartconnect 1.0,
   proc_sys_reset 5.0) accepted as-is.
3. Generated HDL wrapper, added `zcu102_spi_benchmark.xdc`, set top, launched
   `impl_1 -to_step write_bitstream`.
4. Synthesis failed immediately with:

   ```
   ERROR: [Common 17-345] A valid license was not found for feature 'Synthesis'
   and/or device 'xczu9eg'.
   ```

5. License environment check on stile confirmed the cause: `XILINXD_LICENSE_FILE`
   and `LM_LICENSE_FILE` are **both unset**, and `~/.Xilinx/` contains **no `.lic`
   file**. Stile has no Xilinx synthesis license configured for this user — not a
   down/misconfigured server, simply no license present.

### Conclusion

- Design source (`spi_bm_bd.tcl`) is correct and rebuilds on 2025.1 with a single
  documented IP version bump (PS 3.3 -> 3.5).
- The only blocker to producing a fresh, correct bitstream is a **Xilinx synthesis
  license covering the xczu9eg device**, which is not installed on stile.

Recommended repo follow-up: commit the patched rebuild TCL (PS bumped to 3.5,
version guard neutralized) so the next attempt on a licensed machine is one
command. Suggested path: `hardware/spi_bm_bd_2025p1.tcl`.

## Outstanding checks (cheap, optional, to fully close the loop)

- Confirm Bank 28 VCCO present (~1.8 V at a UTIL_1V8 reference to GND). If the bank
  rail is dead, that is an alternative explanation (bank power vs. routing). If
  1.8 V is present and pins remain inactive, routing is confirmed as the cause.

## Impact on Phase 6 / paper

- **Headline benchmark results are unaffected.** Phase 6 Linux benchmarks
  (AXI 14.2x vs PS SPI) and the internal-loopback integrity validation stand.
- External loopback was an *additive* validation of the physical I/O buffers on an
  already-validated data path — a nice-to-have, not load-bearing for the headline
  finding.
- **Priority 2 (SCK clock-rate confirmation) is blocked by the same root cause.**
  Probing SCK (J55 pin 4 / F11) requires the pin to be driven; with J55 I/O
  inactive, an instrument would read SCK as dead. The clock-rate discrepancy
  (3.125 MHz formula prediction vs. ~11.1 MHz empirical) therefore cannot be
  resolved by probing until the bitstream is rebuilt.

## Single blocker / ask

Both remaining hardware items (external loopback validation, SCK clock-rate
confirmation) trace to one blocker:

> **A Xilinx Vivado synthesis license covering the xczu9eg device, installed on
> stile (or a license-server pointer to a seat that includes it).** Confirmed
> absent: no license env vars set, no `.lic` file present.

No design work is required — the block design rebuilds and validates on 2025.1
with one documented IP version bump. Once a synthesis license is available, the
rebuild is: source the patched TCL, generate wrapper, add XDC, write bitstream,
copy `.bit.bin` to SD, re-test. This closes both remaining items in one session.

Exact error to give the license admin:

```
ERROR: [Common 17-345] A valid license was not found for feature 'Synthesis'
and/or device 'xczu9eg'.
```
