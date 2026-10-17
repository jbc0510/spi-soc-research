# Task 2e clock readback and clock evidence

Read-only XSCT/JTAG register snapshot collected after the sustained bare-metal runner completed, on 17 October 2026. No PS or PL register was written. Cortex-A53 #0 was reported Running. The AXI SPI register read was rejected by the XSCT memory map (`PL AXI slave ports access is not allowed`); no AXI SPI transaction was issued in this check.

| Register | Address | Readback | Interpretation |
|---|---:|---:|---|
| APLL_CTRL | `0xFD1A0020` | `0x00014800` | APLL feedback divisor 72, divide-by-2 enabled |
| ACPU_CTRL | `0xFD1A0060` | `0x03000100` | ACPU source APLL, divisor 1, full and half clocks active |
| IOPLL_CTRL | `0xFF5E0020` | `0x00015A00` | IOPLL feedback divisor 90, divide-by-2 enabled |
| PL0_REF_CTRL | `0xFF5E00C0` | `0x01010F00` | PL0 source IOPLL, divisor 15, clock active |

The board clock reference is 33.330 MHz, as recorded in the target Linux clock-tree capture (`results/linux_axi_spi_bringup_20261013/target_console.log`). Applying the Zynq UltraScale+ clock-divider definitions in AMD UG1085/UG1087 gives a register-derived A53 full-rate clock of 1.19988 GHz (72 × 33.330 MHz / 1) and PL0 of 99.990 MHz (90 × 33.330 MHz / 15). This agrees with the Linux preflight's 1.2 GHz userspace CPU point and 99.990 MHz PL0 readout. Register-derived values are not oscilloscope measurements.

The same validated ratio-2 bitstream and PL0 setting were used in the 29 September hardware validation; that report records a physical J55 pin 4 SCK measurement of approximately 51 MHz and the image SHA-256 `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd` (`results/ratio2_j55_board_validation_20260929/ratio2_j55_lvcmos33_validation_20260929.txt`). The Linux run set requested/read back 49.995 MHz through spidev. J55 SCK was not remeasured during the October sustained windows; therefore, 51 MHz is matching-configuration historical physical evidence, not a simultaneous SCK measurement.

The bare-metal benchmark contains no clock-programming operation; its observed IOPLL/PL0 readbacks also appear in the immediately preceding physical fixed-ladder run (`baremetal_reboot_capture_20261016.raw.log`). This supports the sustained-run configuration association. It cannot prove that clocks remained invariant at every point, and the sustained UART capture began after its startup banner. The BM A53 frequency is derived from the post-run readback, not sampled by the runner during each 60-second interval. The Linux CPU governor and 1.2 GHz frequency were captured before its set, not at every point.

**Disposition:** sufficient configuration and operating-point evidence to report a bounded Task 2e Linux-versus-bare-metal framework result under the tested clock configuration. It does not meet a stronger claim of simultaneous/per-window clock instrumentation, controlled backend ordering, or causal isolation of OS overhead. The next maximum-reliable-envelope stress experiment is distinct from this Task 2e closure.

AMD references: [UG1085, Zynq UltraScale+ MPSoC Technical Reference Manual, PS Clock Subsystem](https://docs.amd.com/r/en-US/ug1085-zynq-ultrascale-mpsoc-trm/PS-Clock-Subsystem); [UG1087 ACPU_CTRL](https://docs.amd.com/r/en-US/ug1087-zynq-ultrascale-registers/ACPU_CTRL-CRF_APB-Register); [UG1087 APLL_CTRL](https://docs.amd.com/r/en-US/ug1087-zynq-ultrascale-registers/APLL_CTRL-CRF_APB-Register); [UG1087 IOPLL_CTRL](https://docs.amd.com/r/en-US/ug1087-zynq-ultrascale-registers/IOPLL_CTRL-CRL_APB-Register).
