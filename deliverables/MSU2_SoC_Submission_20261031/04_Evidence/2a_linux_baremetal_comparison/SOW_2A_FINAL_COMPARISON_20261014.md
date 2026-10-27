# MSU-2 Task 2a — Linux / bare-metal AXI SPI performance comparison

**Disposition:** The measured end-to-end comparison is complete for the
validated AXI Quad SPI/J55 loopback setup. The data quantifies the observed
Linux and bare-metal path differences across the SOW payload ladder. It does
not isolate a universal or causal “Linux kernel overhead” independent of the
driver, timer, and processor operating point.

## Requirement and test basis

The governing source is `MSU-2 SOW Final (1).docx` in the workstation Downloads
folder (SOW revision 2026-02-23). Task 2 calls for OS versus bare-metal SPI
analysis; its “Characterize Performance Gaps” activity calls for quantifying
Linux SPI-stack performance relative to direct hardware execution. The SOW
also requires a comparative benchmark framework, identical test patterns,
transaction latency, sustainable throughput, and CPU utilization. This report
closes the measured latency/performance-gap comparison; it does not claim the
whole Task 2 or every separate framework metric is complete.

Linux capture: `linux_benchmark_20261014.log` and
`linux_benchmark_20261014.csv`. Bare-metal capture:
`../axi_baremetal_validation_20261013/axi_ratio2_sdtirq_uart_20261013.log`,
extracted unchanged as `baremetal_baseline_extracted.csv`. Both used the shared
`common/spi_benchmark_contract.h`: 1, 8, 16, 64, 128, 256, 512, 1,024, 4,096,
16,384, and 65,536-byte payloads; 1,000 attempts per size; incrementing TX
pattern; poisoned RX buffer; and byte-for-byte receive comparison. Each run
completed 11,000 full-length transfers with zero API errors, timeouts, or RX
mismatches.

## Hardware and clock provenance

Both runs target the AXI Quad SPI at `0xA0000000`, with mode 0, 8-bit words,
one chip select, the same J55 external MOSI-to-MISO loopback, and the
hash-identified September 29 FPGA image:
`c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`.
The October Linux run records PL0 at 99.990 MHz and requests/readbacks
49.995 MHz. The October bare-metal run records the same IOPLL and PL0 register
values; the image configuration is SCK ratio 2.

The physical clock was previously measured on J55 pin 4 with this exact
bitstream and hardware configuration: approximately 51 MHz at a 50 MHz request.
That September 29 board-validation record also documents the pin map, external
jumper, and passing 1–65,536-byte loopback sweep with 1,000 attempts per size
and zero mismatches. Source: `../ratio2_j55_board_validation_20260929/ratio2_j55_lvcmos33_validation_20260929.txt`.
The pin measurement was not
simultaneous with the October timing captures; the matching bitstream hash,
XSA, PL0 setting, and ratio-2 configuration tie it to those runs. Thus the
October binary's `physical_sck_hz=UNKNOWN` header is stale template metadata,
not an unmeasured interface. No new pin measurement is needed for this result.

## Results

The detailed row-level comparison is `linux_vs_baremetal_comparison_20261014.csv`.
Mean API latency is the elapsed time around one complete transfer call: Linux
`SPI_IOC_MESSAGE(1)` versus bare-metal `XSpi_Transfer()` through interrupt
completion. Negative latency change means Linux was faster in that capture.

| Payload | Bare-metal mean | Linux mean | Linux change | Effective payload rate, BM → Linux |
|---:|---:|---:|---:|---:|
| 1 B | 6.922 µs | 28.031 µs | +304.98% | 0.144 → 0.036 MB/s |
| 8 B | 16.913 µs | 30.373 µs | +79.58% | 0.473 → 0.263 MB/s |
| 16 B | 28.318 µs | 33.492 µs | +18.27% | 0.565 → 0.478 MB/s |
| 64 B | 96.974 µs | 64.577 µs | −33.41% | 0.660 → 0.991 MB/s |
| 256 B | 371.533 µs | 189.646 µs | −48.96% | 0.689 → 1.350 MB/s |
| 1,024 B | 1.008 ms | 0.697 ms | −30.84% | 1.016 → 1.468 MB/s |
| 65,536 B | 54.350 ms | 43.287 ms | −20.36% | 1.206 → 1.514 MB/s |

Linux is slower for 1–16-byte transactions and faster from 64 bytes upward in
these runs. The crossover is between 16 and 64 bytes. The 65,536-byte Linux
mean is 11.063 ms lower (20.36%) than bare metal. “Effective payload rate” is
payload bytes divided by end-to-end API latency; it includes software and
transfer costs and is not wire throughput or the approximately 51 MHz SCK.

The CSV also carries minimum, maximum, standard deviation, and both error
counts for every payload. Linux standard deviation is much larger than the
bare-metal sample standard deviation; because timer sources and runtime paths
differ, those values describe observed run variability and are not a calibrated
cross-OS jitter ratio.

## Interpretation and limits

This comparison establishes the measured performance gap between the two
software paths on the same validated AXI hardware and external loopback. It
does not support a single percentage of overhead attributable solely to the
Linux kernel: the sign and size of the difference depend on payload length,
and the large-payload Linux result is faster in the captured run.

Linux timestamps use `CLOCK_MONOTONIC_RAW`; bare metal uses `XTime_GetTime`
converted with the BSP frequency of 99,990,005 Hz. Both are reported in
nanoseconds, but no independent cross-calibration of timer conversion and
measurement overhead was recorded. Linux's CPU policy was captured at
1,200,000 kHz under the userspace governor. The bare-metal capture does not
record an equivalent live A53 operating-point readback. These are limits on
causal attribution, not on transfer integrity: both runs passed the same RX
checks and use the same payload/trial contract.

The bare-metal raw log retains old template labels `hardware_validation=NOT_PERFORMED`,
`topology=UNVERIFIED`, and `clock_pair=UNRECONCILED`. The separate September
29 physical validation plus the October Linux runtime binding and successful
RX-verified sweep resolve the image/controller/topology for this comparison;
those stale template strings are not evidence that the October data was
synthetic or that J55 was not measured.

## Reproduction and integrity

From the repository root:

```sh
python3 scripts/compare_task2a_runs.py \
  --linux results/linux_axi_spi_bringup_20261013/linux_benchmark_20261014.csv \
  --baremetal results/linux_axi_spi_bringup_20261013/baremetal_baseline_extracted.csv \
  --output results/linux_axi_spi_bringup_20261013/linux_vs_baremetal_comparison_20261014.csv
```

The script requires all 11 sizes, 1,000 timing samples per size, and zero API
errors, timeouts, or receive mismatches before producing the comparison. It
computes the per-size mean-latency delta and ratio, standard-deviation ratio,
minimum/maximum values, and effective payload rates. Source and output hashes
are recorded in `artifact_hashes.sha256`; complete run metadata is in
`linux_build_manifest.json`.
