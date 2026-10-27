# Task 2e bare-metal board run — 16 October 2026

## Result

The ZCU102 booted the existing standalone AXI SPI benchmark from its SD card. It completed all 11 payload sizes with 1,000 verified transfers per size: **11,000 transfers, zero API errors, zero timeouts, and zero receive mismatches**. This is the fixed-ladder bare-metal regression, one part of the complete Task 2e framework evidence. The paired 60-second sustained result is recorded below and in `SOW_2E_PAIRED_SUSTAINED_RESULTS_20261017.md`.

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

At the time of this fixed-ladder run, the SD card's `BOOT.BIN` contained the standalone image and the original Linux boot image was preserved on the card under the verified backup name above. This report does not make a claim about the board's present boot state.

## Next work

The fixed-trial and sustained Linux-versus-bare-metal comparisons are now captured. This report retains the fixed-ladder run as one evidence component; the complete bounded Task 2e result and clock interpretation are in the paired report and `clock_readback_20261017.md`.

## Follow-up recorded 17 October 2026

The newly built 60-second bare-metal runner subsequently completed all 11 payload sizes × 3 repetitions (33 points) on the ZCU102, with zero API errors or RX mismatches. Raw and derived evidence, paired Linux rates, clock/operating-point readback, and interpretation limits are documented in `SOW_2E_PAIRED_SUSTAINED_RESULTS_20261017.md`, `clock_readback_20261017.md`, and `paired_sustained_manifest_20261017.json`. These results close the fixed-trial and sustained-comparison portions of Task 2e. The full Task 2e item remains open pending the clock/payload stress test that measures the reliable operating envelope. Per-window clock sampling and alternating backend order were not performed.
