# Linux AXI SPI investigation, October 13–14, 2026

Status: read-only board investigation complete; clock-only experiment prepared,
not applied. Linux transfer verification and comparison remain blocked on
hardware initialization. No root cause of the earlier hangs is established.

## Provenance and confirmed observations

Repository: feature/ratio2-j55-rebuild, starting HEAD
867ef7de7aa1de1691bc8283f55984098f1e663a. Three preexisting untracked
sd-images/baremetal/axi_ratio2* directories are preserved. No FPGA rebuild.

The September 29 XSA SHA-256 is
e8b4626edb5949bc8adb14ae259802cdd24b16ea3f02daf0dd8fdbeb1cc0e7d7.
Its embedded bitstream matches the adjacent .bit byte for byte. Repository and
board SD-card .bit.bin both hash to
c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd.
This verifies the files, not what is currently programmed. FPGA-manager state
is `unknown`. Build provenance records Vivado 2026.1; installed workstation
Vivado/Vitis paths are 2025.1. These are distinct tool provenance facts.

`xsa_audit.txt` records the authoritative HWH parameters and connections:

- HPM0 FPD (128-bit) -> SmartConnect -> SPI AXI Lite (32-bit),
  address 0xA0000000–0xA000FFFF.
- SPI 3.2, standard master, 8-bit words, one SS, FIFO 256, SCK ratio 2,
  STARTUP disabled. Both SPI clocks, HPM clock, SmartConnect and reset
  synchronizer use PL0, annotated 99.990005 MHz.
- Active-low pl_resetn0 enters proc_sys_reset; separate interconnect and
  peripheral reset outputs feed SmartConnect and SPI.
- SPI interrupt directly enters pl_ps_irq0[0]; HWH marks rising-edge sensitivity.
- XSA IOPLL feedback divider 60, PL0 divisors 10 and 1. This is design metadata,
  not the Linux runtime configuration.

Console identity: CP2108 serial B66A78CB12A648B611E661AF58A7182 interface 0,
/dev/ttyUSB0. Existing picocom was released by the user before opening an
exclusive Python serial session at 115200. `target_console.log` contains raw
output across both dates; board clock is not wall-clock reliable. Serial
execution uses /tmp/msu2_serial_console.py. No target network configuration was
changed; end0 has only a link-local IPv6 address in the capture.

Linux: 6.12.10-xilinx-g0a0f70e531c7. No configfs overlays or spidev devices.
IOPLL 1,499,850,000 Hz; PL0 configured 249,975,000 Hz but hardware disabled and
CCF enable count zero. PL0 div1 has no CLK_SET_RATE_PARENT, while div2 and gate
propagate rate requests. Thus rate propagation stops before the shared IOPLL.
CPU policy reports 1,200,000 kHz, userspace governor; CCF acpu is 1,199,880,000 Hz.
Spidev buffer size 1,048,576 bytes supports the 65,536-byte benchmark payload.

Read-only firmware PM_RESET_GET_STATUS queries return 0 for IDs 1116 (PS_PL0)
and 1112 (GPO3_PL_31). These are different reset definitions. This does not
establish the live PL fabric net level or GPIO direction/output enable.
No GPIO registers were written and no AXI SPI registers were accessed.

SD boot files: BOOT.BIN SHA-256
56db96f7530aa9cf4008d5494f1e1497d6fb6e76ece965d820b99b017e1539de;
image.ub SHA-256
446dd4756b4be2c29d513594e42adf45f0c90a362d2714dcc56f9ddbd5292bf0.
Boot-file hashes do not prove which FSBL initialization functions executed.

## Driver evidence and implications

Sources inspected at the running kernel's reported commit:

