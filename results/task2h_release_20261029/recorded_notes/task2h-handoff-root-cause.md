---
name: task2h-handoff-root-cause
description: "Why the Linux→bare-metal (task2h) handoff aborts, and the proven-good vs faulting parts"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2ca6d9fb-76b2-4b09-878e-5e8d039d2474
---

Linux→bare-metal SPI handoff (results/task2h_boot_handoff_*): the boot/marker/fallback
mechanism and U-Boot launch are NOT the problem. On 2026-10-29 a RAM-only reach-test
(`mw.l` a trivial UART-poke+spin stub at the exact failing addr 0x00100980, then
`go 00100980`) printed its marker and ran — proving:
- U-Boot `go` performs a complete, correct EL2→EL1 switch (armv8_switch_to_el1_m) and
  reaches the standalone load address; the low address and load path are fine.
- Earlier "`_boot` never executed" inference from the fault register dump was WRONG
  (over-read). Execution DOES reach 0x100980.

CONFIRMED (step-test markers A,B,C,D printed; E did not): the fault is boot.S InitEL1
@0x100aac `msr sctlr_el1` ENABLING THE MMU + I/D caches. PMCR read/write (A→B→C) and
TTBR0/MAIR/TCR set (C→D) all succeed. A follow-up stub that installed its OWN EL1 fault
handler + enabled the MMU printed A,D then NOTHING (no handler '>') — so after the MMU
turns on, even the exception-vector fetch in low DDR faults. Conclusion: the Xilinx
standalone translation table (TTBR0=0x117000, TCR=0x200803520, MAIR=0xbb0400ff44) does
NOT map low DDR in the EL1-under-U-Boot regime (works at EL3 in the normal FSBL boot,
which is why the standalone BOOT.BIN runs fine but the U-Boot→EL1 launch does not).

FIX — IMPLEMENTED AND HARDWARE-VALIDATED 2026-10-29: custom msu2_el2_entry (in
bare_metal/src/spi_sustainable_benchmark_bare_axi.c) — enter at EL1 via U-Boot `go`
(clean state), set up our OWN flat identity MMU (table msu2_mmu_table: 0-2GB DDR Normal
cacheable, 2-4GB Device), set SP=__el1_stack/VBAR=_vector_table/CPACR(FP), OR SCTLR M|C|I,
then `b _startup` (BSS clear + libc init + PMCR + main). boot.scr builder
(scripts/build_msu2_handoff_boot_scr.py, new --elf arg) emits
`setenv autostart no; bootelf -p 0x08000000; go <e_entry>` (go to ELF entry 0x00100940,
NOT the load addr). FULLY WORKING END-TO-END on SD 2026-10-29: Linux msu2_demo.sh opt 2 -> PL/clock/bitstream
setup -> reboot -> boot.scr `go` -> bare-metal menu -> SPI benchmark ran with REAL numbers
(282457 one-byte transfers in 1.000s, 0 api_errors, 0 mismatches) -> `q` -> PSCI -> Linux.

SECOND fix needed for the SPI TEST itself at EL1: the app was architected for EL3 standalone
and attached to the GIC (XSetupInterruptSystem) + interrupt-driven XSpi_Transfer. At EL1
non-secure that hangs (cannot own secure GIC / IRQ storm). Fix: removed ALL GIC calls
(XSetupInterruptSystem, XDisableIntrId, XEnableIntrId, XDisconnectInterruptCntrl) and drive
completion by polling XSpi_InterruptHandler(&spi) in transfer_bounded's wait loop. The EL1
generic timer (XTime_GetTime/CNTPCT) works fine (go enabled EL1PCTEN). Deployed ELF sha
dc0369618eaf...(fix3); boot.scr 090de374... (entry 0x00100940 unchanged throughout).
Working source is in the working tree. Follow-ups: official Vitis rebuild for the manifest,
refresh results/task2h_boot_handoff_* SHA256SUMS/docs, commit.

MENU UX (done, validated on board): main() is now a for(;;) menu loop; run_test() returns
on every path so options 1/2/3/4 go back to the menu after success OR failure; only `q`
exits via PSCI reset. Added human-readable summary lines alongside the CSV. fix4 (7cced0d6)
validated: opt 4 ran clean + looped; opt 1 returned to menu.

OPEN ISSUE (resume here 2026-10-30): multi-byte RX reads all ZEROS. The external physical
MOSI->MISO loopback IS present (user confirms, proved hardware months ago) and MUST stay
external — internal CR loopback is off-limits (would not prove hardware). 1-byte "passes"
only because tx[0]=0 (spi_bench_prepare: tx[i]=i). Cause suspected: the polled
XSpi_InterruptHandler drain didn't capture RX. FIX WRITTEN BUT NOT YET TESTED: replaced the
whole transfer with a register-level polled master (polled_transfer) that drives CR/SSR/DTR
and drains DRR directly, CR bit0 LOOPBACK left clear (external only). Built offline as
fix5.elf sha e8e290945a304a9c4ed15ec90a47c2d44dcb9cf9d25b01256dc3b97e6009a25b (entry
0x00100940 unchanged -> reuse the on-card boot.scr 090de374; ELF-only swap). NEXT: stage
fix5.elf, run opt 1 and opt 2 with payloads 1,8,16 (short window e.g. 1s for speed). If RX
now == TX -> done. If first_actual still 0 in the CSV, the controller isn't sampling MISO ->
hardware-path/pinmux/CPOL-CPHA, not our code. User wants to walk EVERY menu option.
Staging recipe: SD at /media/opentitan/BOOT; backup + cp fix5.elf -> msu2_demo/
spi_axi_bm_menu_aarch64.elf; boot.scr untouched. Scratchpad has fix[1-5].elf + stage_*.sh.
Scratchpad is temp (may be gone next session) -- rebuild fix5 from the working tree with the
build_inputs.json gcc command if needed.

UPDATE EOD 2026-10-29: fix5 (register-level polled_transfer, e8e29094) is DEPLOYED on the
card and TESTED. Result: 1-byte clean + ~4x faster (1,111,016 transfers/s, max 0.910us);
multi-byte RX STILL mismatches (8-byte: first_error -10001 RX_MISMATCH). Two completely
independent RX drains (interrupt-handler poll AND raw DRR register read) give the IDENTICAL
failure -> it is NOT the firmware drain; it's the physical/PL MISO path or a bare-metal
AXI-SPI config detail. The committed source (577e127, pushed) is the GOOD checkpoint.
TOMORROW: (a) run menu option 1 to capture first_actual (confirm literal 0); (b) check if
the "worked months ago" proof was the Linux /dev/spidev1.0 loopback (not bare-metal) -- if
Linux spidev loopback still passes, physical+PL are fine and the gap is bare-metal SPI
config: compare CPOL/CPHA/SS/LSB-MSB and the J55 pinmux vs the Linux dtbo/spidev settings;
(c) walk every menu option. Do NOT use CR internal loopback (would not prove hardware). Board U-Boot symbols for 2025.01-ga09d2660433d
are NOT available locally (.build/uboot-task2g-* are different configs). See [[task2h-board-ops]].
