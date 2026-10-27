# ILA capture preflight — 2026-10-23

## Fresh Vivado 2025.1 rebuild attempt — 2026-10-27

- Ran `tmp/ila_trace_capture/build_spi_ila_debug_rebuild.tcl` with the fresh
  Vivado ML Enterprise 2025.1 install for `xczu9eg-ffvb1156-2-e`.
- The Tcl read back the intended ILA settings: native monitor mode, exactly 2
  probes, widths 96 and 4, depth 4096, and PL0 as the ILA clock. The BD
  `validate_bd_design` command completed.
- Generation then failed before synthesis. Vivado could not deliver the
  encrypted ILA file `data/ip/xilinx/ila_v6_2/ttcl/ooc.ttcl`, reporting:
  `Insecure use of encrypted TTCL file ... within unprotected scope`. The run
  stopped at `IP_Flow 19-1747` / `BD 41-1030`; no bitstream, `.ltx`, XSA, or
  capture was produced. This install therefore passes basic launch/version
  checks but has not passed ILA IP generation.
- The attempt also exposed outstanding BD tap issues that must be fixed before
  retrying: scalar `connect_bd_net` taps override pins of the AXI interface,
  and Vivado grounds the MISO tap (`axi_quad_spi_0/io0_i`) because its source is
  still represented through the external SPI interface. The previous wrapper
  path and probe mode issues are corrected in the rebuild script, but the AXI
  taps need an interface-preserving implementation and the external SPI pad
  mapping needs correction before any bitstream can be considered usable.
- Full console log and journal are preserved at
  `tmp/ila_trace_capture/output_rebuild5_20261027/vivado.log` and
  `tmp/ila_trace_capture/output_rebuild5_20261027/vivado.jou`. The generated
  project is under that same output directory. No hardware was programmed.

## Vivado and target discovery

- Vivado 2025.1 batch mode launched successfully.
- Read-only Hardware Manager discovered a Digilent target at
  `localhost:3121/xilinx_tcf/Digilent/210308A46334`.
- ZCU102 FPGA reported as `xczu9_0`, part `xczu9`, with `DONE=0` (not
  programmed).
- The chain also contains `arm_dap_1`.
- Hardware Manager found no ILA cores on either device.
- No bitstream was programmed, and no hardware state was changed.
- The guarded capture script correctly selected `xczu9_0`, refreshed the
  device, then stopped because `spi_ila` was not present. It produced no trace
  file, as expected for an unprogrammed FPGA.

## Existing artifact validation

Ran:

```sh
python3 tmp/ila_trace_capture/validate_trace_inputs.py \
  sd-images/spi_benchmark_ila.bit.bin \
  sd-images/spi_benchmark_ila.ltx
```

Result: **FAIL, as expected.** The old LTX describes `spi_benchmark_i/ila_0`
with two one-bit probes wired only to `axi_quad_spi_0_sck_o` and
`axi_quad_spi_0_io0_o`. The requested setup needs `spi_ila` with 96-bit AXI
and 4-bit SPI probes. These old artifacts are not used as a substitute.

## What is needed for a real trace

The current project’s `design_1.bd` (or matching Vivado project) and a newly
built/programmed bitstream with `spi_ila` plus its matching `.ltx` file. After
that, run the guarded `capture_ila.tcl` script while the Linux SPI workload is
active. A bare-metal comparison also needs a working bare-metal launch path;
the current evidence deck records that the handoff faults before menu entry.
