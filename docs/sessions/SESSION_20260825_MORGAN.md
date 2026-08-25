# Session Recap — Morgan, 2026-08-25

**Host:** `bxqp8b3-ub22` (Ubuntu 22.04.5) · **Board:** ZCU102 #2 · **Clone:** `~/msu2-verify/spi-soc-research`
**Branch:** `feature/dma-benchmarking` · **HEAD at session start:** `ebae5cf`

---

## 0. SOW scope statement

The session opened with a scope flag that **no SOW-contracted activity was
planned** — the intent was toolchain install and slide preparation. That
changed mid-session.

**2.e moves from WRITTEN to EXECUTED.** `spi_benchmark_v2_aarch64` ran on
ZCU102 #2 and produced the **first Linux SPI capture in this project whose
controller identity was verified from hardware before the run**. The dataset
carries throughput, latency, jitter, and CPU utilization — the three metrics
2.e names — across 11 payload sizes × 1000 trials.

**2.f remains NOT STARTED.** It is half the 9-month deliverable and it is the
schedule risk. Stated plainly, as required, and it should be stated plainly at
the 2026-08-26 meeting.

---

## 1. Repository and host state

| read | value |
|---|---|
| `git status --porcelain` | empty (clean tree) |
| `git pull` | `Already up to date.` |
| HEAD | `ebae5cf`, in sync with `origin/feature/dma-benchmarking` |
| `df -h` | `/dev/sda3` — 641 G total, **252 G available**, 59% used |

**D-1 gate CLEARS** (UG1144 requires 100 GB for PetaLinux 2025.1).

`~`, `/tmp`, and all build scratch are on a **single filesystem** (`/dev/sda3`).
No separate `/home` or `/tmp` mount, so one number governs the entire storage
budget. Re-read `df -h` after any install.

**HEAD discrepancy resolved.** The continuation prompt states LPS closed at
`8aaa065`. Measured HEAD is `ebae5cf` — one commit ahead, and that commit is
the continuation prompt itself. Self-consistent. `8aaa065` should not be
carried forward as "current".

---

## 2. PetaLinux at Morgan is a snapshot build, not GA

From `~/petalinux/2025.2/.version-history` and `settings.sh`:

```
Distro Version:     2025.2+snapshot-a59a0c815a0ffc2747ab4289284f2c3aee3bc7fd
Metadata Revision:  a59a0c815a0ffc2747ab4289284f2c3aee3bc7fd
Timestamp:          20251116092932
settings.sh:52      export PETALINUX_VER=2025.2
```

Three independent sources agree on the version, so the directory name is
corroborated rather than assumed.

