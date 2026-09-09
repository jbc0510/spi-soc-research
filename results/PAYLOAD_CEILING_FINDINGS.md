# Payload Ceiling Investigation — spidev bufsiz vs. AXI Hardware

**Project:** MSU-2 (ZCU102 SPI Benchmark) · Contract FA-8075-18-D-0004
**Date:** 2026-06-03
**Platform:** ZCU102 (xczu9eg), PetaLinux 2025.1, AXI Quad SPI v3.2 @ **15.625 MHz** SCK (C_SCK_RATIO=16, PL0 250 MHz from live CRL_APB). *Originally written "@ 6.25 MHz (C_SCK_RATIO=16, 100 MHz fabric clock)" — superseded, see CORRECTION below.*
**Author:** J. Conway

> ## CORRECTION — 2026-09-09
>
> **The 6.25 MHz SCK originally stated in the Platform line is wrong.** It came
> from the design-time assumption PL0 = 100 MHz ÷ C_SCK_RATIO 16. Live CRL_APB
> reads establish IOPLL 1500 MHz → PL0 250 MHz (÷6) → **AXI SCK 15.625 MHz**.
>
> This file refutes its own header twice:
>
> 1. Line ~31 calls ~10.9 Mbps "consistent with the 6.25 MHz native SCK".
>    Single-lane standard SPI (`C_SPI_MODE=0`) carries one bit per clock, so
>    6.25 MHz caps throughput at 6.25 Mbps. 10.9 > 6.25.
> 2. The timings near the end (4 MB ~ 3 s/trial, 16 MB ~ 12 s/trial) match
>    10.9 Mbps to within a few percent. At 6.25 Mbps they would be 5.4 s and
>    21.5 s — roughly 1.75x slower than observed.
>
> **The bufsiz / EMSGSIZE / ENOMEM findings are unaffected.** They concern Linux
> driver and allocator limits, not the wire rate, and stand as written.
>
> Original wording is retained throughout rather than rewritten. Triage:
> `results/CLOCK_TRIAGE_20260909.md`, commit `a23f32b`.
>
> **Not claimed:** that ~10.9 Mbps is itself correct. It is an unverified figure
> from the 2026-06-03 capture. Established here only that it is inconsistent
> with 6.25 MHz and consistent with 15.625 MHz. 15.625 MHz is DERIVED from
> register reads and the synthesis-frozen ratio; the AXI serial clock has never
> been observed on the wire.

## Question

The benchmark sweep had never exhibited a payload-size ceiling. We extended the
sweep upward (to 16 MB) to find the maximum payload the system can transfer
without error or corruption, and to determine whether any such limit is imposed
by the AXI hardware or by the Linux software stack.

## Method

- Extended `payload_sizes[]` in `spi_benchmark_clean.c` to add 256 KB, 1 MB, 4 MB, 16 MB.
- Buffer allocation auto-sizes to the largest payload (`max_len = payload_sizes[NUM_PAYLOADS-1]`), so no separate buffer edit was needed.
- Ran the internal-loopback sweep (`devmem 0xa0000060 32 0x00000187`) at each `bufsiz` setting, observing where transfers begin to fail and the nature of the failure.

## Results

| spidev `bufsiz` | Largest successful transfer | Failure mode at the ceiling |
|---|---|---|
| 1,048,576 (1 MB, default) | 1 MB | `EMSGSIZE` ("Message too long") at 4 MB |
| 4,194,304 (4 MB) | 4 MB | (expected `EMSGSIZE` at 16 MB; wall tracks bufsiz) |
| 33,554,432 (32 MB) | — | `ENOMEM` ("Cannot allocate memory") at **device open** |

Across every payload that the driver accepted (1 byte through the active bufsiz
limit), the AXI hardware completed with **zero data errors** and stable
throughput of ~10.9 Mbps (consistent with the 6.25 MHz native SCK and FIFO
burst overlap).

> **[2026-09-09]** The parenthetical is wrong and was self-refuting when
> written: single-lane standard SPI carries one bit per clock, so a 6.25 MHz
> SCK caps throughput at 6.25 Mbps and cannot produce 10.9 Mbps.
> `results/CLOCK_DISCREPANCY_FINDINGS.md` lines 41-42 caught the same
> impossibility independently. At the established **15.625 MHz** SCK,
> 10.9 Mbps is ~70% wire efficiency, which is plausible for a FIFO-serviced
> path. The measured throughput is not disputed here — only its stated
> cause. See CORRECTION at the top of this file.

### Interpretation

