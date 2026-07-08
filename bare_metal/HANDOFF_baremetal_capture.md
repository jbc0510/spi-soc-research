# RESOLVED - BENCHMARK CAPTURED ON SILICON (1000-trial publishable run)

Everything below this block is the debug arc that led here; kept for the record.
The boot blocker and the capture blocker are BOTH solved. Summary of the answers:

## What finally worked (the short version)
- BOOT: SD-card boot with FSBL + PMU extracted from the working spidev PetaLinux
  project (/home/jconway/zcu102-spidev/images/linux/): fsbl_good.elf + pmufw_good.elf.
  The XSA-built FSBLs (ws/ws2) died mid-banner; the board-matched PetaLinux pair
  boots clean. Root cause of the old mid-banner death: FSBL/board DDR-config
  mismatch, exactly candidate (a)/(b) flagged in session 3.
- HANDOFF (EL): app is EL3-built; bm.bif hands it off at el-3 directly, NO ATF.
  EL2-via-ATF handoff hung at 0x100abc. So: [bootloader]fsbl_good +
  [pmufw_image]pmufw_good + [a53-0, el-3]spi_bm_app.elf. No bl31.
- CAPTURE: the app prints the full results table to UART (clean 115200) on its
  own - JTAG readback is now BACKUP, not the primary path. The old ~192k app-baud
  problem did not materialize on this build; table read cleanly via screen.
  JTAG fallback (proven working): targets 13; catch {stop}; mrd -value 0x10e178 88;
  g_done @ 0x10e2d8 reads 53406 (=0xD09E). Output radix is DECIMAL ns.

## The validated run
- NUM_TRIALS=1000. Image: BOOT_baremetal.bin (323952 B), committed 9a4a798 on
  dev, silicon-proven. Source NUM_TRIALS at line 50 (=1000).
- SPI1_REF_CTRL confirmed 0x01001800 (/64, 0.9766 MHz SCK) in-band at boot.
- Dataset: results/baremetal_results.csv (avg_us schema, matches compare_spi.py).
- Comparison: compare_spi.py now registers baremetal as a 4th interface
  (run with --sck-ps 976600). BM passes the flat-stddev integrity check; the
  Linux emio/mio baselines FAIL it (modeled 1.0 stddev - see KNOWN GAP).
- Headline: BM vs EMIO at 1 B = 10.3 vs 38.5 us = 3.73x (clean OS-overhead,
  SAME wire/clock - better isolation than the script EMIO-vs-AXI 1.61x, which
  does not hold SCK constant). Asymptotic BM-vs-Linux ~1.21x from 1 KB up.

## KNOWN GAP (next board session, do NOT forget)
- emio_results.csv / mio_results.csv have FABRICATED stddev (constant 1.0 us).
  compare_spi.py flags them every run. The bare-metal jitter-advantage claim
  (BM stddev 0.026-0.436 us, REAL) rests on a placeholder on the Linux side.
  For the paper: re-capture Linux EMIO/MIO with genuine per-trial stddev, or
  footnote the asymmetry honestly. BM side is publication-clean; Linux side is not.

================================================================
(historical debug arc follows)
================================================================

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


================================================================
UPDATE (session 3 cont.) — Hello World ISOLATION TEST: it is the FSBL/image
================================================================

## DECISIVE RESULT: stock Hello World fails IDENTICALLY to our app.
Built BOOT_hello.bin = ws FSBL + ws PMU + stock hello_world.elf (linked at 0x0,
unmodified). SD-booted it. Serial @115200 shows the SAME failure as our app:
prints partial banner "Zynq MP First Stage" then dies (stall/loop), never
finishes the banner line. => The boot failure is NOT our app, NOT the 0x100000
relink, NOT the benchmark code. It is the FSBL or the bootgen image construction.

## Ruled out this session:
- Our app as cause (Hello World fails same -> not us).
- App link address (Hello is at 0x0, still fails).
- Quick FSBL sources: Vitis tools ship NO zcu102 FSBL/PMU (only zcu104 base,
  wrong board). No PetaLinux project / loose zynqmp_fsbl.elf found on stile.
- bootgen extraction of the working Linux BOOT.BIN: -dump_dir only prints
  headers (no file out); -split tries to parse .bin as .bif (fails). Could not
  cleanly extract the Linux image's FSBL/PMU via bootgen on 2025.1.

## Serial: FSBL prints at clean 115200 (confirmed). Dies mid-banner -> failure is
   in FSBL's own early startup, before it finishes printing, before DDR/partition
   load. No error code visible (dies before printing one).

## Working reference: sd-images/BOOT.BIN (Linux, 1775880 B) BOOTS this board.
   Chain: zynqmp_fsbl.elf -> bl31.elf (ATF, el-3) -> system.dtb -> u-boot.elf(el-2).
   Note: Linux hands off FSBL->ATF(el3)->uboot(el2). Our bm.bif puts our app
   directly at el-3 with NO ATF. Possible the FSBL expects an ATF handoff, but
   that would fault AFTER banner, not mid-banner -- so probably not the cause.

## OPEN QUESTION (next session): why does a ZCU102-XSA-built FSBL die mid-banner?
   Candidates: (a) bootgen image attrs/structure subtly wrong; (b) FSBL build
   issue; (c) something about the ws/ws2 platform FSBL specifically.

## NEXT-SESSION PLAN (fresh approach needed -- not more blind swaps):
1. Get a genuinely board-matched FSBL+PMU. Best sources, in order:
   a. The PetaLinux project that built the working Linux BOOT.BIN (on another
      machine? jerry0510? ask Jerry). images/linux/zynqmp_fsbl.elf + pmufw.elf.
   b. Rebuild FSBL fresh from spi_benchmark_wrapper.xsa via the zynqmp_fsbl
      template, verifying the ZCU102 board preset / DDR config is selected.
   c. Extract from Linux BOOT.BIN with a proper tool (python bincopy, or
      bootgen with correct dump syntax for 2025.1 -- research the flag).
2. Consider adding ATF (bl31.elf) to the bif before our app, mirroring the
   Linux chain: [bootloader] fsbl + [pmufw_image] pmu + bl31(el-3) + app(el-2 or
   el-1). The stock standalone app may expect to run below EL3 after ATF.
3. Capture full FSBL serial (115200) for any error code if it ever prints past
   the banner.

## REMINDER: reading results over JTAG WORKS once an app actually runs. Only the
   dow-LOAD and now the SD-boot are blocked. App code remains unblamed throughout.
