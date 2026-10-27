# MSU-2 one-stop Linux demo progress

**Date:** 2026-10-17  
**Status:** The no-Python operator menu and its bring-up, smoke, integrity,
sustained-test, system-information, and return-to-shell paths were exercised on
the ZCU102. All captured transfers passed. Raw run files are currently on the
board's SD card and still need to be copied into the repository for archival.

## Confirmed on the ZCU102

The SD card's active Linux boot image was restored to the verified
`BOOT_linux_backup_20261013.bin` image, SHA-256
`56db96f7530aa9cf4008d5494f1e1497d6fb6e76ece965d820b99b017e1539de`. The
board booted PetaLinux 2025.1, kernel `6.12.10-xilinx-g0a0f70e531c7`.

After a clean boot, the FPGA was initially unconfigured (`fpga_manager=unknown`),
PL0 was disabled at the boot-time rate of 249.975 MHz, no PL overlays were
present, and no spidev node existed. This is expected because the runtime PL
configuration is volatile.

The previously validated runtime sequence was repeated:

1. Applied the clock overlay. Linux clock framework reported PL0 at
   `99,990,000 Hz`, enable count 1.
2. Verified the on-card September 29 bitstream SHA-256 as
   `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`, then
   loaded it. FPGA Manager reported `operating`.
3. Applied the PL reset GPIO hog. Debug GPIO reported EMIO95 / line
   `msu2-pl-resetn0` as `out hi`.
4. Applied the AXI SPI device-tree overlay. Linux created `spi1.0`; binding its
   child to `spidev` created `/dev/spidev1.0`.
5. Ran the menu-driven smoke executable. It transmitted `0xa5`, received
   `0xa5`, returned `ioctl_rc=1`, and reported `errno=0` in 53,726 ns.

The menu then ran an 11-payload-size RX integrity/latency sweep at 1,000 trials
per size. All 11,000 calls returned the full requested length; API errors,
timeouts, short returns, and RX mismatches were all zero. Average ioctl latency
ranged from 27.5 us at 1 byte to 43.28 ms at 64 KiB. The target program labels
the external loopback topology unverified and physical SCK unknown, so these
are application-path timing results rather than a verified electrical or wire
rate measurement.

A configurable sustained run was also completed with 256 B, 4 KiB, and 64 KiB
payloads, 10 seconds per size, one repetition, and the program's requested
15,623,438 Hz SPI setting. All 55,937 transfers (52,085 + 3,623 + 229) were
verified with zero API errors and zero mismatches. Application throughput was
1.333, 1.484, and 1.495 MB/s, respectively. Thread CPU share was 32.88%,
3.58%, and 1.47%. The physical SCK remained unmeasured; do not interpret the
requested setting as an independently verified pin frequency. This 30-second
run is a menu-path demonstration and not a substitute for the full-duration,
repeated benchmark used in the comparative baseline.

Menu option 5 reported kernel `6.12.10-xilinx-g0a0f70e531c7`, CPU0 at
1.2 GHz, FPGA Manager `operating`, PL0 at 99.99 MHz, and `/dev/spidev1.0`
present. The on-card bitstream source file hash matched the validated artifact;
the FPGA was not read back for a bitstream hash. Finally, `q` returned to the
ordinary PetaLinux shell. This confirms the operator menu is optional after
Linux login and normal OS control remains available.

The target generated run-directory names beginning `20250108T...` because the
board's reported wall clock was in January 2025. Preserve those names as emitted
and record the workstation session date separately; do not treat the target
timestamp as the actual experiment date.

The boot log also reported that Linux could not create the PS Cadence SPI flash
child at `/axi/spi@ff0f0000/flash@0` because its modalias was missing. This is
the PS SPI flash node, not the AXI Quad SPI controller at `0xA0000000`; it did
not prevent Linux boot or the AXI SPI smoke transfer.

## Operator menu package

PetaLinux's minimal image has no `python3`, so the existing Python menu cannot
run there. A POSIX shell menu now provides explicit choices for validated AXI
bring-up, one-byte smoke, the RX-verifying integrity sweep, sustained throughput
with selected payloads/duration/repetitions, system information, or return to
the normal Linux shell. Tests are never started automatically. Each run writes
a separate log and manifest beside the package on the boot partition. Hardware
bring-up applies clock, programs the hash-checked bitstream, releases reset,
registers the AXI SPI controller, and binds spidev in that order.

The host package builder is `scripts/package_msu2_demo_bundle.py`. It refuses to
overwrite an existing output directory and checks pinned hashes for the
bitstream, the three overlays, and the three Linux executables. The package
includes `PACKAGE_MANIFEST.json` and `SHA256SUMS`.

Host checks run so far:

- `dash -n linux/appliance/msu2_demo.sh` and `sh -n ...`: pass.
- `dash linux/appliance/msu2_demo.sh --self-test`: pass for accepted/rejected
  payload sizes. This does not access target hardware.
- `python3 scripts/package_msu2_demo_bundle.py --out results/msu2_linux_demo_bundle_20261017_v3`:
  pass; all package input hash pins matched.
- `sha256sum -c SHA256SUMS` in the generated bundle: all nine files passed.
- Copied the package to the SD card's new `msu2_demo/` directory. All nine
  hashes passed again on the card; active `BOOT.BIN` remained at the known-good
  Linux hash. The card was cleanly unmounted after copying.

## Open items

- Copy the on-card `msu2_demo/msu2-demo-results/` run directories to the
  repository, verify hashes, and append the raw console capture before treating
  the target logs as archived evidence.
- Repeated, longer sustained windows remain necessary for a reproducible
  comparison; today's short run confirms that operator-selected parameters and
  the logging path work.
- Measure actual J55 SCK with the scope or logic analyzer and photograph or
  log the probe setup. The userspace tool cannot infer actual SCK from
  `SPI_IOC_RD_MAX_SPEED_HZ` on this AXI controller.
- The menu starts after Linux login. It is not a pre-OS Linux-versus-bare-metal
  chooser. The attempted custom U-Boot selector did not reach a U-Boot banner;
  the boot-chain cause remains unresolved.
- FIT payload signature tests do not make the FSBL/U-Boot chain authenticated.
  Do not describe this prototype as secure boot.
- No new measurement of J55 physical SCK was made in this session. The program
  labels it unmeasured rather than inferring it from the requested speed.

## Evidence generated on target

- Smoke: `msu2-demo-results/20250108T182507Z_smoke`
- Integrity: `msu2-demo-results/20250108T182533Z_integrity`
- Sustained 256 B: `msu2-demo-results/20250108T182942Z_sustained_256B_rep1`
- Sustained 4 KiB: `msu2-demo-results/20250108T182952Z_sustained_4096B_rep1`
- Sustained 64 KiB: `msu2-demo-results/20250108T183002Z_sustained_65536B_rep1`

The console also showed a successful `q` return to `newQspi:~$`. Once the SD
card is back on the host, archive the five run directories and the complete
serial capture, then generate the final comparison figures from raw CSV data.
