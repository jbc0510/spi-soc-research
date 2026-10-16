# Task 2e target access status — 2026-10-16

The ZCU102 is reachable through the CP2108 UART and remains responsive at the `newQspi` console. Read-only preflight confirmed Linux `6.12.10-xilinx-g0a0f70e531c7`, PetaLinux 2025.1, FPGA Manager state `operating`, `/dev/spidev1.0`, platform device `a0000000.spi`, SPI child `spi1.0`, a 1 MiB spidev buffer, and 348,001 accumulated interrupts on the AXI SPI IRQ. See `target_preflight.log`.

The console currently runs as `petalinux` (UID 1000). `/dev/spidev1.0` is `0600 root:root`; `sudo -n` says a password is required, and the provided `root` password was rejected by `su`. The unprivileged account cannot read the current clock summary, CPU frequency, or protected bitstream path. Previously captured clock, reset, and loopback evidence remains in `results/linux_axi_spi_bringup_20261013/`.

One UART upload attempt failed because the target shell consumed base64 data as commands before a receiver was ready. The shell returned to the unprivileged prompt. A follow-up read-only check confirmed the board remained responsive. No AXI SPI register access, spidev ioctl, FPGA reprogramming, clock/reset change, or reboot occurred during this session. No new physical transfer result is claimed.

The Linux AArch64 runner requires GLIBC_2.38 at most; target `/lib/libc.so.6` exports GLIBC_2.39, so the dynamic ABI is compatible. Root-level access is still required to stage and execute the runner against the current root-only spidev node. Once root console access is restored, use `scripts/task2e_upload_runner.py`; it now refuses to upload unless the shell is already root and waits for an explicit receiver-ready marker.
