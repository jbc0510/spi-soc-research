# SOW 2.e — QSPI Read Clock Ceiling, ZCU102 #1 at LPS

**Date:** 2026-09-11 · **Board:** ZCU102 #1 · **Host:** stile · **HEAD at start:** ce122b0
**Console log:** `artifacts/2e-qspi/zcu102-1_qspi_recon_20260911.log`
  `6e12b83c860901a5ce422a1578d93005`, 117174 bytes
**Overlay:** `hardware/overlays/qflash_probe.dts`

## Scope

SOW 2.e, "maximum sustainable throughput", with a read across to 2.a.
Objective as stated: maximum QSPI clock before data corruption, and maximum
payload before data corruption.

**READ-ONLY throughout.** Every access used `/dev/mtd0ro`. Nothing was
written to the flash. Boot mode is `sdboot`, so the QSPI device is dormant.

## Part 1 — the flash was unreachable from every software layer

Root cause: `/axi/spi@ff0f0000/flash@0` has **neither `compatible` nor
`reg`**. The node lists only `partition@0..2`, `phandle`, and the two
bus-width properties.

    Linux   spi_master spi0: cannot find modalias for /axi/spi@ff0f0000/flash@0
            no /dev/mtd*, no /dev/spidev*
    U-Boot  sf probe -> zynqmp_qspi: Invalid chip select 0:0 (err=-19)

Both consume the same broken node. Kernel configuration is NOT the problem:
`CONFIG_SPI_ZYNQMP_GQSPI=y`, `CONFIG_MTD_SPI_NOR=y`, `CONFIG_SPI_SPIDEV=y`,
`CONFIG_OF_OVERLAY=y`, `CONFIG_OF_CONFIGFS=y`.

Corroborating measurement: `qspi_ref` in `clk_summary` showed enable = **N**.
The reference clock was gated because nothing had requested it.

### Fix: a 394-byte device-tree overlay, no rebuild

Adding properties to the existing node does not re-trigger the SPI core's OF
notifier, which fires on node ADDITION. The overlay therefore adds a NEW
child at the same chip-select carrying the missing properties.

Applied via configfs; transferred to the board as hex-escaped `printf` chunks
over the console, byte-count gated at 132/264/394 and md5-gated at
`2099a8d6a0b5765c9460a5ac8b19a0d8`. The board has no `base64`, `python3`,
`openssl`, `xxd` or `perl`; busybox `dd` has no `conv=notrunc`.

Result:

    /dev/mtd0  /dev/mtd0ro  /dev/mtdblock0     spi0.0 -> spi:spi-nor
    mtd0: 04000000 00010000 "spi0.0"           64 MiB, 64 KiB erase, type nor

**This is the reusable outcome of the session.** The QSPI flash is now
reachable from Linux with no PetaLinux rebuild.

Note: the DT declares `is-dual = <1>`, `num-cs = <2>` (two chips in
parallel), but mtd0 reports 64 MiB — a single part. The driver appears to
have bound one chip and ignored the parallel config. NOT investigated.

## Part 2 — clock sweep

GQSPI divides `qspi_ref` = 249,975,000 Hz by powers of two. The driver picks
the largest divisor at or below `spi-max-frequency`, so a 10 MHz request
yields 7.81 MHz. Each rung was a 4-byte patch at offset 232 of the dtbo.

Target: 1 MiB at flash offset 0x100000. Baseline established by three
identical reads at 7.81 MHz: `b4014a90c5187987c47ae375f33e5e91`.

| divisor | SCK MHz | wall time | theory | overhead | md5 |
|---|---|---|---|---|---|
| /16 | 15.623 | 0.577 s | 0.537 | +7.5% | match |
| /8 | 31.247 | 0.309 s | 0.268 | +15.1% | match |
| /4 | 62.494 | 0.180 / 0.175 s | 0.134 | +34% | match |
| /2 | 124.987 | 0.098 s | 0.067 | +46% | **MISMATCH** |

Wall time approximately halved at each rung, confirming the divisor actually
changed rather than the request being silently ignored. Rising overhead
indicates a component that does not scale with SCK (FIFO service or
per-command cost); NOT characterised.

At 124.987 MHz, three consecutive reads produced **three different hashes**:

    32c10de501f5f3670f4ff7a726f991b1
    5eef6d287af035b058410f52739ab8d5
    f9b3daad991360ada00f599aa988dce7

697 of 1,048,576 bytes differed (0.067%). All three began differing at the
**same** byte, read offset 0xD00C0 = flash 0x1D00C0.

**Non-deterministic in content, deterministic in onset.**