- [SPI driver](https://github.com/Xilinx/linux-xlnx/blob/0a0f70e531c7/drivers/spi/spi-xilinx.c):
  accepts xlnx,xps-spi-2.00.a, requires fifo-size, enables clocks and then writes
  and reads SPI CR during probe. Binding is an AXI hardware test, not safe
  metadata inspection. It has no transfer-speed divider programming.
- [FCLK driver](https://github.com/Xilinx/linux-xlnx/blob/0a0f70e531c7/drivers/staging/fclk/xilinx_fclk.c):
  enables the referenced clock; set_rate sysfs uses CCF; removal drops its clock
  enable reference. Removal does not restore the previous divider rate.
- [AFI driver](https://github.com/Xilinx/linux-xlnx/blob/0a0f70e531c7/drivers/fpga/xilinx-afi.c):
  configures firmware AFI pairs then pulses optional resets. Its reset return
  value is ignored; successful binding alone cannot certify reset success.
- [Reset driver](https://github.com/Xilinx/linux-xlnx/blob/0a0f70e531c7/drivers/reset/reset-zynqmp.c):
  maps DT reset IDs to firmware IDs by adding 1000.
- [AMD programming guidance](https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18841847/Solution+ZynqMP+PL+Programming)
  describes FPGA-region, AFI and FCLK integration. Sample values must be checked
  against this hardware rather than copied wholesale.

## Next approved experiment: clock only (approval pending)

`pl0-clock-only.dts` compiles successfully using dtc. It requests 99,990,000 Hz
via CCF clock 71 and an xlnx,fclk consumer under the live `amba` symbol. No SPI,
AFI, reset, firmware-name, or other PL MMIO node is included.

Before execution, confirm no new overlays/consumers and unchanged clock flags.
Stage source and dtbo in target /tmp, verify hashes, then after user approval:

1. Create /sys/kernel/config/device-tree/overlays/msu2_pl0_clock.
2. Write the staged dtbo to that directory's dtbo attribute.
3. Capture overlay status, dmesg, FCLK binding, entire clk_summary and set_rate.
4. Require PL0 near 99.99 MHz, enable count >=1, hardware enable Y, and unchanged
   IOPLL/other consumer rates. CCF state is not an oscilloscope measurement.
5. Stop before FPGA programming, reset changes or SPI binding. Those need a
   further concrete proposal and approval after inspecting the result.

Rollback while there are no other PL0 consumers: write 249975000 to the bound
msu2_pl0_clock/set_rate, remove the configfs overlay directory, then verify
PL0 disabled and original rate restored. Removing the overlay alone leaves the
new rate programmed. Clock changes can affect an unknown loaded fabric, so the
user's disruptive-operation approval rule applies even to this isolated test.

Host build:

```sh
dtc -@ -I dts -O dtb -o /tmp/pl0-clock-only.dtbo \
  results/linux_axi_spi_bringup_20261013/pl0-clock-only.dts
```

## Benchmark and acceptance limitations

Reuse linux/src/spi_benchmark_v3_rxverify.c and common/spi_benchmark_contract.h;
11 payloads, 1000 attempts each, poisoned RX and byte verification already exist.
The October 13 standalone raw log contains 11,000 verified transfers without
errors, but its provenance still labels topology unverified. It records IOPLL
0x00015a00 and PL0 0x01010f00 (divisor 15), unlike the XSA's divider 10.
At this Linux IOPLL rate divisor 15 derives PL0 99,990,000 Hz and SCK 49,995,000
Hz with ratio 2. These are derived rates, not measured pin clocks.

Host regression on October 14: five tests passed; one static bare-metal test
failed because it requires old XScuGic calls replaced by the committed SDT
interrupt wrapper. This is a stale test contract, not a board transfer failure.
No production source or validated artifact was changed to satisfy it.

Remaining: verify fabric reset and PS–PL initialization; approved FPGA load;
correct driver overlay; actual loopback; Linux benchmark; CPU/timer and physical
clock reconciliation; failure/recovery checks; comparisons; actual Statement of
Work 2a–2f acceptance mapping. No Linux performance CSV or Task 2 completion is
claimed. Existing historical reports are retained and may describe older hardware.
