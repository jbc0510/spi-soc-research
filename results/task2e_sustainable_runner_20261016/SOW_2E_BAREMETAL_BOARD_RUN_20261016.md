# Task 2e bare-metal board run — 16 October 2026

## Result

The ZCU102 booted the existing standalone AXI SPI benchmark from its SD card. It completed all 11 payload sizes with 1,000 verified transfers per size: **11,000 transfers, zero API errors, zero timeouts, and zero receive mismatches**. This is a successful physical bare-metal regression run. It is not the newly built 60-second sustained bare-metal runner, so Task 2e remains partial.

The raw UART capture is `baremetal_reboot_capture_20261016.raw.log` (SHA-256 `3d573481c2e6bed1d704aaaa8c9e653be538b57701c007f2ea162820d152bebf`). The parser `scripts/parse_task2e_baremetal_capture.py` checks the complete size sequence and zero-failure counters, then emits `baremetal_reboot_metrics_20261016.csv` and `linux_baremetal_rate_comparison_20261016.csv`.

## Hardware and software identity

- Target: ZCU102, booted standalone from the SD card.
- Boot image: `BOOT_AXI_RATIO2_SDTIRQ_PASS_20260930.BIN`, SHA-256 `fbfbdb3bef84037376c604183d2b7b484d073c1fb62c52cab844894ca0853cc7`.
- The copied image matched the local Bootgen artifact byte-for-byte. Its BIF includes FSBL, PMUFW, the PL bitstream, and the A53 standalone SPI test.
- The embedded PL bitstream SHA-256 is `90f93479dd47c505b8f9e4fe6f4f18e853f8923d081f4b2037401ed3cb46994a`; it matches `results/ratio2_j55_lvcmos33_20260929/spi_ratio2_j55_wrapper.bit`, the September 29 XSA implementation.
- The original Linux `BOOT.BIN` was preserved as `BOOT_linux_backup_20261013.bin`, SHA-256 `56db96f7530aa9cf4008d5494f1e1497d6fb6e76ece965d820b99b017e1539de`.
- The UART banner reports timer frequency 99,990,005 Hz, `IOPLL_CTRL=0x00015a00`, `PL0_REF_CTRL=0x01010f00`, and control readback `0x00000186`. The app does not report a measured SPI SCK frequency; controller clock, SPI serial clock, and CPU clock must remain distinct in comparisons.
- Before the boot switch, Linux reported kernel `6.12.10-xilinx`; networkd had no IPv4 lease. The Linux FPGA manager state was `unknown`, and no Xilinx AXI SPI platform device was bound.

## Measurements

The benchmark uses the 11 payloads 1, 8, 16, 64, 128, 256, 512, 1,024, 4,096, 16,384, and 65,536 bytes. Bare-metal reported mean per-transfer latency from `XTime_GetTime`. The comparison CSV derives a decimal-MB/s rate as `payload_bytes / mean_latency_us` and places it beside the median application payload rate from Linux's three 60-second runs at each size.

The rates are informative but **not an apples-to-apples performance result**: bare metal ran 1,000 transfers per size with the XSpi interrupt driver, while Linux ran sustained 60-second windows through spidev and included Linux syscall/thread effects. For example, the derived bare-metal rate is 0.1438 MB/s at 1 byte and 1.1916 MB/s at 65,536 bytes; Linux medians are 0.0578 and 1.4949 MB/s respectively. See the CSV for all points.

## Limitations and recovery

The application banner still says `hardware_validation=NOT_PERFORMED`, `topology=UNVERIFIED`, `clock_pair=UNRECONCILED`, and `sck_physical_hz=UNKNOWN`. Those are stale build-time metadata fields; the UART capture itself proves the benchmark executed and verified returned bytes, and the exact bitstream hash is established. The run did not measure SCK or independently record the J55 wiring during this session.

The SD card's `BOOT.BIN` currently contains the standalone image. The original Linux boot image remains on the same card under the verified backup name above. The workstation does not detect the SD card as a block device, so restoring Linux requires moving the card to the workstation reader (or another writable host) and copying the backup back to `BOOT.BIN`. Do not claim the board is back on Linux until its next Linux boot is observed.

## Next work

1. Restore the original Linux `BOOT.BIN` and confirm Linux boots.
2. Run the fixed 1,000-trial Linux executable on the same bitstream to build a matched per-transfer comparison against this bare-metal sweep.
3. Package and execute the sustainable bare-metal runner (11 sizes × 3 × 60 seconds) if Task 2e requires a sustained paired comparison.
4. Update the SOW tracker and evidence deck after the matched run; retain the present result as a successful standalone board regression.