## Part 3 — the corruption is ADDRESS-dependent, not LENGTH-dependent

A payload sweep at 124.987 MHz appeared to show a ceiling at 832 KiB
(clean at 832, corrupt at 896). **That result is an artifact of the sweep's
design and is withdrawn.** Every read started at flash 0x100000, so longer
reads necessarily covered more addresses. Length and address varied
together; the sweep measured where reads reached 0x1D00C0.

Two controls settle it:

1. A full 1 MiB read at flash 0x200000 is **byte-identical at 124.987 MHz
   and 62.494 MHz** (`c2ebfbd8ef2f5605f9c48c5c2698acde`). A 1 MiB transfer
   at 125 MHz can be perfectly clean.
2. A **64 KiB** read at flash 0x1D0000 — a tiny transfer — is stable at
   62.494 MHz (`05e6caa934d76df19176a2cc52044c7d` twice) and UNSTABLE at
   124.987 MHz (`b5519e7e...` then `d87fa48c...`).

**There is no payload ceiling.** Transfer length is not a factor.

## Part 4 — where the unstable regions are

Method: read each 64 KiB block twice at 124.987 MHz and compare the two
reads against each other. Self-consistency as the detector; no baseline
needed.

| flash address | 124.987 MHz |
|---|---|
| 0x000000 – 0x1C0000 | stable |
| **0x1D0000, 0x1E0000, 0x1F0000** | **UNSTABLE** |
| 0x200000 – 0x340000 | stable |
| **0x380000** | **UNSTABLE** |
| 0x400000 | stable |

Contiguous unstable region **0x1D0000 – 0x1FFFFF = 192 KiB**, plus at least
one further isolated block at **0x380000**.

Three independent measurements agree: the corrupt tail of the 1 MiB baseline
read ran 0x1D00C0 to 0x200000 = 191.8 KiB; the block scan marks exactly
three 64 KiB blocks = 192 KiB; and 0x200000 tested stable by two
independent methods.

## Conclusions

- **124.987 MHz is NOT a general ceiling.** Most of the device reads
  perfectly at that rate, including full 1 MiB transfers.
- **Specific address regions fail at 124.987 MHz**, independent of transfer
  length.
- **62.494 MHz is clean at every address tested**, including the regions
  that fail at 125 MHz.
- Failure signature: non-deterministic content, deterministic onset —
  consistent with marginal sampling rather than a fixed timing violation.
- Highest clock clean everywhere tested: **62.494 MHz**.

## Instrumentation errors made this session

Both were in the measurement apparatus, not the hardware. Recorded because
they are the same confound class as the retracted 14.24x clock artifact.

1. **Length/address confound.** The payload sweep varied transfer length and
   address range together and was initially read as a length result. Caught
   by a fixed-length read at a different address. The 832 KiB figure is
   withdrawn.
2. **Address label error.** The block-scan `printf` added 0x100000 that `dd`
   never applied — `dd skip=` on `/dev/mtd0ro` is an absolute flash offset.
   Every address printed by the two scan loops in the console log is
   0x100000 too high. The table in Part 4 is corrected. **When reading the
   raw log, subtract 0x100000 from the scan output.**

A third error was caught before it propagated: the md5 of 64 KiB of 0xFF was
asserted from memory as `bd82eb9b...` and is actually
`ecb99e6ffea7be1e5419350f725da86b`.

## DELIBERATELY NOT CLAIMED

- **No write, erase or program operation was performed or tested.** Read
  path only. Write behaviour at any clock is unknown.
- Only **single-bit** (`spi-tx/rx-bus-width = <1>`) transfers were tested.
  The DT declares the hardware as quad-capable. Dual and quad modes untested.
- The flash part was **not identified**. No JEDEC ID was captured; the probe
  messages did not reach the dmesg ring before it was inspected.
- The `is-dual = <1>` parallel configuration is **not** reflected by the
  bound driver, and the discrepancy is unexplained.
- No rung exists between 62.494 and 124.987 MHz — GQSPI offers only
  power-of-two divisors — so the threshold is **bracketed, not located**.
  Narrowing it requires changing `qspi_ref` itself.
- The **cause** of the address-localised instability is unknown. Media
  defect, board routing, and die-boundary effects are all consistent with
  the evidence and none was tested.
- The scan sampled 64 KiB blocks at intervals. Unstable regions between
  sampled blocks would not have been detected. The map is **not exhaustive**.
- Only ZCU102 #1 was tested. Whether board #2 shows the same regions is
  unknown and is the obvious next test.
- Temperature was not monitored or controlled.
- No 2.f work was performed this session.