**Consequence for reproducibility.** This is a snapshot pinned to metadata
commit `a59a0c81…`, built 2025-11-16, installed 2026-04-15. It is **not** a
released 2025.2. Any reproducibility claim must cite the metadata revision; a
third party building from a GA installer will not get the same tree. This bears
directly on the 5–8 month deliverable ("reproducible build scripts… and
standardized SPI benchmarking suite").

Version skew at this site: **Vivado 2025.1, PetaLinux 2025.2-snapshot**.
Whether PetaLinux 2025.2 accepts a 2025.1-exported XSA was **not tested**.
Nothing was built this session.

---

## 3. Board identity — hostname and device tree cannot identify a board

| source | value | discriminating? |
|---|---|---|
| CP2108 console serial | `B66A78CB12A648B611E661AF58A7182` → `/dev/ttyUSB0` | **YES** |
| Digilent JTAG serial | `210308A46334` → `/dev/ttyUSB4` | yes |
| hostname | `newQspi` | no — from `image.ub`, on both boards |
| `/proc/device-tree/model` | **absent** | n/a |
| `/proc/device-tree/compatible` | `xlnx,zynqmp` (single string) | **no** — SoC family only |

`/proc/device-tree/` has **30 entries**, so the DT is mounted and readable, and
`ls -l /proc/device-tree/model` returns a visible `No such file or directory`.
The absence is measured, not a suppressed error.

**Finding:** the booted device tree identifies the SoC family only. Nothing in
software on this board identifies *which* ZCU102 it is. **The CP2108 serial is
the only board-identity anchor available.**

**Serial-number reconciliation.** The prior record conflated two adapters.
`C68E7C4D227B4FA211ED7C38CE7DE91` is board #1's at LPS;
`B66A78CB12A648B611E661AF58A7182` is board #2's, measured here. Both correct,
different boards, no conflict.

---

## 4. RTC — corrected, and PROVEN NOT TO PERSIST

Board read `Wed Jan 8 18:23:40 UTC 2025`, corroborated independently by a boot
audit timestamp (`audit(1736360608…)` → 2025-01-08). Offset ≈ **594 days**.

`date --help` → **BusyBox v1.36.1**; `@seconds_since_1970` accepted. `@epoch`
was chosen over date-string forms: unambiguous, no timezone interpretation, no
quoting hazard on a console that had already mangled a multi-line paste.

### First correction (pre-power-cycle)

| step | command | result |
|---|---|---|
| host reference | `date -u '+%s …'` | `1787678228` = 2026-08-25 17:17:08 UTC |
| set | `date -s @1787678228` | 17:17:08 |
| **readback (system)** | `date -u` | **17:17:33** (+25 s) |
| write RTC | `hwclock -w -u` | silent (success) |
| **readback (RTC)** | `hwclock -r -u` | **17:18:40** (+67 s) |

Host epoch verified by independent arithmetic before use: 1767225600
(2026-01-01) + 20 390 400 s (236 d) + 62 228 s = 1787678228. Matches the
printed date string exactly.

**Why the readbacks count.** Each returns a time *later* than the value set. A
stale or echoed value would return the identical timestamp; an advancing clock
is a live clock. This is the set-then-verify discipline the bare-metal harness
applies to `SPI1_REF_CTRL`, and its absence on the Linux side is what produced
the July mislabeling.

### The power-cycle test — PREDICTED, THEN CONFIRMED

Before the card swap, the prediction was recorded that the ZCU102 ships without
a coin cell and the RTC would not survive power loss.

**After power cycle: `date -u` → `Wed Jan 8 18:25:35 UTC 2025`.**

**RTC DOES NOT PERSIST.** `hwclock -w` succeeded and read back correctly, and
survived zero power cycles. Note it resumes a few minutes later than the prior
boot (18:23:40 → 18:25:35) — it counts up while powered and loses the value at
power-down, rather than resetting to a fixed constant.

> **STANDING RUNBOOK RULE: setting the clock is a mandatory first step of every
> board session, before any capture. It is not a one-time fix.** Any CSV
> written without it carries a `capture_utc` ≈594 days wrong.

Second correction, post-reboot: host `1787684098` = 18:54:58 UTC (verified:
1787684098 − 1787678228 = 5870 s = 1 h 37 m 50 s; 17:17:08 + 1:37:50 =
18:54:58 ✓). Board readbacks 18:55:21 and 18:55:37, both advancing.

The correction landed in the capture: `# capture_utc=20260825_190101`.

---

## 5. Board artifact inventory

**Running image:** `PetaLinux 2025.1+release-S05180137`, console `ttyPS0`. The
card was built with the **LPS** toolchain; the 2025.2 snapshot at Morgan has
produced nothing that runs.

**Kernel:** `6.12.10-xilinx-g0a0f70e531c7`, `#1 SMP Sat May 17 14:01:06 UTC 2025`.

**Rootfs is INITRD** — confirmed directly: `rootfs on / type rootfs`. All rootfs
mtimes read the `Mar 9 2018` placeholder epoch.

### SD card — 58.2 G, single FAT partition, label `BOOT`

Not the multi-partition `.wic` layout described in `JITTER_CAPTURE_RESUME.md`.
This is the **loose-file layout, and it boots reliably here.** The BL31-hang
theory in that document is specific to the LPS card and does not reproduce on
board #2.

Contents at session start (all mtime 2026-08-20, real FAT timestamps
independent of the broken RTC — the whole card was written in one operation):

| file | bytes |
|---|---|
| `BOOT.BIN` | 1 775 880 |
| `boot.scr` | 3 833 |
| `image.ub` | 55 510 056 |
| `spi_benchmark_axi` | 704 072 |
| `spi_benchmark_axi_ext` | 704 048 |
| `spi_benchmark_wrapper.bit.bin` | 26 510 780 |
| `spi_loopback_test` | 74 832 |
| `system.dtb` | 42 130 |

Host and board report these mtimes 4 h apart (11:21 vs 15:21) — FAT stores
local time, host is EDT, board is UTC. Not a discrepancy; it independently
confirms both machines agree on when the card was written.

### Rootfs vs SD — three files differ

| file | rootfs | SD | same? |
|---|---|---|---|
| BOOT.BIN | `/boot/BOOT.bin` 1 783 192 | 1 775 880 | **NO** — 7 312 B apart |
| system.dtb | `/boot/system.dtb` 40 143 | 42 130 | **NO** |
| pl.dtbo | `/boot/devicetree/pl.dtbo` 2 137 | FIT: 2 009 | **NO** — §6 |

Filename case (`BOOT.bin` vs `BOOT.BIN`) is **not** the explanation; the byte
counts differ. The SD copies are what boot.

### Firmware directory absent

`/lib/firmware/` and `/usr/lib/firmware/` **both absent**.
`find / -xdev -name '*.bit*'` returned nothing — control marker printed, so the
command ran; true negative. No bitstream on the root filesystem. Consistent
with an INITRD rootfs rebuilt from `image.ub` each boot.

---

## 6. `/boot/devicetree/pl.dtbo` is the wrong overlay — now measured

`dumpimage -l` on `image.ub`:

```
FIT description: ZCU102 SPI Benchmark spidev.bufsiz=1MB
Created:         Thu May 28 15:53:39 2026
 Image 0 (kernel-1)            Kernel Image, gzip, 11 660 781 B
 Image 1 (fdt-system-top.dtb)  Flat DT, 36 067 B
 Image 2 (fdt-pl.dtbo)         Flat DT, 2 009 B
                               sha256 2912ee463b2f60652dd64fc8009d1836
                                      e8a5c7824008eb26940a753eeb09dfcd
 Image 3 (ramdisk-1)           RAMDisk, 43 809 071 B
 Configuration 1 (conf-pl.dtbo)  PL overlay
```

**`-p 2` CONFIRMED as the overlay index on this image** — previously carried on
trust, now read off the FIT.

**New finding.** FIT overlay = **2 009 B**; `/boot/devicetree/pl.dtbo` =
**2 137 B**. Different files, 128 bytes apart. The record's "unresolved
phandles" warning now has a **measured arithmetic basis**, not only a
remembered caution. The obvious-looking file in the obvious location is wrong.

### Verified extraction — performed twice, deterministic

```
dumpimage -T flat_dt -p 2 -o /tmp/pl.dtbo /run/media/BOOT-mmcblk0p1/image.ub
sha256sum /tmp/pl.dtbo
```

| gate | expected | run 1 | run 2 (post-reboot) |
|---|---|---|---|
| size | 2009 | 2009 ✓ | 2009 ✓ |
| sha256 | `2912ee46…b09dfcd` | ✓ | ✓ |

The hash is recorded **inside the FIT by the tool that built it** and recomputed
by an independent `sha256sum`. This proves the extracted bytes are the intended
overlay, not merely that a file appeared.

Other FIT provenance: `spidev.bufsiz=1MB` is baked into this image; FIT created
**2026-05-28**, six days after the U-Boot script stamp
(`u-boot-xlnx-scr--1.0-r0-20260522150658.scr` → 2026-05-22 15:06:58).

---

## 7. PL programming — reproducible procedure

Tools present: `/bin/dumpimage`, `/bin/fpgautil`. `xmutil` **absent**.

```
fpgautil -b /run/media/BOOT-mmcblk0p1/spi_benchmark_wrapper.bit.bin \
         -o /tmp/pl.dtbo -f Full -n full
```

Invocation taken from `fpgautil`'s own help text, not from memory.

```
fpga_manager fpga0: writing spi_benchmark_wrapper.bit.bin to Xilinx ZynqMP FPGA Manager
OF: overlay: WARNING: memory leak will occur if overlay removed, property: /fpga-region/firmware-name
OF: overlay: WARNING: memory leak will occur if overlay removed, property: /fpga-region/resets
Time taken to load BIN is 235.000000 Milli Seconds     (run 1)
Time taken to load BIN is 234.000000 Milli Seconds     (run 2, post-reboot)
BIN FILE loaded through FPGA manager successfully
```

**The two `OF: overlay: WARNING` lines are BENIGN.** They fire on
`firmware-name` and `resets` whenever a full-region overlay is applied and
concern *teardown*, not load. Recorded so they are not later read as a fault.

The presence of `/fpga-region/firmware-name` confirms the standing finding that
**the overlay programs the PL itself** — no separate `fpga_manager` sysfs write
is required.

**Executed twice on two independent boots with identical results.** That is
what makes this a runbook step rather than a session anecdote.

---

## 8. Controller identity — established from hardware, twice

| | before `fpgautil` | after |
|---|---|---|
| `ls -l /dev/spidev*` | `No such file or directory` | `crw------- 153, 0 /dev/spidev1.0` |

One controlled change between two reads, on both boots. Confirms **PL state
does not survive a power cycle** and must be reapplied every boot.

```
/sys/class/spidev/spidev1.0 ->
  ../../devices/platform/axi/a0000000.axi_quad_spi/spi_master/spi1/spi1.0/spidev/spidev1.0
```

**`/dev/spidev1.0` is the AXI Quad SPI at `0xA000_0000`.** Identity comes from
the kernel's own device hierarchy — platform device, `spi_master`, child — not
from a filename and not from a speed request the driver is free to acknowledge
and ignore.

**The falsifier was written down before the read:** resolution through
`ff050000.spi` or any Cadence PS node would have contradicted the record and
halted the session. It did not appear, on either boot.

> **Binding consequence:** every number captured through `/dev/spidev1.0` is a
> **Linux AXI Quad SPI** number. Not PS SPI1. Not a same-wire OS-tax comparison
> against the bare-metal PS results. No CSV or commit may imply otherwise.

---

## 9. Transfer — SD card, gated at four hops

The board has **no network path** (§13). The SD card is the project's
established transfer method and was used.

```
repo → host copy → SD (FAT) → board FAT read → board /tmp
```

| hop | md5 | size |
|---|---|---|
| `linux/src/spi_benchmark_v2_aarch64` (repo) | `ff194b3828edc13d06ba26ef816c8616` | 94 544 |
| `/media/opentitan/BOOT/…` (host, after `sync`) | same ✓ | 94 544 |
| `/run/media/BOOT-mmcblk0p1/…` (board) | same ✓ | 94 544 |
| `/tmp/…` (board, `chmod +x`) | same ✓ | 94 544 |

`sync` before every hash so the value reflects flash, not page cache — a hash
read back through a dirty cache is a check that cannot fail.

Card identified **by difference**: baseline `lsblk` taken before insertion
showed no removable device; `mmcblk0` (58.2 G, label `BOOT`) appeared after.
Contents then matched the board's own listing on all eight files. Unmounted
with `umount` and verified to show no mountpoint before removal.

The repo md5 corroborates the `ff194b38…` prefix in the prior record — this is
the tracked binary, not a stale local build.

---

## 10. CAPTURE — first identity-verified Linux SPI dataset

```
/tmp/spi_benchmark_v2_aarch64 /dev/spidev1.0 2>&1 | tee /tmp/run_log.txt
```

**Artifacts** (copied to SD, hash-verified both sides):

| file | md5 |
|---|---|
| `spi_bench_spidev1.0_20260825_190101.csv` | `c666c299daa53ebc2858a8e23ea107aa` |
| `run_log.txt` | `b9f1b772b8db60e735e32de628c385c7` |

### The driver's speed lie, caught in the act

```
Speed requested: 1000000 Hz
Speed readback:  1000000 Hz          <- driver echoed the request
ACHIEVED: 65536 B in 48178.19 us = 10.88 Mbps
WARNING: achieved rate FAR EXCEEDS request -- the driver ignored
         the speed request. Do NOT label this capture with the
         requested rate.
```

This is the exact July failure mechanism firing live, and this time the harness
caught it. **A driver can echo a request; it cannot fake elapsed time.**

### Results — 11 payloads × 1000 trials

```
bytes,min_us,max_us,avg_us,stddev_us,cpu_pct,nvcsw,nivcsw,err_count
1,10.241,52.795,14.816,3.867,82.20,526,0,0
8,19.352,41.674,24.199,2.357,61.98,1000,0,0
16,25.202,37.724,27.552,1.172,55.53,999,0,0
64,60.166,79.228,62.674,1.524,28.64,1000,0,0
128,106.871,120.662,109.491,1.285,19.66,1000,0,0
256,200.010,213.421,202.729,1.416,13.93,1000,0,0
512,388.329,401.090,391.060,1.378,7.28,1000,0,0
1024,764.556,776.257,767.542,1.248,3.77,1000,0,0
4096,3022.212,3040.454,3026.348,1.491,1.04,1000,0,0
16384,12054.114,12067.605,12057.820,1.170,0.31,1000,0,0
65536,48172.223,48321.008,48178.186,6.266,0.12,1000,0,0
# achieved_mbps_at_65536B=10.88
```

Full 12-column form (including `cpu_us`, `wall_us`, `first_errno`) is in the
committed CSV.

**`err_count=0` on every payload.** See the loopback caveat below for what this
does and does not mean.

**`nivcsw=0` on every payload** — zero involuntary context switches across
11 000 trials under `SCHED_FIFO`. This is a determinism datum and the first
2.f-adjacent measurement in the project.

**`nvcsw=526` at 1 B** against 999–1000 everywhere else. Unexplained. Recorded,
not rationalized.

### Reproduces the July AXI capture

| payload | `axi_internal_results.csv` | today | delta |
|---|---|---|---|
| 16 B | 27.530 | 27.552 | 0.08% |
| 128 B | 109.521 | 109.491 | 0.03% |
| 256 B | 202.73 | 202.729 | **exact** |
| 65 536 B | 48 185.95 | 48 178.186 | 0.016% |
| Mbps @ 64 K | 10.880 | 10.88 | — |

**8 B is the sole outlier:** 20.429 (July) vs 24.199 (today), ≈18% apart, while
every other payload agrees within 0.1%. **Unexplained.** Noted, not explained
away.

### CAVEAT — `SPI_LOOP` was REJECTED

```
spidev spi1.0: setup: unsupported mode bits 20
warning: could not set SPI_LOOP (continuing): Invalid argument
# mode_readback=0x00 spi_loop=0
```

Mode bit `0x20` is `SPI_LOOP`. **The `xilinx_spi` driver does not implement
internal loopback.** The harness warned and continued by design (source L354
prints `NOT SET -- loopback must be in hardware`).

**What this does and does not affect.** Timing is unaffected — the transfer
still clocks the full payload. **Data integrity is unverified:** `err_count=0`
means the ioctl returned success, **not** that TX matched RX. No claim that
transmitted bytes were received may be made from this run unless a physical
loopback is confirmed on the PMOD header.

**It also casts doubt on an existing filename.** The July harness set
`SPI_LOOP` against this same driver and would have hit the identical rejection.
`axi_**internal**_results.csv` is named for a loopback mode that appears
unavailable on the AXI path. **Flagged for verification, not concluded.**

---

## 11. Clock chain measured on board #2 — both CRL_APB questions addressed

```
devmem 0xFF5E00C0   ->  0x01010600      (PL0_REF_CTRL)
devmem 0xFF5E0080   ->  0x01001800      (SPI1_REF_CTRL)
```

**`PL0_REF_CTRL = 0x01010600`**

| bits | field | value |
|---|---|---|
| [2:0] | SRCSEL | 0 → **IOPLL** |
| [13:8] | DIVISOR0 | **6** |
| [21:16] | DIVISOR1 | 1 |
| [24] | **CLKACT** | **1** |

IOPLL 1500 ÷ 6 ÷ 1 = **PL0 250 MHz** → ÷16 (synthesis-frozen C_SCK_RATIO)
= **AXI SCK 15.625 MHz**.

**Open question #1 ANSWERED:** bit 24 is **CLKACT** (clock enable), set. Not a
divisor artifact.

**`SPI1_REF_CTRL = 0x01001800`** → SRCSEL IOPLL, **DIVISOR0 = 24**,
DIVISOR1 = 0, CLKACT set. 1500 ÷ 24 = **62.5 MHz** → ÷64 prescale
= **0.9766 MHz**.

**Ratio confirmed on board #2: 15.625 / 0.9766 = 16.0×.** Board #1's chain is
no longer being extrapolated — board #2 is measured, in the same session as the
capture, on the same PL image.

**Two things NOT resolved:**

- **DIVISOR1 = 0 on SPI1** but 1 on PL0. The 62.5 MHz arithmetic requires 0 to
  behave as ÷1 (bypass). Open question #2 is **sharpened, not closed**.
- **`0x01001800` is the value the bare-metal code force-writes** to correct the
  FSBL. Reading it under Linux on a fresh boot means either this card's FSBL
  already sets DIVISOR0=24, or the design documents' "DIVISOR0=6 at boot" claim
  is wrong for this build. **Flagged, unresolved.**

---

## 12. Defects

### D-A · `JITTER_CAPTURE_RESUME.md` publishes a build command that cannot run

Its SUPERSEDED header — the file's *current* guidance — prints:

```
aarch64-linux-gnu-gcc -O2 -Wall -Wextra -o spi_benchmark_jitter_aarch64 \
  linux/src/spi_benchmark_jitter.c -lm
```

`linux/src/spi_benchmark_jitter.c` **does not exist**; commit `f4e8237` renamed
it to `spi_benchmark_v2.c`. The document a person opens to resume this work
hands them a command that fails on a missing file, and names an output binary
that is now the older of the two tracked binaries.

### D-B · `LINUX_JITTER_PROVENANCE.md` §6 overstates — NARROWED

Original finding: §6 counts three AXI captures as a "Valid result" while §8
states of one of them *"NOT CLAIMED: that this file is the AXI controller"*.
§8's stated disqualifier is the absence of a `# device=` header — and measured
across `results/`, `grep -l 'device=' *.csv` returned **no matches**. No results
CSV in the repository carries a provenance header, so the disqualifier is not
discriminating and, applied evenly, hits all three files §6 counts.

**NARROWED by today's capture.** `axi_internal_results.csv` now has an
**identity-verified twin** reproducing it to ≈0.02% across seven weeks, a
different board, and a fresh PL load. That is far stronger corroboration than
throughput inference. D-B stands cleanly against
`unidentified_internal_results_20260708_1319.csv`; it is substantially weakened
against `axi_internal_results.csv`.

### D-C · Forced password change fires on EVERY boot — worse than recorded

Observed on **both** boots this session: logging in as `petalinux` triggers
`You are required to change your password immediately (administrator
enforced)`. Because the rootfs is INITRD and rebuilt from `image.ub` each boot,
`/etc/shadow` resets and the change never persists. This is not a first-login
event; it recurs indefinitely until fixed in the image. Any runbook omitting it
strands the next person, every single time.

### Record correction (not a defect)

`linux/src/build.sh` **already carries** the `XILINX_ROOT` portability patch —
commit `a00a522`, 2026-08-20. Prior notes listed it as owed. **CLOSED.**

### Source observation

`spi_benchmark_v2.c` L50 still defines
`SPI_DEVICE_DEFAULT "/dev/spidev0.0"` as the no-argument fallback — the retired
harness's hardcoded node. Harmless while the device is always passed
explicitly (L238), but it is the July filename ghost still resident in the
code. Running with no arguments produces
`Failed to open SPI device: No such file or directory`, not a usage message.

---

## 13. Network — still no path to the board

| read | result |
|---|---|
| board `ip -4 addr show` | `lo` only; `end0` has **no IPv4 address** |
| board `operstate` | `up` (carrier, 1 Gbps per boot log) |
| board `udhcpc -i end0 -n -q` | 3 × discover → **`no lease, failing`** |
| host `ip -br addr` | `enp3s0` = `172.20.71.59/24`; `wlp4s0` DOWN; **no second NIC** |

The host holds a campus DHCP lease; the board, on a link with carrier, got none.
**`scp` unavailable.** Worked around via SD card (§9) — which is the project's
established transfer method and cost roughly five minutes including the
re-establish sequence.

Options if a live link is wanted later: USB-Ethernet adapter on
`bxqp8b3-ub22` with static addressing on a private subnet (no IT dependency),
or a campus allocation for the board from Vinton. Assigning a static address in
`172.20.71.0/24` without an allocation risks a collision.

---

## 14. DELIBERATELY NOT CLAIMED

- **No data-integrity claim.** `SPI_LOOP` was rejected; `err_count=0` means the
  ioctl succeeded, not that TX matched RX. Physical loopback on the PMOD header
  was **not** confirmed.
- **No SCK measurement.** 15.625 MHz is **derived** from `PL0_REF_CTRL` and the
  synthesis-frozen ÷16. No scope, no ILA, no wire-side observation.
- **The 8 B outlier (20.429 → 24.199) is UNEXPLAINED.**
- **`nvcsw=526` at 1 B is UNEXPLAINED.**
- **DIVISOR1=0 bypass semantics assumed, not verified** (§11).
- **The FSBL/`SPI1_REF_CTRL` contradiction is unresolved** (§11).
- **Neither `BOOT.BIN` was hashed.** The record's `a25d6549` was not verified
  against either copy, and which copy it refers to is unknown.
- **`image.ub` was not hashed.** The record's `ffe0c75b` is unverified this
  session.
- **`spi_benchmark_axi`, `spi_benchmark_axi_ext`, `spi_loopback_test` on the SD
  card are of UNKNOWN provenance** (704 072 / 704 048 / 74 832 — matching
  nothing in `linux/src/`). They were **NOT RUN**. Running an unidentified
  binary and attributing its output would reproduce the July failure in a new
  form.
- **That the board's Ethernet is on a different segment is an INFERENCE** from
  host-leased / board-not-leased. The cable was not traced.
- **PetaLinux 2025.2 acceptance of a 2025.1 XSA is UNTESTED. Nothing was
  built.**
- **The `/boot` vs SD file differences are unexplained** — sizes compared,
  contents not diffed.
- **No bare-metal comparison is drawn.** Linux cannot reach PS SPI1 (ATF wall);
  this capture is AXI-only and is not an OS-tax measurement.

---

## 15. Next session — ordered

1. **Fix D-A** — one-line correction to `JITTER_CAPTURE_RESUME.md`.
2. **Restate D-B** in `LINUX_JITTER_PROVENANCE.md` §6 to the strength §8
   supports, incorporating today's corroborating capture.
3. **Confirm or deny physical loopback** on the PMOD header. Until then no
   integrity claim attaches to any AXI capture, including July's.
4. **2.f — START IT.** Still not started, still the schedule risk. Needs runs
   across governor / preemption / IRQ-affinity settings. Today's capture is the
   baseline configuration point; `uname_v` in the header carries the preemption
   string, so step-2 captures remain attributable after the fact.
5. **2.a headline restatement** on AXI controller identity, now supported by a
   same-session pairing of live `PL0_REF_CTRL` and measured 10.88 Mbps.

### Reproducible bring-up sequence — established and executed twice

```
set clock  ->  date -u readback  ->  hwclock -w -u  ->  hwclock -r -u readback
dumpimage -T flat_dt -p 2 -o /tmp/pl.dtbo <image.ub>
sha256sum /tmp/pl.dtbo                    # gate: 2912ee46…b09dfcd, 2009 B
fpgautil -b <bit.bin> -o /tmp/pl.dtbo -f Full -n full
ls -l /dev/spidev*
ls -l /sys/class/spidev/                  # gate: a0000000.axi_quad_spi
md5sum <binary>                           # gate: ff194b38…
```

The last identity step is not bookkeeping. It is the step whose absence
produced `LINUX_JITTER_PROVENANCE.md`.
