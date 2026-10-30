# Live handoff diagnosis — 2026-10-29

UART: CP2108 interface 0, /dev/ttyUSB0, 115200. Initial Linux shell responsive.
Board kernel: 6.12.10-xilinx-g0a0f70e531c7.

Read-only SD identity checks:
- BOOT.BIN: 56db96f7530aa9cf4008d5494f1e1497d6fb6e76ece965d820b99b017e1539de
- boot.scr: f465658e33b26ad22bbfde35c2add09eaa782511161ffbf501c8096091565cb1
- bare-metal ELF: 8b275de051bfc9b9f9ed17520554bc7e3029e23a059be3728c235904640429ea
- baremetal.once absent.

Normal Linux reboot reached U-Boot 2025.01-ga09d2660433d at EL2.
Live bdinfo reported relocaddr=0x7fd6d000 and reloc_off=0x77d6d000.
The historical fault address 0x7bd02a90 currently contains data, not identified
U-Boot instructions. Do not infer its historical mapping from this boot.

Loading ELF with autostart=no succeeded. Memory at 0x100940 matched the
candidate shim disassembly; _boot is 0x100980.

A RAM-only register diagnostic was loaded at 0x02000000 using mw.l and entered
with go. Its first MRS CurrentEL returned 4 (EL1). Its subsequent MRS HCR_EL2
faulted at 0x0200000c, ESR 0x02000000, as an EL2-only register is inaccessible
at EL1. U-Boot printed Please RESET the board. A physical reset was requested.
No boot files, environment persistence, or one-shot marker were changed.

This proves go enters this diagnostic at EL1; it does NOT prove bootelf enters
at EL1. Local source corroboration (not exact board revision):
.build/u-boot-xlnx-task2g at cb52646e468c5d4ab73672b003dbdeb7f859275e,
board/xilinx/zynqmp/zynqmp.c do_go_exec calls dcache_disable and
armv8_switch_to_el1. Its macro initializes CNTHCTL, CPTR, SCTLR, SP, VBAR,
and HCR. The current application shim initializes only HCR.RW, SPSR and ELR.

Next controlled experiment after recovery: load ELF with autostart=no and
enter verified _boot address with go, bypassing the EL2-only custom shim.
First restore/verify PL clock, reset and configuration if testing SPI.
This is an untested alternative, not a working handoff claim.

Raw evidence: initial_board_state.log and uart_session.log.
