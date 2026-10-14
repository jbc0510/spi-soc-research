# Linux AXI SPI bring-up and verification (October 13–14, 2026)

## Result

Linux AXI Quad SPI is operational on the ZCU102 using the hash-matched September
29 FPGA image. PL0 is enabled at the CCF-reported 99.99 MHz; the EMIO95
`pl_resetn0` output is enabled and driven high through a kernel GPIO hog; the
Xilinx SPI platform driver and spidev child are bound. A one-byte J55 loopback
smoke test passed, followed by 11,000 full-length transfers across the same 11
payload sizes and 1,000 trials per size as the bare-metal baseline. Both runs
reported zero receive mismatches and zero timeouts.

This completes the Linux transfer and benchmark portion of the investigation.
It does not claim all MSU-2 Task 2a–2f acceptance criteria: the primary
Statement of Work was not in the repository, physical SCK was not measured,
failure/recovery behavior was not exercised, and operating conditions do not
support a controlled OS-only performance comparison. The earlier hang's root
cause remains unconfirmed.

## Hardware and software identity

- Repository branch: `feature/ratio2-j55-rebuild`; starting commit recorded
  below. The three preexisting untracked `sd-images/baremetal/axi_ratio2*`
  directories were preserved.
- Authoritative XSA: `results/ratio2_j55_lvcmos33_20260929/spi_ratio2_j55_wrapper.xsa`,
  SHA-256 `e8b4626edb5949bc8adb14ae259802cdd24b16ea3f02daf0dd8fdbeb1cc0e7d7`.
- FPGA image: `spi_ratio2_j55_wrapper.bit.bin`, SHA-256
  `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`.
  Repository and SD-card files matched. The FPGA manager reported `operating`
  after programming; there is no bitstream readback identity check.
- XSA path: HPM0 FPD -> SmartConnect -> AXI Quad SPI at `0xA0000000–0xA000FFFF`.
  PL0 clocks the path at XSA metadata rate 99.990005 MHz. SPI is master,
  8-bit, one chip-select, FIFO depth 256, SCK ratio 2, with interrupt routed
  through `pl_ps_irq0[0]`. See `xsa_audit.txt` for extracted metadata.
- Target: `newQspi`, kernel `6.12.10-xilinx-g0a0f70e531c7`. Controller
  `a0000000.spi` bound to `xilinx_spi`; master `spi1`, child `spi1.0`, IRQ 60;
  child bound to `spidev` as `/dev/spidev1.0`.
- Runtime clocks: IOPLL 1,499,850,000 Hz; PL0 CCF 99,990,000 Hz. CPU policy
  1,200,000 kHz with `userspace` governor. The SPI request/readback was
  49,995,000 Hz for the benchmark. Physical SCK is unknown; requested speed,
  driver readback, and CCF rates are not pin measurements.
- Kernel reported boot arguments include `spidev.bufsiz=1048576`, sufficient
  for 65,536-byte payloads. Full console chronology and raw diagnostics are in
  `target_console.log`.

## Reset and earlier failure investigation

The XSA connects active-low `pl_resetn0` through `proc_sys_reset` to both the
SmartConnect and SPI peripheral resets. AMD 2025.1 sources map the XSA's GPIO
Bank 5 bit 31 to EMIO95 / firmware reset ID 1119 (DT reset index 119). The
running Linux GPIO driver requires both DIRM and OEN for an output. After the
hash-matched FPGA load, read-only evidence showed DIRM bit 31 set while OEN bit
31 was clear. A configfs overlay then claimed EMIO95 with a kernel-managed
output-high GPIO hog; debugfs showed `out hi` and OEN bit 31 set. This matches
the generated XSA reset initialization intent, but the physical reset net was
not measured. The GPIO input readback and firmware reset-status calls are not
proof of that net's voltage.

