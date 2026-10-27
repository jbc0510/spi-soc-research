# ILA trace capture test workspace

This folder contains a guarded Vivado Hardware Manager capture script and a
preflight validator. It does not program the FPGA. The capture script expects
the `.ltx` probe map generated alongside a bitstream that contains `spi_ila`
with probe0=96 bits (the AXI Quad SPI IP's actual exposed AXI-Lite pins: 7-bit addresses, 32-bit data, and no AWPROT/ARPROT pins) and probe1=4 bits (SCLK/MOSI/MISO/CS_N).

## Current preflight finding

The 2026-10-27 rebuild attempt with the replacement Vivado 2025.1 install
confirmed the requested ILA configuration in the BD, but IP generation failed
on Vivado's encrypted ILA OOC Tcl file before synthesis. The run also found
that the current AXI scalar taps override interface connectivity and that MISO
is tied off. These are recorded in [TEST_RESULTS.md](TEST_RESULTS.md); the
current build attempt has not produced usable `.bit`/`.ltx` files.

The repository's older `sd-images/spi_benchmark_ila.bit.bin` and
`sd-images/spi_benchmark_ila.ltx` are not the requested design. Its probe map
contains only two one-bit probes: SCLK and MOSI. No `design_1.bd` is present in
the workspace. A read-only Vivado Hardware Manager scan did discover the
ZCU102 JTAG target, but reports the `xczu9_0` FPGA unprogrammed (`DONE=0`) and
finds no ILA cores. Therefore a live trace capture cannot run from the current
FPGA state.
The old bitstream should not be loaded as a substitute for the current PL image.

## Use after building the matching debug bitstream

1. Copy the matching bitstream and `.ltx` into this folder as `debug.bit` and
   `debug_nets.ltx` (or set the file paths at the top of `capture_ila.tcl`).
2. Confirm `validate_trace_inputs.py` reports 2 probes, widths 96 and 4, and
   the four SPI signals in the LTX names.
3. Program the matching design through your normal approved flow. The capture
   script only connects to Hardware Manager; it never calls
   `program_hw_devices`.
4. In Vivado Tcl Console, run:

   ```tcl
   source /home/opentitan/msu2-verify/spi-soc-research/tmp/ila_trace_capture/capture_ila.tcl
   ```

   The script associates `debug_nets.ltx`, checks that exactly one `spi_ila`
   core is discoverable, triggers a capture, waits for completion, and saves
   both `.ila` and `.csv` data in this folder.

5. Run the Linux SPI workload during the configured trigger delay so the sample
   window contains transactions. For Linux-versus-bare-metal comparison, make
   separate captures under each operating environment using the same PL image,
   clock, payload sequence, and trigger setup. The current board log says the
   bare-metal handoff faults before its menu, so that side is not yet runnable
   through the current flow.

The script requires an accessible Hardware Manager target and an already loaded
matching bitstream. It will stop with a clear error if either is missing.

## Related presentation

The 22-slide evidence review (including the Vivado-generated block design as slide 2) is saved at:

`/home/opentitan/msu2-verify/spi-soc-research/deliverables/MSU2_Task2_Evidence_Review_20261023_v54.pptx`

See [SLIDE_GUIDE.md](SLIDE_GUIDE.md) for a slide-by-slide explanation and
[TEST_RESULTS.md](TEST_RESULTS.md) for the preflight outcome.
