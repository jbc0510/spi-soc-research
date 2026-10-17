# MSU-2 demo console (Linux)

`msu2_demo.sh` is the no-Python Linux-side operator menu for the minimal
PetaLinux image. `msu2_demo.py` provides the same menu on Linux images that
include Python 3. Both are started by an operator after Linux has booted; neither
starts a test automatically during boot. Choosing `0` or `q` returns to the
normal Linux console for ordinary computer use. The shell application records
one non-overwriting evidence directory per test under
`msu2-demo-results/` beside the package on the FAT boot partition by default.
The Linux menu is launched after login. A top-level Linux/bare-metal selector
and a reboot handoff are still being integrated; the current launcher enters
the Linux test menu directly.

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

The `dtbo` files and target executables are copied from the committed,
hash-verified release inputs under
`results/msu2_linux_demo_bundle_20261017_v3/`. The bundle builder checks every
input hash. The menu checks the validated bitstream source hash before
programming. A user explicitly chooses hardware
bring-up or a test. Hardware bring-up applies the PL0 clock, programs the full
bitstream, releases the PL reset, registers the AXI SPI controller, and binds
spidev in that order. It refuses unexpected overlay state and records each test
log and a text manifest. It marks the physical SCK and live FPGA identity as
unverified because it cannot measure SCK or read the programmed design back.

## Reproduce from a fresh GitHub clone

The repository contains the menu source, all runtime binaries/overlays, the
validated bitstream, and the package builder. No Vivado, Vitis, target Python,
or untracked workstation SD-card backup is needed to build this Linux demo
bundle. From the LPS workstation, clone or update the feature branch and build
a new package directory:

```sh
git clone --branch feature/ratio2-j55-rebuild \
  https://github.com/jbc0510/spi-soc-research.git
cd spi-soc-research
python3 scripts/package_msu2_demo_bundle.py --out /tmp/msu2_demo
(cd /tmp/msu2_demo && sha256sum -c SHA256SUMS)
```

The clean-clone verification was run at commit
`6d86bcc0fcd32ddc27c8dcba76692d8ace175338`: package creation succeeded, all
nine file hashes passed, and the POSIX shell syntax and menu self-test passed.
The self-test does not access the ZCU102.

With the board safely off and its boot SD card mounted on the workstation, copy
the package into a new `msu2_demo` directory on the FAT boot partition. Keep
the existing known-good Linux `BOOT.BIN` and other boot files intact. Eject the
card cleanly, boot Linux, log in, and launch the menu command below. In the
menu, choose hardware bring-up and then choose the requested test; the menu
does not launch tests automatically. Choosing `q` returns to the Linux shell.
For example, when the host mounted the FAT partition at
`/media/$USER/BOOT`:

```sh
cp -a /tmp/msu2_demo /media/$USER/BOOT/msu2_demo
sync
```

Use the host's actual mount path if it differs. Eject/unmount the card cleanly
before inserting it into the board.

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

The Linux menu is a functional Linux operator entry point, not yet a two-mode
selector. The requested workflow is to boot the existing Linux image, log in,
run one command, then choose Linux or bare-metal tests. Selecting bare metal
must reboot the A53 into the standalone application; exiting that application
must reboot to the existing Linux default. No new BOOT.BIN is needed for the
menu source/build work, and the current BOOT.BIN must remain unchanged. The
one-time boot handoff and return path still need implementation and board
validation. This menu is a development convenience and must not be described
as secure boot. Secure boot is a separate project objective and remains
unverified.

The bare-metal sustained application presents its own UART menu when that
standalone ELF is booted. Its options now match the Linux test scope: an
11-size × 1,000-trial receive-integrity/latency sweep; sustained throughput
with selected shared payload sizes, 1–3,600 second windows and 1–3
repetitions; the full 11-size × 60-second × 3-repetition baseline; and a
one-second one-byte smoke run. It requires explicit `RUN` confirmation. Build
it without packaging or programming a board image with:

```sh
python3 scripts/build_spi_axi_bm_ratio2_vitis.py \
  --source bare_metal/src/spi_sustainable_benchmark_bare_axi.c \
  --workspace-name spi_axi_bm_menu_parity_20261017
```

The build validates the ELF and pinned XSA relationship. The 17 October 2026
host build produced ELF SHA-256
`32110227aeb7d18e6bbd79e71dc0877916e76326c9625b8f3eee7ba43da4c4f5` and did
not package a BOOT.BIN. It does not prove the UART menu or SPI path on hardware.
