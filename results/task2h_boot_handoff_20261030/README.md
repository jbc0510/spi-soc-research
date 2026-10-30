# 2026-10-30 operator investigation

Hardware evidence supplied by operator in this session:

- Linux integrity: all 11 shared payloads, 1,000 trials each, zero API errors
  and zero RX mismatches. Mode 0, 8-bit, spi_loop_requested=0. Evidence on
  card: msu2-demo-results/20261030T173053Z_integrity.
- Linux nonzero smoke: tx=a5 rx=a5, ioctl_rc=1. Evidence on card:
  msu2-demo-results/20261030T173927Z_smoke.
- Original bare-metal: 8,16,64,128,256-byte rows each have 1,000 mismatches,
  first offset=1 expected=1 actual=0. These rows establish only the first
  mismatching byte, not the contents of the entire RX buffer.

Candidate fifo_candidate_v2 is BUILD ONLY, NOT HARDWARE VALIDATED.
It explicitly clears FIFO reset before loading, limits each TX batch to 256
bytes, drains that batch before refilling while retaining slave select, and
checks the whole-transfer deadline even while RX is available. Integrity
returns on the first timeout rather than repeating it 1,000 times. A comment
line dumps the first eight-byte integrity transfer for diagnosis. SPI mode,
bit order and external loopback selection remain unchanged (CR bit0 clear).

The original 20261029 offline build directory is unavailable on this host.
The candidate uses the local generated SDT AXI BSP under
bare_metal/vitis/spi_bm_axi_wjfmpg_2 and the local 2025.1 AArch64 toolchain.
Its xparameters specifies base 0xa0000000, 8 bits, 256 FIFO entries, one CS,
standard SPI, interrupt 89. Build command and hashes are in build_inputs.json.
objdump confirms entry 0x00100940. Compiler warns that the existing naked
attribute is ignored and noreturn function returns; entry assembly is unchanged.
BOOT.BIN and boot.scr are not modified.

Next operator check: option 1, capture first_transfer diagnostic and eight-byte
row, then exercise options 2,3,4,q after RX is clean. No menu option on this
candidate has yet been confirmed on hardware.
