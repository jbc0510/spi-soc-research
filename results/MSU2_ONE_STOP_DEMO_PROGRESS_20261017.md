# MSU-2 one-stop demo console — progress report

**Date:** 2026-10-17
**Status:** Linux test menu passed on the ZCU102. Bare-metal menu parity now builds against the validated XSA. The Linux-to-bare-metal reboot handoff and return path are not yet implemented or hardware-tested.

## Intended operator flow

The board boots its existing Linux image. After login, the operator runs one
command and chooses Linux or bare metal, then chooses a test from that mode's
submenu. Linux remains the normal boot. Selecting bare metal requires a
controlled processor reboot because Linux and a standalone A53 program cannot
run concurrently. A one-time request must select the standalone test, and its
return action must reboot to the unchanged Linux default. This software menu
and its boot handoff are development functions; they are not secure boot and
must not be presented as such.

No SD card or BOOT.BIN was changed during the bare-metal work described here.

## Linux path already demonstrated on the board

The no-Python shell menu was run on the ZCU102 using the September 29 validated
AXI Quad SPI bitstream (file SHA-256
`c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`). It
configured PL0 at 99.99 MHz, released the PL reset, registered the SPI
controller, and exposed `/dev/spidev1.0`.

- One-byte J55 loopback returned `0xa5` for transmitted `0xa5`.
- The shared 11-size integrity/latency sweep completed 11,000 transfers with
  zero API errors and receive mismatches.
- The operator-selected 10-second sustained run at 256 B, 4 KiB and 64 KiB
  completed 55,937 transfers with zero API errors or mismatches.
- The menu returned to the ordinary Linux shell without automatically starting
  a test.

The requested SPI frequency in the user-space test is not a measurement of
physical SCK. Pin-level SCK and loopback topology remain outside what these
menu runs prove. Raw target logs were saved on the SD card and still need to be
archived on the host.

## Bare-metal menu work completed on the host

`bare_metal/src/spi_sustainable_benchmark_bare_axi.c` now offers the same
shared payload sizes as the Linux menu, explicit `RUN` confirmation, and these
selections:

1. RX integrity and latency: 11 shared payload sizes × 1,000 attempts.
2. Sustained throughput: operator-selected shared payloads, 1–3,600 seconds
   per point, and 1–3 repetitions.
3. Full sustained baseline: 11 sizes × 60 seconds × 3 repetitions.
4. One-byte smoke run: one second.
5. `q`: do not run a test; remain in the standalone idle loop.

The integrity output reuses the shared CSV schema and validates received bytes.
Transfer errors are followed by an SPI controller recovery attempt. The
program labels this as a bare-metal test, not an OS selector.

Vitis 2025.1 built the updated ELF against the pinned September 29 XSA:

- Build status: `BUILD_PASS_NOT_HARDWARE_VALIDATION`.
- ELF SHA-256: `32110227aeb7d18e6bbd79e71dc0877916e76326c9625b8f3eee7ba43da4c4f5`.
- XSA SHA-256: `e8b4626edb5949bc8adb14ae259802cdd24b16ea3f02daf0dd8fdbeb1cc0e7d7`.
- The builder produced an ELF only; it did not produce or install a BOOT.BIN.
- This ELF has not been loaded on the ZCU102, and its menu or SPI tests have
  not been hardware-validated.

The isolated Vitis workspace and build manifest are under
`bare_metal/vitis/spi_axi_bm_menu_parity_20261017_final/`.
The concise, commit-ready hash record is
`results/baremetal_menu_build_20261017/build_manifest.json`.

## Reproduction currently available

From a clean clone of `feature/ratio2-j55-rebuild`, the Linux bundle can be
built with:

```sh
python3 scripts/package_msu2_demo_bundle.py --out /tmp/msu2_demo
(cd /tmp/msu2_demo && sha256sum -c SHA256SUMS)
```

After the package is installed on the card and Linux boots, run:

```sh
sudo sh /run/media/BOOT-mmcblk0p1/msu2_demo/msu2_demo.sh
```

This currently opens the Linux test menu directly. A top-level Linux/bare-metal
choice must be added after the handoff and return mechanism is implemented.
The bare-metal ELF build can be reproduced with:

```sh
python3 scripts/build_spi_axi_bm_ratio2_vitis.py \
  --source bare_metal/src/spi_sustainable_benchmark_bare_axi.c \
  --workspace-name spi_axi_bm_menu_parity_20261017_final
```

Vitis 2025.1 and the pinned XSA are needed for that build. A clean GitHub
reproduction of the bare-metal menu therefore still needs the source, build
instructions, and reproducible build metadata committed together.

## Remaining work for the requested one-command, two-mode demo

1. Add a Linux top-level selector: Linux submenu, or bare-metal handoff.
2. Implement a one-shot handoff through the existing boot chain without
   replacing the Linux-default BOOT.BIN. The mechanism must boot the newly
   built standalone ELF after a deliberate reboot and return to Linux after
   the operator exits the bare-metal menu.
3. Test the boot selection and return path on a copy/test card before touching
   the working card. Preserve recovery to the current Linux boot.
4. Install from the host and verify the complete menu path on the ZCU102,
   including both modes, cancellation, results, and return to Linux.
5. Archive the existing Linux run logs from the card and capture equivalent
   bare-metal evidence. Then produce the final matched comparison and report.
6. Separately measure physical SCK and CPU operating conditions before making
   claims requiring those values.

Until these steps pass, the accurate result is: Linux menu and SPI test path
demonstrated; bare-metal menu build passes on the host; the one-command
cross-mode demo and Linux-versus-bare-metal comparison remain open. No secure
boot claim is made.
