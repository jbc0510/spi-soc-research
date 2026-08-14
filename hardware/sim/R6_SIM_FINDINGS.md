# Round-6 keyhole sim — interim findings (2026-08-04, sim runs 1-5)

## Answered on the bus (monitors, run 5, log r6_keyhole_sim5_bus_truth.log)
1. CDMA KEYHOLE WORKS: with CDMACR bit5 set, M_AXI issued FIXED bursts
   (AWBURST=0) at 0xA0000068, address held WITHIN and ACROSS bursts
   (len=5 then len=9, both at 0x68). PG034 behavior confirmed in RTL.
2. BLOCKER FOUND PRE-SILICON: SmartConnect does NOT convert multi-beat
   FIXED bursts to AXI4-Lite — Phase A writes never appeared on M00;
   CDMA received DECERR (CDMASR=0x5042). Current add_cdma_r6.tcl wiring
   (CDMA -> SC -> QSPI AXI4-Lite) would fail identically on hardware.
3. NEGATIVE CONTROL PERFECT: INCR phase converted fine and walked
   0x68,6c,70,74,78,7c then WRAPPED through the 7-bit Lite window into
   0x00,04,08... — clobbering QSPI control registers. Textbook capture
   of why INCR DMA into register space is unsafe.
4. TB readback plumbing still returns zeros (VIP read API); bus RDATA
   is correct (run 4). Cosmetic — verdict moves to monitors next rev.

## Next session
- Read PG153 (Quad SPI C_TYPE_OF_AXI4_INTERFACE / full-AXI4 slave mode
  constraints) + PG247 (SmartConnect FIXED-burst support matrix).
- Candidate fix: QSPI full-AXI4 slave so FIXED passes unconverted;
  revise add_cdma_r6.tcl accordingly, re-run this sim as the gate.
- Fix TB verdict (monitor-based) + VIP read API.
Files: sim_keyhole_bd.tcl, tb_keyhole.sv (v4), run_keyhole_sim.tcl.

## CORRECTION (2026-08-10) — blocker is broader than stated in item 2
Item 2 above attributes the DECERR to SmartConnect failing to CONVERT
multi-beat FIXED bursts to AXI4-Lite. The real limitation is unconditional:
per UG1037 (Vivado AXI Reference Guide, AXI SmartConnect Core Limitations),
SmartConnect does NOT support FIXED type bursts at all. Any FIXED burst
received at the SmartConnect SI is blocked and DECERR is returned to the
master. The downstream slave protocol is irrelevant — the block happens at
the SI, before conversion is attempted.

CONSEQUENCE: the "candidate fix" in Next Session (QSPI full-AXI4 slave) is
NECESSARY BUT NOT SUFFICIENT. With SmartConnect still in the CDMA M_AXI
path, CDMASR=0x5042 would reproduce identically. SmartConnect must be
removed from that path.

REVISED FIX (three coupled changes, all pre-silicon, sim-gated):
1. AXI Quad SPI -> AXI4 interface mode, Performance Mode ON, XIP OFF
   (PG153: enhanced/non-XIP supports fixed-burst transfer at DTR/DRR only;
   XIP mode is read-only, no writes). Standard SPI mode + 256 FIFO retained
   per PG153 feature summary, so benchmark comparability is preserved.
2. Replace SmartConnect with AXI Interconnect v2.1 on CDMA M_AXI.
   PG059 "AXI Interconnect Core Limitations" does NOT list FIXED; crossbar
   propagates m_axi_awburst. Supported on UltraScale+ (xczu9eg). NOTE:
   absence from a limitations list is weaker than positive support -> sim
   remains the gate, docs do not.
3. No couplers on the QSPI path: match CDMA M_AXI width to QSPI AXI4 slave
   (32-bit) to avoid a width converter (PG059 packing would defeat FIXED);
   set QSPI MI write-issuing limit = 1 (PG153: one write outstanding max).

## AMENDMENT (2026-08-10) — PG153 read; topology corrected AGAIN
Source: PG153 v3.2 (AXI4 Interface / Enhanced Mode / Register Space /
Port Descriptions / Unsupported Features), retrieved 2026-08-10.

