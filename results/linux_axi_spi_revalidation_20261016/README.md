# ZCU102 Linux AXI Quad SPI revalidation — 16 October 2026

## Outcome

Linux was restored on the ZCU102 and brought back to the validated September 29
AXI Quad SPI design. The controller bound to `xilinx_spi`, `/dev/spidev1.0` was
created, a one-byte J55 loopback smoke test returned the transmitted byte, and
the fixed-trial test completed all 11,000 transfers with no observed transfer
or data-integrity failures.

This is a matched-workload Linux-versus-bare-metal comparison on the same
payload sizes and trial counts. It is not a strict apples-to-apples CPU or
timer comparison: Linux measured with `CLOCK_MONOTONIC_RAW`; bare metal used
`XTime_GetTime`, and the bare-metal CPU frequency was not captured. These
measurements describe the tested board and software paths, not a universal
kernel overhead.

## Hardware and software identity

- Board: AMD ZCU102; Linux hostname `newQspi`.
- Linux boot image restored from the SD-card backup; `BOOT.BIN` SHA-256:
  `56db96f7530aa9cf4008d5494f1e1497d6fb6e76ece965d820b99b017e1539de`.
- Kernel: `6.12.10-xilinx-g0a0f70e531c7`, PetaLinux
  `2025.1+release-S05180137`.
- Authoritative XSA:
  `results/ratio2_j55_lvcmos33_20260929/spi_ratio2_j55_wrapper.xsa`, SHA-256
  `e8b4626edb5949bc8adb14ae259802cdd24b16ea3f02daf0dd8fdbeb1cc0e7d7`.
- FPGA image from the mounted SD card and the Linux firmware copy both matched
  SHA-256 `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`.
  Linux FPGA Manager reported `operating` after programming. The manager does
  not provide a bitstream readback hash, so this identity is established from
  the source file staged for programming plus manager state.
- XSA path: `M_AXI_HPM0_FPD` → SmartConnect → AXI Quad SPI at
  `0xA0000000–0xA000FFFF`; PS clock PL0; J55 external MOSI-to-MISO loopback.
- Clock framework after setup: IOPLL `1,499,850,000 Hz`; PL0
  `99,990,000 Hz`, enable count 1. The PL0 overlay set the branch rate and did
  not change the shared IOPLL rate.
- Current Linux CPU policy: `userspace`, `cpuinfo_cur_freq=1,200,000 kHz`,
  `cpuinfo_max_freq=1,200,000 kHz`. The SPI request and kernel readback were
  `49,995,000 Hz`; this is a controller request/readback, not a fresh physical
  SCK measurement. J55 SCK was previously measured at approximately 51 MHz
  with this exact FPGA image and ratio-2 configuration; it was not remeasured
  during this run.
- `spidev.bufsiz=1048576`; CPU governor and frequency were left unchanged.

## Linux setup and evidence

The target started with FPGA Manager state `unknown`, PL0 at `249,975,000 Hz`,
no PL SPI device, and no active device-tree overlays. No AXI read was made in
that state. Setup proceeded in this order:

1. Apply the PL0 clock-only overlay and verify 99.990 MHz, enable count 1, and
   unchanged 1.49985 GHz IOPLL.
2. Program the SHA-verified September 29 image through Linux FPGA Manager and
   verify manager state `operating`.
3. Apply the reset-release overlay. Linux GPIO debug showed EMIO95 as GPIO
   line 689, `msu2-pl-resetn0`, `out hi`. This verifies the requested GPIO
   state, not the voltage on the physical reset net.
4. Apply the AXI SPI overlay. The `a0000000.spi` platform device bound to
   `xilinx_spi`; the SPI child registered as `spi1.0`.
5. Set `driver_override=spidev` and bind `spi1.0` to `spidev`; the overlay's
   placeholder child compatible does not auto-bind spidev on this kernel.
   This produced `/dev/spidev1.0`. The probe and transfers then completed
   without a kernel stall.

Host-compiled overlays were reproduced on the target with its device-tree
compiler and byte-for-byte hash matched:

| Overlay | SHA-256 |
|---|---|
| `pl0-clock-only.dtbo` | `00d3bd63dd926a41c3e8581c8d4ee8abb3e94307ad7e4ba345e500e45bb1bffa` |
| `pl-reset-release.dtbo` | `6ae01a4bddea4fe225e2fdee6c5da48df70ce68df7be14328326d7066a171255` |
| `axi-spi-controller.dtbo` | `92416746eaba51248438fdca8be324ef2a0455ccb2caa64da74d75df96bee693` |

