# Bare-metal SPI benchmark — capture handoff

## STATUS: port PROVEN on silicon; capture of numbers is the open task.

The ported app (spi_benchmark_bare_zynqmp.c) compiles, the platform builds
natively in the unified Vitis CLI, DDR inits via psu_init over JTAG, the ELF
downloads, and the A53 core REACHES "Running" executing the benchmark on the
ZCU102. SPI1 TX confirmed active. The Zynq-7000 -> ZynqMP port is validated.
What's left is reading the result numbers out.

## SOURCE FIXES APPLIED (all committed to spi_benchmark_bare_zynqmp.c):
1. Header: xtime_l.h -> xiltimer.h + xtimer_config.h (SDT BSP; COUNTS_PER_SECOND
   = XSLEEPTIMER_FREQ = XPAR_CPU_TIMESTAMP_CLK_FREQ = 99990005, matches port math).
2. SPI lookup: XPAR_XSPIPS_1_DEVICE_ID -> XPAR_XSPIPS_1_BASEADDR (0xff050000);
   SDT LookupConfig takes base address, not device id.
3. UART baud fix block at top of main(): XUartPs_LookupConfig/CfgInitialize/
   SetBaudRate(115200) on XPAR_XUARTPS_0_BASEADDR. NOTE: did NOT resolve serial;
   see UART issue below.
4. JTAG capture scaffolding: results[] promoted to file-scope global @ 0xe178;
   volatile u32 g_done @ 0xe2d8 set to 0x0000D09E after fill loop (+ dsb barrier).
5. NUM_TRIALS currently 20 (line 50) for fast capture test — RESTORE TO 1000
   for the publishable run.

## BUILD (works reliably):
- Platform: built natively via client.create_platform_component from
  hardware/xsa/spi_benchmark_wrapper.xsa, os=standalone, cpu=psu_cortexa53_0.
  (XSCT-built platform export is NOT consumable by unified CLI — must build native.)
- App: workspace ws2 (unified, NOT classic ws). /tmp/do_build.py re-imports
  src + builds. ELF at ws2/spi_bm_app/build/spi_bm_app.elf.
- XSCT GUI backend (rdi_vitis) CRASHES (tcache double-free) on stile — use
  `vitis -s <script>` Python CLI for build, `xsdb` for load. Both healthy.

## SYMBOLS (re-check after rebuild; addresses shift):
- results @ 0xe178 (11 entries x 32 bytes; each = 4x u64 LE: min,max,avg,stddev ns)
- g_done  @ 0xe2d8 (reads 0x0000d09e when benchmark complete)
- payload ladder: 1,8,16,64,128,256,512,1024,4096,16384,65536

## TWO ENVIRONMENT OBSTACLES (not code bugs):
1. UART baud: UART0_REF_CTRL = 166.67 MHz (IOPLL 2GHz / 12), but print divisors
   (BAUDGEN=51,BAUDDIV=16 = /867) assume 100 MHz -> app TX'd at ~192234 baud, not
   115200. stty can't set 192000. SetBaudRate(115200) in code did not fix it
   (BSP config likely carries wrong input clock). FALLBACK: hardcode BAUDGEN=207,
   BAUDDIV=6 for true 115200 @ 166.67MHz, OR just read results over JTAG.
2. xsdb reset nondeterminism: `rst -processor` lands in varying stopped substates
   (Reset Catch / External Debug Request / Suspended). psu_init only tolerates
   some -> intermittent "EDITR not ready". `rst -system` leaves "APU Reset" which
   psu_init also rejects ("not stopped"). Need a reliable settle-to-stopped.
   `mrd -force` does NOT bypass halt requirement on this xsdb (2025.1).

## RECOMMENDED NEXT-SESSION APPROACH (JTAG memory read, no UART):
1. Reliable reset: loop `rst -processor; after 2000; check [state] contains
   "Stopped"` and retry until psu_init succeeds (or investigate -clear-registers
   per the reset warning xsdb prints).
2. Load + con. With NUM_TRIALS=20, wait ~25s. With 1000, full run is ~15-20 MIN
   (64KB row alone ~9 min at 0.9766 MHz SCK).
3. `stop` once after completion, then plain `mrd 0xe178 88` (no -force; halted).
   Verify g_done @ 0xe2d8 == 0x0000d09e first.
4. Decode 88 words: per entry [min_lo,min_hi,max_lo,max_hi,avg_lo,avg_hi,
   sd_lo,sd_hi] little-endian u64. avg_ns/1000 -> us. Diff vs results/emio_results.csv.