1. **The payload ceiling is a software limit, not a hardware one.** The maximum
   single transfer is set by the spidev driver's `bufsiz` parameter. The wall
   moved exactly in step with `bufsiz` (1 MB cap at 1 MB buffer; 4 MB transfers
   succeeded once the buffer was raised to 4 MB).

2. **There is an upper bound on `bufsiz` itself, set by kernel memory, not SPI.**
   spidev allocates two buffers of `bufsiz` each (TX + RX) at device-open. At
   `bufsiz = 32 MB`, that 64 MB contiguous allocation failed (`ENOMEM`) before
   any transfer occurred. The practical `bufsiz` ceiling on this board therefore
   lies between 4 MB and 32 MB.

3. **No AXI hardware payload limit or corruption was observed at any size.** The
   AXI Quad SPI streams data via its 256-byte FIFO, refilled by the driver in a
   loop, so it has no inherent single-transfer size cap. Every accepted transfer
   passed cleanly.

**Conclusion:** the maximum correctly-transferred payload is governed entirely by
the Linux SPI software stack — the spidev `bufsiz` buffer and, above it, kernel
contiguous-memory allocation at device-open — not by the AXI SPI hardware. This
is consistent with the project's broader finding that the OS layer, not the
silicon, is the dominant constraint on this interface.

## How to change the spidev buffer size

`spidev` on this image is **compiled into the kernel** (not a loadable module),
so `bufsiz` cannot be changed at runtime:

```
# both of these FAIL on this build:
modprobe spidev bufsiz=N            # "Module spidev not found" (built-in)
echo N > /sys/module/spidev/parameters/bufsiz   # "Permission denied" (read-only)
```

It must be set via the kernel command line. The bootargs are assembled by
`boot.scr` (which hardcodes `spidev.bufsiz=1048576`), and the board has no
writable U-Boot environment area ("No Valid Environment Area found"). The
reliable method is to **bypass `boot.scr`** and boot the FIT image manually with
custom bootargs.

### One-time change (test) — at the U-Boot prompt

Reboot, press a key during the autoboot countdown to reach the `ZynqMP>` prompt:

```
fatload mmc 0:1 0x10000000 image.ub
setenv bootargs earlycon console=ttyPS0,115200 root=/dev/ram0 rw spidev.bufsiz=4194304
printenv bootargs        # VERIFY the bufsiz token is present before booting
bootm 0x10000000
```

`bootm` extracts kernel + ramdisk + DTB from the FIT and boots using the
bootargs just set — it does not source `boot.scr`, so the hardcoded 1 MB value
is bypassed. Do not `saveenv` (no writable env area; the change is one-time).

After boot, confirm:
```
cat /proc/cmdline                              # shows spidev.bufsiz=4194304
cat /sys/module/spidev/parameters/bufsiz       # 4194304
```

**Guidance on the value:** spidev allocates 2 x bufsiz at open. Keep
2 x bufsiz comfortably within available contiguous kernel memory. 4 MB
(-> 8 MB at open) works; 32 MB (-> 64 MB) fails with ENOMEM. Set bufsiz to just
above the largest payload you intend to test.

### Permanent change (future)

To persist across reboots, regenerate `boot.scr` from its `boot.cmd` source with
the desired `spidev.bufsiz=` value and re-wrap with `mkimage`, or rebuild the
PetaLinux image with the updated bootargs. (Not done here; the one-time U-Boot
method was sufficient for the investigation.)

## Reproduce

1. Boot to U-Boot, set `spidev.bufsiz` via the one-time method above (size > target payload, 2x within memory).
2. Init: copy bitstream to `/lib/firmware`, apply the PL overlay, create `/dev/spidev0.0`, copy `spi_loopback_test` to `/tmp`.
3. `devmem 0xa0000060 32 0x00000187` (internal loopback).
4. `/tmp/spi_loopback_test /dev/spidev0.0 1000000`
5. Observe the largest size that transfers vs. the `EMSGSIZE`/`ENOMEM` boundary.

> Note: at 6.25 MHz, large payloads are slow (4 MB ~ 3 s/trial; 16 MB ~ 12 s/trial).
> A few trials suffice to confirm pass/fail; full 1000-trial rows at MB scale take
> tens of minutes to hours.
>
> **[2026-09-09]** Read "15.625 MHz" for "6.25 MHz". The per-trial times are
> correct as observed and are themselves evidence against the 6.25 figure:
> 4 MiB at 10.9 Mbps is 3.08 s and 16 MiB is 12.3 s, both matching what was
> seen. At a 6.25 Mbps ceiling they would have been 5.4 s and 21.5 s.