The Linux PL0 clock overlay set the rate through CCF clock 71 without changing
the shared IOPLL rate; the complete before/after clock summary showed only the
PL0 branch and its IOPLL enable reference changed. The FPGA image was then
programmed via FPGA Manager, the reset output was released, and the SPI driver
probe plus transfers succeeded. This sequence resolves the immediate
operational blockage but does not isolate which prior condition caused hangs.
Earlier direct MMIO and SPI probe attempts happened before prerequisites were
established; they were not repeated under the final sequence. The board was
responsive after the final tests.

The following overlays remain active on the board: PL0 clock, reset GPIO hog,
and AXI SPI controller, with spidev bound. No SD boot files or workstation boot
configuration were modified. `pl0-clock-only.dts`, `pl-reset-release.dts`,
and `axi-spi-controller.dts` plus their compiled DTBOs document the applied
configuration. Overlay application order and captured observations are in
`target_console.log`.

## Transfer verification and comparison

`linux_spi_smoke_20261014.log` records the single-transfer test: mode 0,
8 bits, 1 MHz requested/read back, TX `a5`, RX `a5`, one-byte ioctl success,
57,806 ns measured around the ioctl using `CLOCK_MONOTONIC_RAW`.

`linux_benchmark_20261014.log` is the captured target output and
`linux_benchmark_20261014.csv` contains 11 rows. The run used
`CLOCK_MONOTONIC_RAW`; all 11,000 full-length API operations succeeded and
matched the poisoned receive buffers, with zero errors, timeouts, short
returns, or mismatches. Per-size latency statistics are in the CSV and log.
The target clock's wall time was wrong and was not used for dates or timing.

The bare-metal rows in `baremetal_baseline_extracted.csv` were extracted
without changing values from
`results/axi_baremetal_validation_20261013/axi_ratio2_sdtirq_uart_20261013.log`.
That log also reports 11 sizes × 1,000 trials with zero mismatches/timeouts,
but its own metadata labels topology unverified. The comparison CSV aligns
payload sizes and trial counts; it is exploratory because bare metal uses
`XTime_GetTime` and Linux uses `CLOCK_MONOTONIC_RAW`, processor points are not
confirmed matched, and physical SCK is unknown. At 65,536 bytes, mean API
latency was 54.350 ms bare metal and 43.287 ms Linux; one-byte means were
6.922 μs and 28.031 μs. Derived effective payload rates at 65,536 bytes were
1.206 and 1.514 MB/s respectively. These include software and transfer costs
and are not measured wire throughput.

## Reproduction

The binaries were built with AMD AArch64 Linux GCC 13.3.0 using
`-std=c11 -O2 -Wall -Wextra -Werror` (benchmark also uses `-Icommon -lm`).
Set `AARCH64_GCC` to that compiler, then run from the repository root:

```sh
"$AARCH64_GCC" -std=c11 -O2 -Wall -Wextra -Werror -Icommon \
  linux/src/spi_benchmark_v3_rxverify.c -lm \
  -o results/linux_axi_spi_bringup_20261013/spi_benchmark_v3_rxverify_aarch64
"$AARCH64_GCC" -std=c11 -O2 -Wall -Wextra -Werror \
  results/linux_axi_spi_bringup_20261013/linux_spi_smoke.c \
  -o results/linux_axi_spi_bringup_20261013/linux_spi_smoke_aarch64
```

Run only with the validated bitstream, PL0 clock, reset and controller
configuration in place. The benchmark source documents its arguments and
CSV output; the actual run's exact commands and environment appear in the raw
console log. The target binaries' hashes were verified after transfer and are
recorded with the logs, CSVs, source files and XSA artifacts in
`artifact_hashes.sha256`; `linux_build_manifest.json` records the machine
readable run metadata.

## Remaining Task 2 evidence

The transfer-integrity and repeatable Linux benchmark criteria are supported
by the attached evidence. To close the broader Task 2a–2f scope, compare this
report with the authoritative SoW acceptance criteria, measure SCK and any
other relevant board signals with suitable instrumentation, run failure and
recovery cases, and repeat the comparison with matched operating conditions
if a controlled Linux-versus-bare-metal performance conclusion is required.
