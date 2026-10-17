# MSU-2 demo console (Linux)

`msu2_demo.py` is the Linux-side operator menu for the ZCU102 SPI tests. It is
started by an operator after Linux has booted; it never starts a test during
boot. Choosing `0` or `q` returns to the normal Linux console for ordinary
computer use. The application writes one non-overwriting evidence directory
per run under `~/msu2-demo-results` by default.

## Menu actions

- **Integrity and latency** calls the receive-verified Linux sweep (all 11
  shared payload sizes, 1,000 attempts per size).
- **Sustained throughput** accepts a comma-separated subset of shared payload
  sizes, a per-point window from 1 to 3,600 seconds, and 1 to 3 repetitions.
  It displays the maximum planned duration and requires the operator to type
  `RUN` before starting. Each point is saved separately and the sweep stops at
  its first failed point.
- **System information** captures Linux/kernel, CPU frequency when exposed,
  SPI node/driver and spidev buffer size. Physical SCK, PL0, topology and the
  programmed bitstream hash are explicitly marked unknown unless independently
  measured; the menu does not infer these values.
- **Bare-metal guidance** explains that bare metal is another A53 boot mode and
  cannot execute concurrently with Linux.

## Install and launch on the target

Copy `linux/appliance/msu2_demo.py` to the target, install the already-built
receive-verification and sustained-runner binaries at:

```text
/usr/bin/spi_benchmark_v3_rxverify
/usr/bin/spi_sustainable_benchmark
```

Then launch:

```sh
python3 /path/to/msu2_demo.py
```

The device and result directory can be overridden with `MSU2_SPI_DEVICE` and
`MSU2_DEMO_RESULTS`. Binary locations can be overridden with
`MSU2_INTEGRITY_BIN` and `MSU2_SUSTAINED_BIN`. This launcher does not configure
the FPGA, change clocks or reset state, install device-tree overlays, or
measure physical SCK. Confirm the board is in the known-good Linux/PL state
before selecting a hardware test.

## Host self-test

```sh
python3 linux/appliance/msu2_demo.py --self-test
```

This validates parameter parsing and evidence-directory/raw-log/manifest
creation with a fake executable. It does not access SPI hardware.

## Current integration boundary

The menu is a functional Linux operator entry point, not yet a power-on OS
chooser. The current ZCU102 boot flow starts Linux without presenting an OS
selection screen. A boot-time Linux-versus-bare-metal chooser requires a
separate, signed boot-flow integration and hardware validation; do not deploy
an unsigned U-Boot menu or use it to bypass the Task 2g verification policy.
