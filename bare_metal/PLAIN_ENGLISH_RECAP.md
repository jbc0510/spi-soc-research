# What We've Been Doing - The Plain-English Story

## The one-sentence version
We set out to time how fast a small chip sends data when there's no operating
system in the way - and as of this session, it WORKS: the program boots on the
board, runs all its tests, and we have the full results.

---

## The goal, explained simply

Imagine you want to measure how fast a courier can hand a package across a desk.
You already measured it the "normal" way - with a receptionist (the operating
system, Linux) managing the handoff. But the receptionist adds delay. So we
wanted to measure the courier *alone*, with no receptionist at all. That "no
receptionist" mode is called **bare-metal** - the program talks straight to the
hardware.

The catch: the stopwatch program was written for an **older chip**. We moved it
to a **newer chip** on this board. Like adapting a recipe from an old oven to a
new one - most of it carries over, but a few dials are labeled differently and
had to be translated.

---

## What we found (the answer)

**The operating system adds a real, mostly-fixed delay to every transfer.**

- For a tiny 1-byte transfer, bare-metal is **3.7x faster** than Linux
  (10 microseconds vs 38). At this size the transfer itself is almost instant,
  so nearly all of Linux's time IS the receptionist's overhead.
- For large transfers, the gap shrinks to about **1.2x**, because the time spent
  actually moving the data grows and dwarfs that fixed overhead.
- Plain version: the OS adds roughly a constant ~28 microseconds per handoff.
  Painful when handoffs are small and frequent; barely noticeable when big.

**Bare-metal is also dramatically steadier.** With no OS to interrupt it
mid-measurement, the timing barely wobbles - under half a microsecond of jitter
even on transfers lasting half a second. That predictability is its own result,
and it's exactly what matters for real-time and security-critical work.

---

## How we got there - three doors

Getting the program to run meant getting through **three doors**: build it ->
load it onto the board -> start it running. By the end of this session all three
are open.

### Door 1: Build the program (done)
We translated the handful of instructions that differ between the old and new
chip (how it reads its clock, how it names the data-port hardware). Compiles
clean. Done.

### Door 2: Get it onto the board (done, after a detour)
The first method - pushing the program in through a debug cable (JTAG) - *looked*
like it worked but silently never placed our code in memory. We proved it wasn't
our fault: the chip-maker's own "Hello World" failed identically. So we switched
to the **proper** method: boot from the SD card, the way the board starts a real
product. That worked.

### Door 3: Start it running (done - this was the long fight)
The board's startup helper (the **FSBL**) kept crashing mid-boot - but only with
*our* boot file; the Linux one booted fine. The fix: we'd been using a startup
helper built from the wrong settings for this exact board. We borrowed the
**known-good startup helper from the working Linux setup** on the same board,
paired it with our program, and it booted cleanly with the right pair. The
program ran all 11 transfer sizes and printed its results to the serial console.

---

## The honest bottom line

We **got the numbers**, and the program itself was never the problem - every
wall we hit was about *getting it onto the board and starting it*, never the
stopwatch code. The breakthrough was realizing the startup helper has to match
the specific board it runs on; borrowing the proven one from the Linux build
was the key that turned the ignition.

**One caveat we're being upfront about:** the Linux numbers we compare against
have a real *average* but a **placeholder** jitter value (an earlier capture
filled in "1.0" instead of a measured number). Our analysis script catches this
automatically and flags it every run. So "bare-metal is steadier" is rock-solid
on our side but needs one more proper Linux measurement before it goes in a
paper. The averages are fine; only the jitter comparison needs that re-capture.

---

## What we accomplished

1. **Built the program clean** for the new chip - stable.
2. **Cracked the boot problem** - found that the startup helper must match the
   board, and used the proven Linux one to boot bare-metal successfully.
3. **Captured the full 1,000-trial dataset** - all 11 transfer sizes, real
   averages and real jitter.
4. **Built the comparison into the analysis pipeline** - the bare-metal numbers
   now sit alongside the Linux and AXI ones in one script, with automatic
   integrity checks (which is what caught the placeholder-jitter issue).

---

## Where the numbers live
- results/baremetal_results.csv - the 1,000-trial bare-metal dataset
- results/compare_spi.py - run it to regenerate the full four-way comparison
- HANDOFF_baremetal_capture.md - the full technical story and debug arc

---

*Status: all three doors open. Program built, boots on silicon, full results
captured. Remaining: one Linux re-capture for a clean jitter comparison.*
