# Linux AXI SPI investigation, October 13–14, 2026

Status: approved clock-only experiment PASSED on October 14. PL0 is enabled
at 99,990,000 Hz; the overlay remains active. Linux transfer verification and
comparison remain blocked on the remaining hardware initialization. No root cause of the earlier hangs is established.

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

## Clock-only experiment (approved and executed October 14)

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

## Clock-only execution result, October 14

User explicitly approved this step. Preconditions remained unchanged: no
overlays, PL0 disabled at configured 249,975,000 Hz, and div1 rate propagation
stopped before IOPLL. Target lacked base64, so staging via base64 failed before
any overlay application. The equivalent DTS was compiled with target dtc; its
dtbo SHA-256 matched the workstation exactly:
00d3bd63dd926a41c3e8581c8d4ee8abb3e94307ad7e4ba345e500e45bb1bffa.

Configfs application returned 0; status is applied. PL0 div1/div2/gate now
report 99,990,000 Hz, enable/prepare counts 1, hardware enable Y. The consumer
bound to xilinx_fclk and its set_rate attribute returns 99990000. The actual
platform device path is /sys/bus/platform/devices/axi:msu2_pl0_clock; an initial
read without the axi: prefix failed harmlessly. Use the prefixed path for the
rollback described above.

Full before/after clk_summary diff shows only PL0 branch rate/enable/consumer
changes and the additional IOPLL enable/prepare reference. IOPLL remains
1,499,850,000 Hz; all other reported clock rates are unchanged. Firmware reset
1116 still reports 0. Board remains responsive, FPGA-manager state remains
unknown. No FPGA programming, reset mutation, SPI probe or AXI SPI MMIO occurred.

The clock overlay is intentionally left active. This establishes CCF-reported
clock initialization, not a measured pin frequency, fabric reset release, AXI
accessibility or SPI functionality. Next work is the remaining reset/firmware
sequence investigation and preparation of a separately approved FPGA load.
Raw command output, including the complete clock-tree diff, is appended in
target_console.log. Historical dmesg includes a devmem SIGBUS at uptime 152 s;
that predates this experiment (uptime about 21 h 52 min) and was not generated
by a new devmem command.

## Reset mapping investigation and proposed programming stage

Installed AMD 2025.1 embeddedsw sources (hashes in reset_source_hashes.sha256)
provide a crucial distinction: pm_defs.h maps firmware IDs 1116..1119 to GPIO5
EMIO92..95 respectively. pm_reset.c maps those IDs to GPIO direction and input
data registers. The XSA reset sequence uses Bank5 bit31 (EMIO95), corresponding
to firmware ID 1119 / DT reset index 119, not index 116 from the older overlay.
The generated XSA sequence and HWH support this mapping; exact running PMUFW
binary identity remains unverified. ID 1112 is PMU GPO3_PL31, a different path.

PmResetGetStatusGpioBankIOs returns the raw GPIO input bit without checking DIRM
or OEN. Despite its generic comment about reset assertion, do not interpret a
zero result as proof that the active-low fabric reset has been released.
All four live queries currently return zero. The reference pulse handler sets
direction and writes high-low-high masked output data; it does not explicitly
configure OEN. Do not assume that pulse alone reproduces XSA initialization.

FSBL reference source calls psu_ps_pl_reset_config_data after a PL partition
load, and in particular reset/handoff branches. This does not establish that the
current Linux boot image executed the same generated function.

Proposed next step (NOT EXECUTED, requires approval): program the hash-matched
September 29 full bitstream through fpga_manager, with PL0 already enabled.
program-validated-fpga.sh is syntax-checked and pins the input hash, current
clock and overlay state, stages into volatile rootfs /lib/firmware, uses flags=0
and writes only the firmware filename to the manager. It then requires state
operating and captures clock, firmware reset-status and dmesg evidence. No SPI
node, reset mutation, AFI change, or AXI SPI MMIO is requested by the script.
FPGA programming itself can alter PL state and firmware-managed isolation; this
is the consequential operation for approval. SD boot files remain untouched.

A failed/hung load stops the investigation; no automatic reboot or retry is
authorized. The previous FPGA contents are unknown and cannot be restored from
a known image. No bitstream readback identity or functional SPI result is claimed
from a successful manager load alone. Further reset/path checks precede any
controller binding. The prepared script is a proposal, not an executed result.

## Software readiness

Linux RX-verifying benchmark rebuilt successfully with AMD AArch64 Linux GCC
13.3.0 and -std=c11 -O2 -Wall -Wextra -Werror -Icommon, linked with -lm.
linux_build_manifest.json pins source, shared contract, executable hashes and
flags. The resulting AArch64 ELF has SHA-256
d4e0e6b747789eb44e9013397e8956703ab41d8b78800e18d5586e72e5037c85.
It has not been executed on the board. For the eventual run, explicitly pass
49995000 as requested speed; its historical default is not this design's SCK.
The driver does not make that requested speed a physical measurement.

The stale static regression was updated to require the current SDT wrapper
setup/disable/enable/disconnect calls and generated interrupt metadata. All six
existing host tests now pass; both original failing and corrected logs are
preserved. This does not replace hardware fault/recovery validation.

