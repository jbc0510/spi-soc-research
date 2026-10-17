# MSU-2 demo console (Linux)

`msu2_demo.sh` is the no-Python Linux-side operator menu for the minimal
PetaLinux image. `msu2_demo.py` provides the same menu on Linux images that
include Python 3. Both are started by an operator after Linux has booted; neither
starts a test automatically during boot. Choosing `0` or `q` returns to the
normal Linux console for ordinary computer use. The shell application records
one non-overwriting evidence directory per test under
`msu2-demo-results/` beside the package on the FAT boot partition by default.
The separate bare-metal ELF also has a UART
menu; these applications do not yet provide a power-on OS chooser.

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

## Shell-menu package contents

The minimal-image menu expects these files beside `msu2_demo.sh`:

```text
pl0-clock-only.dtbo
pl-reset-release.dtbo
axi-spi-controller.dtbo
spi_ratio2_j55_lvcmos33_20260929.bit.bin
linux_spi_smoke_aarch64
spi_benchmark_v3_rxverify_aarch64
spi_sustainable_benchmark_linux_aarch64
```

The `dtbo` files and target executables are the hash-recorded artifacts in
`results/linux_axi_spi_bringup_20261013/` and
`results/task2e_sustainable_runner_20261016/`. The menu checks the validated
bitstream source hash before programming. A user explicitly chooses hardware
bring-up or a test. Hardware bring-up applies the PL0 clock, programs the full
bitstream, releases the PL reset, registers the AXI SPI controller, and binds
spidev in that order. It refuses unexpected overlay state and records each test
log and a text manifest. It marks the physical SCK and live FPGA identity as
unverified because it cannot measure SCK or read the programmed design back.

## Install and launch on the target

On the minimal PetaLinux image, copy the shell menu and package files above to a
directory on the boot partition, then launch it after login as root so it can
read the root-owned FAT files and access `/dev/spidev1.0`:

```sh
sudo sh /run/media/BOOT-mmcblk0p1/msu2_demo/msu2_demo.sh
```

The menu uses `sudo` for FPGA, clock, reset, overlay, device binding, and SPI
operations. It does not require Python 3. For Python-enabled Linux images, copy
`linux/appliance/msu2_demo.py` to the target and install the already-built
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

The bare-metal sustained application presents its own UART menu when that
standalone ELF is booted. It offers the existing full 11-payload/60-second/3
repetition baseline, a configurable single-payload run, and a one-second
single-payload smoke run. It requires explicit `RUN` confirmation. Build it
without packaging or programming a board image with:

```sh
python3 scripts/build_spi_axi_bm_ratio2_vitis.py \
  --source bare_metal/src/spi_sustainable_benchmark_bare_axi.c \
  --workspace-name spi_axi_bm_unified_menu_20261017c
```

The build validates the ELF and pinned XSA relationship. It does not package a
BOOT.BIN or prove the UART menu or SPI path on hardware.
