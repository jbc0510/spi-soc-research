# RESUMING ON THE OPENTITAN MACHINE — READ THIS FIRST

This work moved from `stile` to the OpenTitan machine at Morgan (has Xilinx
tools + the ZCU102 board). Before touching the ZDMA bug, clear these four
setup checks. Do them IN ORDER — a missing workspace is a bigger detour than
the actual fix, so catch it first.

## 0. Toolchain version + path
Entire build/provenance chain assumes Xilinx **2025.1** (SDT-mode BSP,
bootgen v2025.1). Confirm:

    ls /tools/Xilinx/
    /tools/Xilinx/2025.1/Vitis/bin/vitis -version 2>&1 | head -3

If version/path differ: update paths in dma/baremetal/build_zdma_app.py and
create_zdma_app.py, AND note a different Vitis version may regenerate the BSP
differently (version skew caused the SDT lookup bug, commit 777e183). Verify
BSP xparameters after any regen — don't assume.

## 1. Repo + branch
    cd spi-soc-research && git checkout feature/dma-benchmarking
    git log --oneline -8      # expect 42d33c2 or later at top
    md5sum sd-images/baremetal/BOOT_zdma.bin   # expect aba250eb... (round-3)

## 2. Workspace regeneration (LIKELY NEEDED on a fresh machine)
bare_metal/vitis/ws2/ is .gitignore'd by design. On a fresh clone it WON'T
exist — including platform spi_bm_plat, also untracked. Check:

    ls bare_metal/vitis/ws2/spi_bm_plat/export/spi_bm_plat/*.xpfm

- Present: create_zdma_app.py rebuilds the app component directly.
- MISSING: regenerate the platform FIRST (needs the .xsa/hardware handoff —
  locate it before starting). This step can eat a whole session. Do it before
  any DMA debugging.

## 3. Board deploy path on THIS machine
On stile: stile->GitHub->jeremiahc->SD->board (no net path to board). On the
OpenTitan machine, if board + SD reader + build tools are one box, build and
flash locally. Confirm which BEFORE setting up UART capture.
  - UART: screen -L -Logfile ~/log /dev/ttyUSB0 115200 (check tty name — may
    not be ttyUSB0 here).
  - SD mount: lsblk -o NAME,SIZE,LABEL,MOUNTPOINT to find it (was mmcblk0p1).
  - Linux restore point BOOT.BIN.linux-a25d6549 is on the card (md5 a25d6549).

## 4. Only after 0–3 pass: resume the ZDMA bug
Pick up at the "EXACT NEXT STEP" section below — the four diagnostic greps for
the incrementing-destination-address hypothesis. No board trip for that step.

---
# Phase 3 (Bare-Metal ZDMA) — Session Handoff

**Branch:** feature/dma-benchmarking
**Last commit at session end:** 9fc8759 (round-3 image) — verify with `git log --oneline -5`
**Board state:** SD card holds round-3 image `aba250eb...` as BOOT.BIN.
  Linux restore point on card: `BOOT.BIN.linux-a25d6549` (md5 a25d6549...).
  image.ub untouched (ffe0c75b, inert for EL3 bare-metal boot).

## Where we are
The ZDMA app compiles, boots at EL3 (no ATF — Phase 2 TrustZone blocker is
structurally absent here), and both ZDMA channels + SPI1 initialize on
silicon. But the benchmark **does not measure real SPI transfers.** Three
rounds of anchor tests all FAILED the physics gate identically.

## The failure signature (identical across rounds 1, 2, 3)
- Flat bus-speed timing: 1 B ~2 us (wire floor 8.2 us), 64 KB ~459 us
  (wire floor ~537 ms). ~1000x too fast — measuring bus, not wire.
- RX MISMATCH on every payload, pattern `payload - N` bytes differ where
  N is small (1 B->0-ish, 16 B->15 differ, 1024 B->1020 differ,
  64 KB->65280 differ). I.e. only the first few bytes ever match.

## What we already fixed (committed, correct, but insufficient)
1. **SDT base-address lookups** (commit 777e183): BSP is SDT-mode;
   XZDma/XSpiPs LookupConfig take base address, not device ID. Fixed.
   This is why inits now pass on silicon. KEEP.
2. **Sticky-ISR drain-wait** (commits 350581f, f878a17): Cadence SR at
   0x04 is W1C interrupt-status; TXOW must be cleared AFTER the FIFO is
   filled (condition false) or it re-latches instantly. Ordering now:
   TX DMA start -> TX busy-poll -> clear TXOW -> drain-poll -> RX DMA.
   Structurally correct now, but did NOT fix the symptom -> the real
   bug is upstream of the drain-wait.

## The leading hypothesis for the REAL bug (NOT yet fixed)
**ZDMA is writing to the TX FIFO with an INCREMENTING destination
address.** ZDMA is a mem-to-mem engine; in WRONLY mode it still
increments DstAddr by default. So:
- byte 0 -> 0xFF05001C (TXD, correct)
- byte 1 -> 0xFF05001D (wrong — scatters into register space)
- byte 2 -> 0xFF05001E ... etc.
Only the first byte(s) reach the FIFO. This explains BOTH symptoms at
once: near-zero wire time (≈1 real byte per "128 B" burst) AND the
"first N bytes match, rest garbage" RX pattern.

Secondary concern: even with a fixed address, ZDMA issues AXI burst
beats (up to 64-bit); the Cadence TXD expects one word write = one FIFO
entry. PS SPI has NO DREQ (our own design note) so there's no flow
control to gate bursts. This is the "burst-and-wait required" risk that
was flagged at design time but never handled in code for the address mode.

## EXACT NEXT STEP (start here next session)
Diagnose in source BEFORE any rebuild — three board trips on the wrong
theory was enough. On stile, run:

    grep -n "WRONLY\|RDONLY\|XZDma_SetMode\|PointType\|SetDescriptorType" dma/baremetal/spi_benchmark_zdma.c
    grep -n "OverFetch\|SrcBurst\|DstBurst\|SetChDataConfig\|ChDataConfig" dma/baremetal/spi_benchmark_zdma.c
    grep -rn "OverFetch\|DstIssue\|ChDataConfig\|Fixed\|keyhole\|Burst" bare_metal/vitis/ws2/spi_bm_plat/psu_cortexa53_0/standalone_psu_cortexa53_0/bsp/include/xzdma.h | head -20
    sed -n '160,215p' dma/baremetal/spi_benchmark_zdma.c

Goal: find whether the xzdma driver exposes a FIXED-address / keyhole
mode for the destination (ZDMA hardware has it — DST_DSCR word bits — it's
how ZDMA-to-peripheral works at all). Verify against the ZDMA register
spec BEFORE editing. Then set the TX channel's dst address mode to fixed.

## Possible legitimate outcome (paper-relevant)
If the driver can't do fixed-dst cleanly, the honest finding is that
**LPD ZDMA + Cadence PS SPI without DREQ is the wrong architecture for
the TX FIFO path.** That's a real Task 2 data-movement result (mechanism
mismatch), not a failure — pairs with the existing AXI-vs-PS finding.
Document it as such if that's where the evidence lands.

## Validated infrastructure (all working — don't re-debug)
- Build: `vitis -s dma/baremetal/build_zdma_app.py` (incremental, -O0 -g3,
  parity with PIO app). create_zdma_app.py for from-scratch.
- Package: sd-images/baremetal/, `bootgen -arch zynqmp -image zdma.bif`,
  fsbl_good + pmufw_good, app at EL3, no bitstream.
- Deploy chain: stile commit/push -> jeremiahc pull -> udisksctl mount
  /dev/mmcblk0p1 -> cp to /media/jeremiahc/BOOT/BOOT.BIN -> sync -> verify
  md5 -> plain umount (NOT -l) -> lsblk confirms unmounted -> card to board.
- UART capture: `screen -L -Logfile ~/log /dev/ttyUSB0 115200` BEFORE power.
- Self-checking anchor: physics gate (avg < payload*8192ns) + RX==TX
  compare + final "ANCHOR VERDICT: PASS/FAIL" line. This caught all 3
  failures cleanly — the gate is the reason we didn't ship bad data.

## Open secondary oddity
FSBL banner appears MULTIPLE times in each UART log — board seems to
reboot/re-run mid-session. Unexplained. Diagnose once timing is fixed
(candidates: watchdog, app returning from main, power). Not blocking.

## Provenance chain (current)
source ef1aac7d (f878a17) -> elf 9090e328? NO: round-3 elf/image are
`aba250eb` (image). Re-verify next session with:
    md5sum sd-images/baremetal/BOOT_zdma.bin   # expect aba250eb...
    git log --oneline -8
