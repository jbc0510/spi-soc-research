# Jitter Capture - Blocked at BL31, Resume Here

## Status: harness DONE + committed; board capture PENDING (boot hang)

## What is done
- Corrected harness committed at f723799 on dev:
  linux/src/spi_benchmark_jitter.c (+ cross-compiled spi_benchmark_jitter_aarch64)
- Adds CLOCK_MONOTONIC_RAW, SCHED_FIFO, CPU0 pin, mlockall (paper method),
  SPI_LOOP internal loopback, CSV output (bytes,min,max,avg,stddev @ 3 decimals).
- Writes /tmp/emio_internal_results.csv. NUM_TRIALS=1000, payload ladder matches bare-metal.

## Why we need this
- emio_results.csv / mio_results.csv have placeholder stddev (flat 1.0us).
  Old harness measured real stddev but only printed to stdout, never to CSV.
  Need real Linux jitter for a fair bare-metal-vs-Linux determinism claim.
- Decision: write NEW file results/emio_internal_results.csv (internal loopback),
  do NOT overwrite the original external-loopback averages.

## THE BLOCKER (where this stopped)
- Restored Linux to the SD card correctly. ALL boot files verified byte-identical
  to repo (md5: BOOT.BIN a25d654, image.ub ffe0c75b, boot.scr e2ac032b, system.dtb e7630d81).
- Board HANGS at BL31 (ATF banner prints, then nothing - U-Boot never starts).
- Files are correct, so this is NOT a file problem. Suspect: the loose-file FAT
  layout (BOOT.BIN + image.ub copied onto one partition) may never have been a
  verified-bootable config. The FIRST working ZCU102 Linux boot used a FULL
  petalinux-sdimage.wic flashed with dd (own partition layout), NOT loose files.

## RESUME PLAN (next session)
1. Locate the petalinux-sdimage.wic / .wic.xz on STILE (it is here somewhere).
2. Flash the FULL wic to the SD card (dd) instead of debugging loose-file boot.
   This is the method that reached a Linux login: prompt originally.
3. Boot Linux, login root/root, confirm login prompt over serial @115200.
4. ls /dev/spidev*  -> verify which node is EMIO (SPI1). Harness has spidev0.0;
   EMIO is likely spidev1.0. If so, edit SPI_DEVICE, recompile, re-copy.
5. Get spi_benchmark_jitter_aarch64 onto the board (scp or rootfs).
6. SANITY run first (small/few trials), confirm loopback + nonzero sane stddev,
   confirm must run as root (SCHED_FIFO/mlockall).
7. Full 1000-trial run (~18 min). Pull /tmp/emio_internal_results.csv back.
8. Save as results/emio_internal_results.csv; run compare_spi.py - new file should
   PASS the integrity check (unlike the placeholder rows). Commit.

## NOTE FOR PAPER
- This jitter is internal-loopback; add one sentence noting that (matches how the
  AXI sweeps were done per the paper builds section).

## NEW ENV CAVEAT
- jerry0510 is retired (no personal laptops). New flashing machine: jeremiahc
  (Ubuntu, has SD slot, card mounts at /media/jeremiahc/BOOT). Repo + wic are on stile;
  stile has NO SD slot. Need repo/wic reachable from the new laptop, or transfer via stile.
