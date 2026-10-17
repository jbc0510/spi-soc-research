# Linux AXI SPI runtime re-bring-up — 2026-10-17

## Outcome

The ZCU102 Linux AXI Quad SPI path was brought up again using the validated
September 29 FPGA image. The confirmed sequence was: enable PL0 at 99.99 MHz,
program the validated bitstream, release the active-low fabric reset through
the saved EMIO95 GPIO overlay, add the hash-verified AXI SPI device-tree
overlay, bind its child to `spidev`, then run the RX-verifying one-byte smoke
test. The transfer succeeded with TX `0xa5`, RX `0xa5`, and ioctl return 1.

This is a successful live Linux SPI data-integrity smoke test on the ZCU102.
It is not a new multi-payload benchmark and does not close all SoW Task 2
criteria.

## Configuration evidence

- Kernel: Linux `6.12.10-xilinx-g0a0f70e531c7` (PetaLinux 2025.1).
- Validated bitstream: `spi_ratio2_j55_lvcmos33_20260929.bit.bin`, SHA-256
  `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`.
- FPGA Manager reported `operating` after `fpgautil -f Full` completed in
  199 ms.
- Clock-only overlay SHA-256:
  `00d3bd63dd926a41c3e8581c8d4ee8abb3e94307ad7e4ba345e500e45bb1bffa`.
- Clock framework readbacks: IOPLL `1,499,850,000 Hz`; PL0
  `99,990,000 Hz`; PL0 enable count `1`.
- Reset overlay SHA-256:
  `6ae01a4bddea4fe225e2fdee6c5da48df70ce68df7be14328326d7066a171255`.
  Kernel GPIO debug showed GPIO 689 `msu2-pl-resetn0` as `out hi`.
- AXI SPI overlay SHA-256:
  `92416746eaba51248438fdca8be324ef2a0455ccb2caa64da74d75df96bee693`.
  Overlay applied; Linux created `spi1.0`. `spidev` was bound using the
  device's `driver_override`; `/dev/spidev1.0` appeared.
- Smoke executable SHA-256 on both host and SD card:
  `fb01baec3d451849bd147837491f0d63b62efd0e1a1f99389314d407582b8dcd`.

## Test result

`linux_spi_smoke_aarch64 /dev/spidev1.0` configured SPI mode 0, 8 bits per
word, and requested/read-back speed 1 MHz. It transmitted one byte (`0xa5`),
received `0xa5`, returned `ioctl_rc=1`, and reported `errno=0`. The measured
single-call duration was 47,655 ns. This demonstrates one successful Linux
full-duplex exchange and exact byte match. It does not establish the physical
SCK rate; the reported speed is a driver readback. The previously documented
J55 physical SCK measurement remains the applicable bench measurement for the
validated hardware configuration.

## Probe failure and interpretation

On the first post-card-swap boot, the clock and reset overlays were applied,
but the volatile FPGA fabric was not reprogrammed before the AXI SPI overlay
was applied. The Linux kernel then reported RCU stalls during the SPI driver
probe. A board reset recovered Linux. After reboot, the same device-tree
overlay was applied only after confirming the validated bitstream was loaded
and FPGA Manager reported `operating`; this time the overlay applied and
`spi1.0` appeared without an RCU stall. This A/B sequence is consistent with
probing an unconfigured PL fabric causing the stall. The root cause is not
proven to be exclusive because reset/reboot state also changed between runs.

The successful sequence must always program the bitstream before registering
the AXI SPI controller. FPGA fabric configuration and configfs overlays are
volatile and must be restored after a board reset or power cycle.

## Benchmark limitation and next work

The SD card's older `spi_loopback_test` binary completed its 1-byte through
1-MiB timing sweep, but its source only checks transfer API errors; it never
compares received data with transmitted data. It then failed at 4 MiB with
`Message too long`, consistent with the kernel's configured 1-MiB spidev
buffer. Its output also contains an obsolete 6.25-MHz SCK note, so it is not
used as current clock evidence. The proper RX-verification benchmark binary
was not present on the card. A new multi-payload verified benchmark remains
to be staged and run; no new benchmark result is claimed here.

The exact target command output was supplied through the live serial session
and is summarized above. The workstation did not have the serial device
exposed in this agent session, and the Ethernet link-local ping was
unreachable, so an independent raw console capture could not be collected.