The October 13 bare-metal CSV was extracted without changing values into
baremetal_baseline_extracted.csv; all 11 rows have 1000 verified timing samples,
zero RX mismatches and zero timeouts. No Linux comparison values are fabricated.

## Approved FPGA load completed; reset output-enable gap found

The user approved full programming. The exact committed script was transferred
to /tmp and its SHA-256 matched
2fd99caa5b10f9a69b7c832ddcd1a1ba5cf950ffd2fc7e97945a3b0c213b362f.
The script passed its input/staged bitstream hash and clock checks. The manager
reported operating and the script returned 0. Completion marker and raw
clk_summary/dmesg/reset results are captured in target_console.log.
This is a successful hash-pinned load, not bitstream readback verification.

PL0 remains enabled at 99,990,000 Hz and IOPLL remains 1,499,850,000 Hz.
Read-only PS GPIO accesses after load returned:

| Register | Address | Value |
|---|---|---|
| DATA_5 | 0xFF0A0054 | 0xF0000000 |
| DATA_5_RO | 0xFF0A0074 | 0x00000000 |
| DIRM_5 | 0xFF0A0344 | 0xF0000000 |
| OEN_5 | 0xFF0A0348 | 0x00000000 |

These establish missing output-enable relative to the XSA initialization. They
do not yet prove the physical reset net level or the cause of previous hangs.
Reset IDs 1116..1119 still report zero. The PS reads completed and Linux remains
responsive. No AXI SPI transaction was issued.

The matching kernel gpio-zynq.c zynq_gpio_dir_out sets both DIRM and OUTEN then
the requested output value. zynqmp_gpio line 173 is EMIO95 / Bank5 bit31.
The live controller is ff0a0000.gpio, gpiochip1, 174 lines, with none requested
in debugfs. GPIO sysfs and libgpiod tools are absent.

Next proposal (NOT APPLIED; approval required): pl-reset-release.dts uses a
dynamic GPIO hog under the verified gpio symbol to request line 173 output-high
through the kernel driver. It compiles with dtc. Require a claimed
msu2-pl-resetn0 output in debugfs, OEN bit31 set, output data bit31 high and
recheck firmware/GPIO readback before any SPI registration. If dynamic hog
handling is unavailable, stop and inspect; do not substitute raw writes.
This releases active-low fabric reset and can activate the loaded design.
No reset pulse, AFI change or SPI probe is part of this proposal. Removing a hog
releases ownership but does not guarantee restoration of hardware direction or
OEN; rollback requires a separately reviewed operation.

Kernel source: https://github.com/Xilinx/linux-xlnx/blob/0a0f70e531c7/drivers/gpio/gpio-zynq.c

## Approved reset release completed; PS path prechecks

The user approved the EMIO95 output-high overlay. Target dtc output matched
SHA-256 6ae01a4bddea4fe225e2fdee6c5da48df70ce68df7be14328326d7066a171255.
Configfs returned 0 and applied. Debugfs shows gpio-689 owned by
msu2-pl-resetn0, out hi. DATA_5 and DIRM_5 remain 0xF0000000; OEN_5 changed
from zero to 0x80000000. This matches the validated XSA's bit31 output-enable.
DATA_5_RO and firmware reset 1119 still return zero. Kernel gpio-zynq.c reads
the output latch for EMIO output reporting, so neither debugfs high nor the
input readback is a direct measurement of the downstream reset net.

PS read-only checks: AFI_FS at 0xFD615000 = 0x00000A00; masked with 0x300 this
is 0x200, matching XSA HPM0 128-bit selection. RST_FPD_TOP at 0xFD1A0100 =
0x32; masked with XSA AFI reset mask 0x1f80 this is zero.

Direct devmem reads of protected PMU addresses 0xFFD80600, 0xFFD80604 and
0xFFD80110 returned SIGBUS (uptime ~81822 seconds); the shell and Linux remained
responsive. No retry through devmem was made. Inspection of kernel-matched
zynqmp-pm.c verified that writing ONLY an address to config_reg selects a read,
and cat performs CONFIG_REG_READ via firmware. That authorized read path returned
zero for all three registers: AIB isolation control, AIB isolation status, and
pending power-up request status. No PMU register value was written.

Clock remains 99.99 MHz and FPGA manager operating. Clock and reset overlays
remain applied. Missing OEN is now corrected, but root-cause confirmation and
functional SPI proof still require an AXI test.

Next proposed test (NOT EXECUTED; approval required): apply the compiled
axi-spi-controller.dtbo, matching XSA address, two PL0 clock inputs, 256-entry
FIFO, 8-bit words, one CS, direct PL IRQ0 (GIC SPI 89, rising edge). The matching
xilinx_spi driver performs CR writes/reads and controller initialization during
probe. This is the first planned AXI access and can still hang if an unobserved
path fault remains. Capture driver symlink, SPI master and child device,
interrupt registration, dmesg and continued console responsiveness.

The child uses descriptive msu2,spi-loopback rather than impersonating another
physical chip. A later explicit spidev driver_override binding will expose it
for loopback verification. This proposed controller-probe stage does not send
benchmark payloads. No automatic reboot, retry or overlay removal on a hang.
The reset GPIO hog must remain owned and high while the controller operates.