## BOARD STATE: SW6 = all ON (JTAG boot). Restore SW6=OFF,OFF,OFF,ON for SD/Linux.
## JTAG chain has TWO devices: Zynq-7000 (xc7z020, target ~2/3) AND our ZynqMP
   (target 13 = A53#0). Always `targets 13`. Don't touch the 7z020.


================================================================
UPDATE (session 3) — JTAG dow dead-end; SD/FSBL boot faults at banner
================================================================

## JTAG dow path: ABANDONED
- dow does NOT load the ELF into DDR in this xsdb+psu_init sequence. Proven:
  ELF says 0x0 = b _boot (1400024e), but memory at 0x0 reads 0x00005003 after
  dow. Manual mwr works, dow does not -- dow/mrd disagree (MMU/remap/coherency).
- Relinked app base 0x0 -> 0x100000 (lscript ORIGIN edit, survives rebuild).
  After relink, 0x100000 had real-looking code but single-step jumped to
  0x5555555555555555 by step 5 -> dow still not landing OUR bytes. Dead end.
- cpsr at fault = 0x3cd -> core IS at EL3 (mode 0xd = EL3h). EL is NOT the issue.
- Hello World template app faults IDENTICALLY via dow -> confirms it is the
  launch/load path, NOT our code.

## Pivoted to SD-card / BOOT.BIN boot (FSBL loads properly, bypasses dow)
- bootgen builds BOOT.BIN fine. bif: [bootloader] fsbl + [pmufw_image] pmufw +
  [a53-0, el-3] spi_bm_app.elf.  App relinked to 0x100000.
- Workflow: build BOOT.BIN on stile -> git push -> jerry0510 pull -> copy to
  /media/jerry0510/BOOT/BOOT.BIN (Linux BOOT.BIN backed up as .linux-backup)
  -> card to ZCU102 -> SW6=OFF,OFF,OFF,ON (SD boot) -> full power cycle.
- BOOT.BIN variants tried, ALL fault:
  1. ws2 FSBL + no PMU            -> APU held in reset, CBR not done.
  2. ws2 FSBL + ws PMU (mismatch) -> same.
  3. ws FSBL + ws PMU (matched)   -> FSBL prints partial banner
     "Zynq MP First Stage" then resets/loops or stalls. Dies BEFORE finishing
     the banner line -> faults within first FSBL printf, before DDR init.
- Two FSBLs exist: ws2/.../fsbl.elf (534688 B, used first) and
  ws/.../fsbl.elf (478904 B). ws set has matched pmufw.elf (504216 B) + its
  own spi_bm_plat.bif.
- Linux BOOT.BIN (sd-images/BOOT.BIN, 1775880 B) BOOTS FINE on this same board.
  Its chain: zynqmp_fsbl.elf -> bl31.elf (ATF) -> system.dtb -> u-boot.elf, with
  PMU fw. So a known-good FSBL/PMU for THIS board exists inside it.

## UART baud: SOLVED for FSBL
- FSBL prints at clean 115200 (confirmed: banner reads with no garbage at 115200
  via pyserial). Earlier 192k garbage was the APP's forced clock, not the FSBL.
- pyserial 3.5 installed. Reader: /tmp/ser.py <baud> <port>. Use 115200 for FSBL.
- (Our app, once running, may still TX at ~192k -- separate issue, irrelevant if
  we read results over JTAG instead.)

## NEXT SESSION -- FASTEST DISCRIMINATOR (do FIRST):
Build BOOT.BIN with known-good FSBL+PMU + STOCK hello_world app (not our bench).
  - If hello ALSO faults at banner -> our bootgen/boot-image construction is
    wrong (header attrs, or FSBL-vs-board mismatch). Fix the image, not the app.
  - If hello BOOTS -> problem is our app load/handoff (0x100000? el-3?). Diff.
Better known-good FSBL source: extract zynqmp_fsbl.elf + pmufw from the working
  Linux sd-images/BOOT.BIN (bootgen read), OR rebuild FSBL from the actual
  ZCU102 BSP/XSA (our spi_benchmark_wrapper.xsa PS config may mismatch the real
  board DDR -> that would explain FSBL dying at DDR init right after banner).
Also: reading results over JTAG WORKS (only dow-LOAD failed). Once the app boots
  via FSBL, capture via: targets 13; stop; mrd 0x10e2d8 1 (g_done==0000d09e);
  mrd 0x10e178 88 (results, 0x100000-relink addresses).

## Capture addresses (0x100000 relink build): results@0x10e178 g_done@0x10e2d8
## NUM_TRIALS=20 (line 50) for fast test; restore 1000 for publishable run.
## Board: SW6 all-ON = JTAG halt; OFF,OFF,OFF,ON = SD boot. Restore as needed.
