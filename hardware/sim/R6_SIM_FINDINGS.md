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
