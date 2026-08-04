# ZDMA Anchor — Round 4 Result (2026-08-04, stile)

## Milestone: the fix BUILT and RAN on hardware for the first time
- Placement bug fixed (RX burst-config block was outside zdma_init(); commit 6a2854e).
- Built clean on stile Vitis 2025.1: spi_bm_zdma.elf (md5 f3aeb97f).
- Boot image BOOT_zdma.bin (md5 ef9a310e) flashed via jeremiahc SD, SD-booted.
- Anchor gate ran end-to-end. Full build/deploy/capture pipeline now proven on stile.

## Verdict: FAIL — physics_fail=11, rx_mismatch=10  (but diagnostic)
RX MISMATCH pattern (correct bytes per payload):
    64B->1  128B->1  256B->1  512B->2  1024B->4  4096B->16  16384B->64  65536B->256
  => correct_bytes = payload / 256 exactly (for payload >= 256).

## Root cause (characterized, not yet solved)
The DMA destination address advances by ~256 bytes per burst even though we set
AWBURST = XZDMA_FIXED_BURST. 256 bytes = default DstBurstLen 0xF (16 beats) x
16-byte ZDMA data path. So exactly one byte per 256-byte burst-span lands in the
fixed TXD FIFO register (0xFF05001C); the rest scatter into adjacent addresses.

## What is RULED OUT (with evidence)
- NOT a chunking problem: zdma_spi_transfer() ALREADY loops by SPI1_FIFO_DEPTH
  (128B) chunks, TX-DMA -> drain-wait(TXOW) -> RX-DMA, advancing src/dst ptrs.
  The scatter happens WITHIN a single <=128B chunk's DMA.
- NOT a config-persistence problem: SetChDataConfig runs once in zdma_init
  (lines 205/234); XZDma_Start runs per-chunk (277/300); nothing clobbers the
  channel DATA_ATTR between them. The FIXED setting persists.
- NOT the placement/syntax bug (fixed this session) and NOT a stale binary
  (md5 chain verified ELF f3aeb97f -> BOOT ef9a310e -> on card).

## The narrow open question (for next session, TRM in hand)
Does ZynqMP simple-mode ZDMA actually honor AWBURST=FIXED to hold a destination
address across a burst, or does true fixed-address-to-peripheral-FIFO require
something else? Candidates to investigate NEXT:
  1. Set DstBurstLen = 0 (1 beat/burst) on TX and SrcBurstLen = 0 on RX, so each
     AXI beat is a standalone transaction to the fixed address. Cheapest test.
     (Add TxCfg.DstBurstLen=0 / RxCfg.SrcBurstLen=0 to the existing config blocks.)
  2. Confirm in ZynqMP TRM (ZDMA / LPD-DMA chapter, DATA_ATTR register) whether
     FIXED burst to a peripheral register is supported in SIMPLE mode, or requires
     scatter-gather with per-descriptor fixed addressing.
  3. Check whether the ZDMA "point-type"/simple-mode inherently assumes an
     incrementing memory destination (it may — SimpleMode writes DstAddr once and
     lets the engine walk it).

## Fast iteration path is now PROVEN
edit source -> rebuild on stile (vitis -s /tmp/build_app.py) -> cp ELF into
sd-images/baremetal/ -> bootgen -image zdma.bif -> commit+push -> pull on
jeremiahc -> cp to /media/jeremiahc/BOOT/BOOT.BIN -> SD boot -> screen
/dev/ttyUSB0 115200 -> read ANCHOR VERDICT.
Try candidate #1 (DstBurstLen=0) FIRST next session — one-line change, fast test.
