# Task 2b CDMA SPI simulation — 2026-10-14

## Result

The fresh Vivado 2025.1 build and XSim run passed the AXI anchor check, the 16-beat keyhole test, the INCR control case, and a 128-byte CDMA-to-AXI-Quad-SPI internal-loopback transfer. The 128 transmitted bytes were read from the SPI receive FIFO in order and all matched the source pattern. The run ended with `CDMASR=0x00001002`, TX FIFO empty, RX FIFO empty after reading, zero byte mismatches, and all testbench assertion groups passed.

The RX FIFO occupancy register read 127 before the 128 verified FIFO reads. The test checks the data itself and confirms the FIFO is empty afterward; the one-count difference is retained as a register diagnostic.

## Reproduction

From the repository root, run:

```bash
/home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1/Vivado/bin/vivado \
  -mode batch -source hardware/sim/run_task2b_cdma_loopback.tcl \
  -log /tmp/task2b_cdma_vivado.log
```

The Tcl script builds a new project in a unique `/tmp/msu2_task2b_cdma_<pid>` directory and preserves prior runs. On this workstation the Vivado process must have host-level access to its local simulator IPC. Inside the restricted execution sandbox, XSim reports `unexpected exception when evaluating tcl command` before the testbench starts; the identical smoke test and fresh CDMA simulation pass with host-level access. No global Vivado, OS, or ZCU102 settings were changed.

## Test scope and limits

- AXI CDMA source: AXI VIP memory model; destination: AXI Quad SPI DTR at `0xA0000068`.
- SPI: internal loopback, SPE enabled, manual SS0 selected; the SPI external pins are not part of this check.
- One 128-byte payload was functionally verified. This is not a multi-size DMA performance sweep.
- Testbench assertion groups fail with `$fatal` if the anchor, keyhole acceptance, INCR control behavior, transfer completion, or received data does not match expectations.
- Simulation timestamps are not compared with physical PIO latency. No hardware DMA test, CPU-use measurement, J55 external loopback, or DMA crossover conclusion is claimed.

## Files

- `../SOW_2B_PIO_DMA_ASSESSMENT_20261014.md` — current Task 2b assessment.
- `../../hardware/sim/tb_keyhole.sv` — testbench source.
- `../../hardware/sim/run_task2b_cdma_loopback.tcl` — fresh-build run script.
- `fresh_build_vivado.log` — fresh design generation, compilation, elaboration, and run log.
- `cdma_loopback_simulate.log` — simulator transaction and testbench output.