### A1. Enhanced mode REPLACES the Lite interface — it is not additive
"In this mode, the AXI4-Lite interface for the core is replaced with the
AXI4 interface." Port table confirms: s_axi_aclk/s_axi_aresetn exist only
in legacy+XIP; s_axi4_aclk/s_axi4_aresetn only in enhanced+XIP. Only XIP
mode carries BOTH interfaces (and XIP is read-only -> useless to us).
=> QSPI has exactly ONE slave port in enhanced mode. PS control writes AND
CDMA FIXED bursts must both traverse the SAME interconnect.
=> CORRECTS the 2026-08-10 correction above: SmartConnect cannot be kept
for a "control-only" path. It must be SWAPPED OUT of the design entirely
(PS->QSPI control also needs FIXED-tolerant fabric on that leg).
=> Revised topology is a straight swap, same 2 SI / 3 MI shape:
   axi_interconnect: S00<-PS M_AXI_HPM0_FPD, S01<-CDMA M_AXI;
   M00->QSPI AXI4, M01->CDMA S_AXI_LITE, M02->PS S_AXI_HP0_FPD.

### A2. Comparability PRESERVED (assumption cleared)
"The core supports the same functionality as the AXI4-Lite interface. The
added advantage for this mode is burst capability at the DTR and DRR
locations." Table 1 lists Enhanced + Standard + ratio 2,4,8,Nx16 + FIFO
0/16/256 as legal. C_SCK_RATIO=16, C_SPI_MODE=0, C_FIFO_DEPTH=256 all
survive. SPICR LOOP bit (standard-SPI-only) intact -> loopback path intact.
Enhanced mode is NOT flash-command-framed in a way that breaks the
same-controller comparison against axi_results.csv.

### A3. Register offsets UNCHANGED (assumption cleared)
"All of the registers are mapped to the same offset as with the AXI4-Lite
interface." DTR=68h, DRR=6Ch, SPICR=60h, SPISR=64h, TXFIFO_OCY=74h.
tb_keyhole.sv hardcoded QSPI+0x68 and +0x74 remain correct. No TB rework.

### A4. NEW CONSTRAINT — 1 SPI byte per 32-bit AXI beat (throughput trap)
Unsupported Features: "Narrow bursts in enhanced mode (only the last
8-bits from the 32 burst bits are valid in enhanced mode)."
=> A 16-beat keyhole burst moves 64 AXI bytes but only 16 SPI bytes.
=> CDMA BTT must be 4x the intended SPI payload.
=> ANCHOR/VERDICT MUST ASSERT ON MEASURED SPI BYTES (TXFIFO occupancy /
   DRR count), NOT ON BTT. Reporting BTT as throughput would inflate the
   DMA path 4x — same class of error as the round-4/5 clock artifact.

### A5. NEW CONSTRAINT — INCR>1 and WRAP unsupported in enhanced mode
Sim finding #3 (INCR walked 0x68..0x7c then WRAPPED into 0x00,04,08,
clobbering control regs) was captured against a LEGACY/Lite QSPI. In
enhanced mode PG153 implies INCR>1 faults at the slave. IT DOES NOT.

RE-CAPTURED 2026-08-10 on the v3 (axi_interconnect) topology.
Source: hardware/logs/r6sim_1e_20260810_1106.log

  PHASE_A (keyhole bit5=1): done=1 OCY=15 addr_held=1  (L505, L507)
  PHASE_B (keyhole bit5=0): done=1 OCY=5  addr_held=0  (L562-L564)
  Both phases: aw=2, w=16 beats issued, MON M00.B resp=0 (OKAY),
  CDMASR=0x00001002 (done, no error bit).

The master sees SUCCESS in both cases. Under INCR only 5 of 16 beats
reached the TX FIFO and NOTHING at the AXI level reports the loss --
no fault, no error response, no status flag. Where the other 11 beats
went is NOT determinable from this log; the count is measured, the
mechanism is not. Do not assert a mechanism without a waveform.

This is a documentation-vs-silicon discrepancy of the same class as the
SmartConnect FIXED-burst block and the PL0 clock: the authoritative
document was wrong and only measurement caught it.

The original Lite-path finding stays valid as a Lite-path result.
RE-CAPTURE directive DISCHARGED.

