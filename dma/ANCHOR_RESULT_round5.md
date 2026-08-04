# ZDMA Round 5 — Anchor Result: candidate #1 (BurstLen=0) FALSIFIED, branch root-caused to unsupported pairing

Date: 2026-08-04.  Commit under test: aa92da8 (source 8039e01b).
md5 chain verified at every hop:
  source 8039e01b -> ELF 911e3af1 -> BOOT_zdma.bin cb9548d5 -> SD card (verified post-sync)
Log: dma/logs/uart_round5_burstlen0.log (screen hardcopy of scrollback — round 5
was captured without -Logfile; future rounds: start screen with
`screen -L -Logfile <path>` BEFORE powering the board).

## Change under test
TxCfg.DstBurstLen = 0 and RxCfg.SrcBurstLen = 0 (AWLEN/ARLEN = 0, single-beat
transactions), added to the existing FIXED-burst config blocks, plus a
DATA_ATTR register readback print after each XZDma_SetChDataConfig.

## Result 1 — the configuration provably landed in hardware
  TX DATA_ATTR = 0x0483C200 : AWBURST[13:12]=00 (FIXED), AWLEN[3:0]=0   <- ours
                              ARBURST=01 (INCR), ARLEN=0xF (mem source, default)
  RX DATA_ATTR = 0x0080120F : ARBURST[27:26]=00 (FIXED), ARLEN[17:14]=0 <- ours
                              AWBURST=01 (INCR), AWLEN=0xF (mem dest, default)
Stable across three boots. This eliminates "driver dropped the config" for good.

## Result 2 — ANCHOR VERDICT: FAIL, physics_fail=11 rx_mismatch=10
Stride UNCHANGED: correct_bytes = payload/256 exactly, at every size
(65536->256, 16384->64, 4096->16, 1024->4, 512->2, 256->1; small payloads 1).
Identical to round 4 (16-beat bursts). Single-beat FIXED transactions produced
the same stride as before => the address walk is NOT AXI burst bookkeeping.
It is the ZDMA engine's internal address counter, which increments per byte
moved regardless of the AXI attributes in DATA_ATTR. Simple mode has no
register to freeze that counter.

## Result 3 — physics_fail on ALL 11 payload sizes (the deeper story)
65536 B completed in ~474 us  ~= 138 MB/s. Wire floor at 0.9766 MHz SCK is
~0.54 s. The DMA completes at memory speed with ZERO SPI pacing: TXD register
writes never backpressure, so the engine firehoses a 128 B FIFO and reports
done. Even with perfect fixed addressing this pairing cannot work — there is
no flow control between ZDMA and the SPI FIFO.
RESOLVED: round-4 anchor doc (line 9) confirms physics_fail=11 there too — the no-pacing behavior is an invariant of the ZDMA<->SPI pairing, present before the BurstLen=0 change, not introduced by it.

## External confirmation (AMD documentation, retrieved 2026-08-04)
- ZynqMP DMA Standalone driver wiki (xilinx-wiki.atlassian.net, page 18841725):
  "Peripheral DMA is not tested/supported."
- ZDMA Linux wiki (page 18842528): "No support for flow control mode";
  AXI burst lengths limited to powers of 2 (1..16).
- Xilinx staff forum answer: FIXED bursts supported in simple mode ONLY,
  not in SG mode => scatter-gather (round-4 candidate #2 fallback) is ruled
  out as well, not a path forward.

## Conclusion
ZDMA (LPD-DMA) + PS SPI1 FIFO is an architecturally unsupported pairing on
ZynqMP: the PS SPI (Cadence) exposes no DMA request interface, the ZDMA is a
mem-to-mem engine with no flow control and no hold-address mode. Candidates
1-3 from round 4 are all closed. This branch concludes as a DOCUMENTED
NEGATIVE RESULT — directly serving SOW task 2.b (analyze PIO and DMA transfer
mechanisms): on this platform, DMA-driven SPI requires either the QSPI
controller (built-in DMA) or a PL-side AXI DMA feeding the AXI Quad SPI.

## Round 6 recommendation
Pivot DMA benchmarking to the supported architecture: AXI DMA (PL) -> AXI
Quad SPI, giving the paper a genuine PIO-vs-DMA comparison on the AXI path,
with this negative result as the PS-side counterpart finding.
