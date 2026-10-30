---
name: task2h-board-ops
description: How to drive the ZCU102 board over UART for the task2h handoff debugging
metadata: 
  node_type: memory
  type: reference
  originSessionId: 2ca6d9fb-76b2-4b09-878e-5e8d039d2474
---

ZCU102 live-debug setup for the Linux↔bare-metal handoff:
- Console UART: CP2108 interface 0 = /dev/ttyUSB0, 115200 8N1. Host user `opentitan`
  is in `dialout`, so can open ttyUSB0 (port is root:dialout).
- Bare-metal console UART base = UART0 0xFF000000 (STDOUT_BASEADDRESS); TX FIFO @ +0x30,
  channel status @ +0x2C (TXFULL=bit4).
- U-Boot prompt is `ZynqMP> `; autoboot banner `Hit any key to stop autoboot:` (~5s window).
  U-Boot runs at EL2; link base 0x08000000 (relocaddr − reloc_off = 0x7fd6d000 − 0x77d6d000).
- The today (root-owned) dir results/task2h_boot_handoff_20261029/ is NOT writable by
  `opentitan`; log live UART to scratchpad instead.
- SD state is safe to leave: BOOT.BIN = Linux (sha 56db96f7...), boot.scr = handoff variant,
  rollback boot.scr.pre_msu2_handoff_20261017 present, msu2_demo/baremetal.once ABSENT
  (so normal Linux boot, no auto bare-metal launch). bare-metal ELF on FAT sha 8b275de0...
- Reversible test pattern: reboot from Linux root shell, spam a key to break autoboot,
  `mw.l` a stub into RAM, `go <addr>`. Writes nothing to the card.
- Gotcha: a spinning (wfe) stub HANGS the board — needs a physical reset-button tap to
  recover (no software path back once spinning at EL1 with IRQs masked). Watchdog is not
  armed in this flow. Consider ending test stubs with PSCI SYSTEM_RESET (x0=0x84000009, smc #0)
  instead of spin for auto-recovery. See [[task2h-handoff-root-cause]].