The one-byte smoke result was mode 0, 8 bits, 1 MHz requested/read back,
`TX=a5`, `RX=a5`, `ioctl_rc=1`, `errno=0`, and 57,096 ns around the ioctl.
This verifies a real spidev transfer and matching receive data. The board's
J55 external loopback was the intended path; the test program itself does not
measure the wires.

## Fixed-trial results

The Linux benchmark used the same 11 payload sizes and 1,000 transfers per
size as the 16 October bare-metal board regression. All rows recorded 1,000
full-length timed successes and zero API errors, `ETIMEDOUT` errors, receive
mismatches, short returns, or timer errors (11,000 verified transfers total).
The executable reports kernel `6.12.10-xilinx-g0a0f70e531c7`, mode 0, 8 bits,
and `49,995,000 Hz` requested/read back. Timing uses
`CLOCK_MONOTONIC_RAW`; target wall-clock time is not used.

| Payload | Bare-metal mean | Linux mean | Linux change | Linux derived rate |
|---:|---:|---:|---:|---:|
| 1 B | 6.952 µs | 25.248 µs | +263.2% | 0.0396 MB/s |
| 16 B | 28.332 µs | 33.501 µs | +18.2% | 0.4776 MB/s |
| 64 B | 96.985 µs | 64.637 µs | −33.4% | 0.9901 MB/s |
| 1 KiB | 1,016.031 µs | 705.413 µs | −30.6% | 1.4516 MB/s |
| 64 KiB | 55,000.611 µs | 43,805.494 µs | −20.4% | 1.4961 MB/s |

Derived MB/s uses `payload_bytes / mean_latency` and is not wire throughput.
The comparison CSV includes all 11 sizes and latency ranges and standard
deviations. The result is consistent with the earlier Linux run: Linux was
slower for 1–16-byte messages and faster from 64 bytes upward in this
measurement. Timer sources and captured CPU conditions still limit causal
interpretation.

## Reproduction and files

The tested Linux executable was built from
`linux/src/spi_benchmark_v3_rxverify.c` using the AMD AArch64 GCC toolchain;
its SHA-256 is `d4e0e6b747789eb44e9013397e8956703ab41d8b78800e18d5586e72e5037c85`.
The target command was:

```sh
/tmp/spi_benchmark_v3_rxverify_aarch64 /dev/spidev1.0 49995000
```

The target output was saved to
`/tmp/linux_axi_spi_1000trial_20261016.log`, then captured over UART. The
host-side extracted evidence is:

- `linux_fixed_trial_20261016.log` — run header, CSV, loop metrics, and exit
  status.
- `linux_fixed_trial_20261016.csv` — the 11 validated Linux result rows.
- `linux_vs_baremetal_fixed_trial_20261016.csv` — paired Linux and bare-metal
  statistics, produced by `scripts/compare_task2a_runs.py`.
- `target_console_20261016.raw.log` — preserved full UART capture, including
  Linux boot, setup, smoke, and run output.
- `scripts/extract_linux_spi_capture.py` — extracts and validates the latest
  fixed-trial sweep from the UART capture.

Re-extract and compare with:

```sh
python3 scripts/extract_linux_spi_capture.py \
  results/linux_axi_spi_revalidation_20261016/target_console_20261016.raw.log \
  results/linux_axi_spi_revalidation_20261016/linux_fixed_trial_20261016
python3 scripts/compare_task2a_runs.py \
  --linux results/linux_axi_spi_revalidation_20261016/linux_fixed_trial_20261016.csv \
  --baremetal results/task2e_sustainable_runner_20261016/baremetal_reboot_metrics_20261016.csv \
  --output results/linux_axi_spi_revalidation_20261016/linux_vs_baremetal_fixed_trial_20261016.csv
```

## Remaining limitations

- The run verifies basic Linux AXI SPI operation and a fixed-trial comparison;
  it does not complete every Task 2 objective or replace the sustainable
  3×60-second paired comparison requested for Task 2e.
- The bitstream manager state is not a hardware readback hash; the physical
  J55 SCK value was not remeasured in this session.
- The reset GPIO state was confirmed in Linux debugfs, but the external reset
  net voltage was not measured.
- The fixed-trial benchmark has no userspace per-transfer deadline; its
  `timeout_count` only counts `ETIMEDOUT` API errors. The completed run had no
  errors or stalls.
- Bare-metal CPU frequency was not recorded, and Linux and bare-metal timer
  methods differ. Treat the comparison as measured end-to-end software paths
  under aligned board, interface, payload, trial-count, and clock settings.