### A6. NEW CONSTRAINT — no simultaneous read+write in enhanced mode
"Simultaneous read and write transactions in enhanced mode" unsupported;
"only one read or one write transaction is acceptable at a time."
Write-only DTR benchmarking is fine. Any future full-duplex DRR/read
benchmarking is constrained -> note in SOW 2.b writeup.

### A7. OPEN — ext_spi_clk headroom to re-check before silicon
PG153 max ext_spi_clk, ZynqMP MPSoC, no STARTUP: 150-165 MHz; footnote
"for xip and standard modes, ext_spi_clk might be limited to 60 MHz."
Our ext_spi_clk is tied to PL0 = 250 MHz (live-readback confirmed).
Table is characterized for Quad mode and states values vary by mode, so
this is NOT a confirmed violation — but given the FSBL PL0-override
history, verify against the post-impl timing report before programming.

### A8. Tcl sites needing rename (enhanced mode changes pin/intf names)
spi_bm_bd_2025p1.tcl lines 603 (C_TYPE_OF_AXI4_INTERFACE 0->1), 621, 634,
643, 651; add_cdma_r6.tcl line 41. All refs to axi_quad_spi_0/AXI_LITE,
s_axi_aclk, s_axi_aresetn change. Exact BD interface/pin/param names are
NOT documented in PG153 -> discover them with probe_qspi_enhanced.tcl
before writing the delta. Docs answered the functional questions; they do
not tell us Vivado's naming.


---

## MEASURED (2026-08-10) — PHASE_C backpressure, and the SPE=1 requirement

Sections A1-A8 above are PG153-derived. This section is measured.
Source: hardware/logs/r6sim_1e_20260810_1106.log (the final and only
complete v3 simulation run). Testbench: hardware/sim/tb_keyhole.sv.

### M1. Backpressure is real and hard, at exactly C_FIFO_DEPTH
tb_keyhole.sv:92 -- run_phase(1, "PHASE_C", 2048), commented
"512 SPI bytes into a 256B FIFO". BTT=2048 AXI bytes / 4 bytes per beat
= 512 W beats intended.

MEASURED: exactly 256 W beats accepted (count over L594-L4062), then the
CDMA stalls. 256 == C_FIFO_DEPTH exactly.

What the log SHOWS: the master issues 256 W beats and then issues no
more. What FOLLOWS from AXI backpressure semantics (inference, one step
from the log): nothing is dropped -- WREADY deasserts and the beats are
withheld rather than lost. The loss-free claim has not been separately
measured; a DRR/occupancy readback after re-enabling SPE would confirm it.

### M2. The stall is a DEADLOCK, not slow progress
The run terminates on a VIP watchdog Fatal, NOT a clean $finish:

  L4062  Forward progress timeout, 513905 ns, 2 pending AR commands,
         no RDATA+RLAST in 50000 cycles.

Mechanism, readable end to end in the log: the write side is blocked on
a full TX FIFO with SPE=0, so no drain occurs; the CDMA therefore cannot
retire its outstanding BRAM reads; the read-side VIP times out. The last
~3400 lines are the testbench polling CDMASR at 0xa0010004 every 320 ns
and reading 0x00000000 -- the done bit never sets.

READ THIS BEFORE JUDGING THE LOG: PHASE_A and PHASE_B completed normally
and printed their results (L505-L564) BEFORE PHASE_C deadlocked. The
Fatal does not invalidate them. PHASE_C deadlocking IS the result.

### M3. HARD REQUIREMENT — SPICR.SPE=1 before kicking the CDMA
Any payload exceeding C_FIFO_DEPTH hangs SILENTLY with SPE=0: no error,
no fault, no status bit, just a stall until something times out. The
benchmark MUST enable SPE before starting the DMA.

Consequence for SOW 2.b: with SPE=1 the CDMA self-throttles to SCK, so
DMA throughput will be SCK-bound and roughly equal to PIO. DMA's
contribution is CPU OFFLOAD and DETERMINISM, not throughput.

### M4. Burst directions confirmed on the wire
PHASE_C monitor output shows the intended asymmetry:
  MON CDMA.AW addr=0xa0000068 len=15 burst=0   (FIXED, into DTR)
  MON CDMA.AR addr=0x00000080 len=15 burst=1   (INCR, out of BRAM)
This is the keyhole topology working as designed.
