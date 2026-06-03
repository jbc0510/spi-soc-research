# On-Chip ILA Plan — Measure the Real AXI SPI Serial Clock

**Project:** MSU-2 (ZCU102 SPI Benchmark) · Contract FA-8075-18-D-0004
**Goal:** Resolve the 6.25 MHz (config) vs. ~11 MHz (timing-implied) SCK discrepancy
by capturing the SCK net inside the fabric with an Integrated Logic Analyzer (ILA),
avoiding the J55 external-pin routing issues.
**Platform:** stile (Vivado 2025.1), project /tmp/spi_rebuild_proj/spi_rebuild.xpr

## Why ILA (not external logic analyzer)
- Taps the SCK net internally over JTAG; no physical probe, no J55 pins.
- Sampled with PL0 (the fabric clock). Because PL0 also feeds the SPI divider,
  the ILA effectively COUNTS PL0 cycles per SCK period = the actual divide ratio.
  - 16 PL0 cycles per SCK period -> ratio 16 confirmed -> SCK = PL0/16 = 6.25 MHz
    (config correct; the ~11 MHz was a benchmark timing artifact).
  - ~9 PL0 cycles per SCK period -> effective ratio ~9 -> SCK ~ 11 MHz
    (silicon differs from config; investigate the IP clock path).

## IMPORTANT: use the 6.25 MHz benchmark build, not the 1 MHz build
The discrepancy is in the BENCHMARK build (PL0=100, ratio 16). The live project is
currently the 1 MHz build (PL0=16). Restore PL0=100 first (set
PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100}) OR check out the block-design Tcl from
commit cb53535 / 77cd6e9, so the ILA measures the configuration that produced the
~11 MHz timing. Otherwise you measure the 1 MHz build and learn nothing about the
discrepancy.

## Method A — System ILA in the block design (recommended)

1. Open the project and block design:
   - open_project, open_bd_design.
2. Expose SCK as a probe-able net. The AXI Quad SPI SPI_0 interface bundles
   SCK/MOSI/MISO/SS. Two options:
   a. Right-click the SPI_0 interface -> make external is already done for pins;
      instead, in the BD, select the AXI Quad SPI, and use "Debug" on the SPI
      clock output, OR
   b. Add a "System ILA" IP, connect its monitored interface to the AXI4-Lite
      interface AND add a probe net for sck. If SCK is only inside the SPI
      interface, break out the interface (Vivado: right-click SPI_0 -> "Break
      Interface Connection" is not needed; instead use slice/utility to tap the
      sck bit) or enable debug on the IP's SCK output pin.
3. Add ILA:
   - Add IP -> "ILA (Integrated Logic Analyzer)" or "System ILA".
   - Set probe width to match (sck = 1 bit; optionally also probe mosi 1 bit,
     ss 1 bit, and the AXI valid/ready for context).
   - Connect ILA clk to the PL0 / s_axi_aclk net (100 MHz) -- the SAME clock that
     drives the AXI SPI. This is what makes the cycle-count = ratio.
   - Set ILA sample depth to e.g. 4096 (enough to see many SCK periods).
4. validate_bd_design, save_bd_design, generate_target all.
5. reset_run synth_1; launch_runs impl_1 -to_step write_bitstream; wait_on_run.
6. write_cfgmem to .bit.bin (same recipe as the benchmark builds) if booting from
   SD, OR program over JTAG directly from Hardware Manager (faster for debug).

## Capture procedure (Hardware Manager)
1. Connect: open_hw_manager, connect to the board over JTAG (open_hw_target).
2. Program the device with the ILA-instrumented bitstream.
3. Set the ILA trigger: trigger on sck rising edge, or just free-run capture.
4. On the board, start a long transfer so SCK is active during capture:
   /tmp/spi_loopback_test /dev/spidev0.0 1000000   (use a big payload, e.g. 64KB+)
5. Arm the ILA, capture.
6. In the waveform: measure the SCK period in SAMPLES. Since the sample clock is
   PL0 (100 MHz, 10 ns/sample):
   - SCK period in samples x 10 ns = SCK period in ns.
   - Or directly: PL0_cycles_per_SCK_period = the divide ratio.

## Reading the verdict
- If SCK period ~ 16 PL0 samples (160 ns -> 6.25 MHz): config is right; the
  benchmark's implied ~11 MHz is a TIMING ARTIFACT (timed region doesn't capture
  full on-wire transfer). Fix the measurement, not the hardware. Paper: state real
  SCK = 6.25 MHz, decomposition becomes valid with 6.25x clock component.
- If SCK period ~ 9 PL0 samples (~90 ns -> ~11 MHz): silicon SCK != config; the
  IP is not dividing PL0 by 16 as configured. Investigate ext_spi_clk source and
  the IP's actual clocking. Paper: report measured SCK, revise accordingly.

## Caveats / gotchas
- The ILA clk MUST be the 100 MHz domain that clocks the AXI SPI, or the
  cycle-count interpretation breaks. If you sample with a different clock, you get
  SCK frequency but not the clean ratio readout.
- If SCK is hard to break out of the SPI interface bundle, the simplest reliable
  tap is to enable "Debug" (mark_debug) on the AXI Quad SPI's sck_o output net in
  the synthesized design, then run the debug-insertion flow -- but confirm the net
  name in the synth netlist first (report_nets or the schematic).
- Capture must happen WHILE a transfer is running; arm the ILA, then kick the
  benchmark, or set a trigger on sck activity.
- JTAG programming from Hardware Manager is faster than SD reflash for iterating
  on the ILA build.

## One-line summary
Insert a System ILA clocked by the 100 MHz PL0, probe the AXI SPI SCK net, capture
during a transfer, and count PL0 cycles per SCK period -- that number IS the divide
ratio and settles 6.25 vs. 11 MHz directly. Use the PL0=100 benchmark build, not
the 1 MHz build.
