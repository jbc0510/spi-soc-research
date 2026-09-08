# SOW 2.f STARTED — CPU frequency sweep, ZCU102 #2

Measured at Morgan, `bxqp8b3-ub22`, 2026-09-08. MSU-2 Task 2, IAC/TAT P1-22-2393.
Repo commit `e042277` at time of measurement.

**This is the first SOW 2.f work in the project.** 2.f is OS tuning and
determinism analysis; it had not been started before today.

Raw evidence: `docs/environment/zcu102-2_2f_freqsweep_20260908.log`
(20480 bytes, md5 `8c53c1a35c9404293adeb3a59332e37e`) — one `script(1)` capture
covering all four runs, the frequency setpoints, and the shutdown.

## THE RESULT

**The fixed per-transfer cost is a fixed quantity of CPU work. The per-byte
cost is very nearly not.**

Four CPU frequencies, one boot, one PL load, one identity verification,
1000 trials per payload, 11 payloads each.

| CSV | CPU | intercept | slope µs/B | achieved Mbps | 64 KB stddev |
|---|---|---|---|---|---|
| `…141830` | 1200 MHz | 15.68 µs | 0.73456 | 10.89 | 3.87 µs |
| `…142131` | 600 MHz | 30.67 µs | 0.75494 | 10.59 | 5.17 µs |
| `…142536` | 400 MHz | 45.73 µs | 0.77886 | 10.26 | 8.65 µs |
| `…142923` | 300 MHz | 60.78 µs | 0.80153 | 9.97 | 14.23 µs |

Intercept and slope are a least-squares fit of `t = intercept + slope·N` over
payloads >= 512 B, where the wire term dominates.

### The fitted law

```
intercept = 18042 / f_MHz  +  0.62 µs        R^2 = 1.00000
```

Four points, two parameters, R^2 = 1 to five decimal places.

Read physically: roughly **18,000 CPU cycles** of fixed software work per
transfer — syscall, driver setup, controller programming — plus **0.62 µs**
that does not scale with CPU frequency at all. That residual is the genuinely
hardware-bound part of the fixed cost.

**A prediction was recorded before the last two runs were taken:** intercept
~46 µs at 400 MHz and ~61 µs at 300 MHz, from the 1200/600 pair alone.
Measured 45.73 and 60.78 — within 0.6% and 0.4%. The law was predictive, not
merely descriptive.

### The slope is not perfectly CPU-independent

Slope drift across a 4x CPU range: 0.73456 -> 0.80153 µs/B, **+9.1%**.

Small, monotonic, and consistent with the driver **polling** rather than
using interrupts (see below): if the CPU busy-waits on the SPI FIFO, it has
some per-byte involvement, so a slower CPU costs slightly more per byte.

**NOT CLAIMED:** that the +9.1% is fully explained by polling. It is
consistent with polling. No instrumentation was added to attribute it.

## JITTER SCALES WITH CPU FREQUENCY — AND IT IS NOT PREEMPTION

Unpredicted, and directly on the SOW 2.f determinism question.

64 KB payload standard deviation: **3.87 -> 5.17 -> 8.65 -> 14.23 µs** across
1200 -> 600 -> 400 -> 300 MHz. Monotonic, roughly **3.7x growth over a 4x
frequency reduction**.

**`ivcsw = 0` on every row of all four captures.** Zero involuntary context
switches across 44,000 timed trials in this session.

So the growing variability is **not** the scheduler preempting the
measurement. With preemption excluded by measurement, the remaining candidate
is the polling loop's own timing spreading out as cycles become scarce.

**NOT CLAIMED:** that the polling loop is the cause. What is established is
that jitter grows as CPU frequency falls and that preemption is excluded.
Attributing the mechanism requires instrumentation not present in this harness.

`err_count = 0` on every row of all four captures.

## TWO OF THE THREE ANNOUNCED AXES ARE NOW SETTLED

The August MSR named three axes for September: preemption model, interrupt
handling, and CPU frequency scaling.

**CPU frequency scaling — DONE.** Four operating points, runtime-settable via
the `userspace` governor, every setpoint confirmed by readback. This document.

**Interrupt handling — DEAD ON THIS PATH.** Measured with the PL programmed:

```
60:  0  0  0  0  GICv2 121 Edge  a0000000.axi_quad_spi
```

The AXI Quad SPI has an allocated interrupt line and **its count is zero on
all four CPUs**. The `xilinx_spi` driver polls. Changing the affinity of an
interrupt that never fires cannot change anything measurable, so IRQ affinity
is not a viable axis for this controller. Reported rather than quietly dropped.

**Preemption model — NOT REACHABLE WITHOUT A KERNEL REBUILD.**
`grep -i preempt /proc/version` returns nothing; `uname -a` shows `#1 SMP`
with no PREEMPT marker. Changing `CONFIG_PREEMPT*` requires a PetaLinux kernel
rebuild and a new `image.ub`. Deferred, with reason.

## SCHEDULING POLICY IS NOT AVAILABLE ON THIS ROOTFS

An earlier plan proposed comparing `SCHED_OTHER` against `chrt -f 80`.
**That plan cannot run here.** Measured:

```
which chrt taskset nice          -> nothing
busybox --list | grep -x -E 'chrt|taskset|nice'   -> rc=1
```

None of the three exists, including inside busybox. A scheduling-policy axis
needs a rootfs rebuild. Recorded so the plan is not proposed again.

## PROVENANCE

Standard bring-up, all gates passed before any measurement:

```
bitstream  61f2c33f6ce6138eee81a862a466ae4e   card == board /usr/lib/firmware
overlay    2009 B, FIT sha256 2912ee463b2f60652dd64fc8009d1836e8a5c7824008eb26940a753eeb09dfcd
           extracted with dumpimage -T flat_dt -p 2; index confirmed by the
           builder-recorded hash, not assumed
identity   /sys/devices/platform/axi/a0000000.axi_quad_spi/spi_master/spi1/spi1.0/spidev/spidev1.0
           AXI Quad SPI at 0xA000_0000. NOT PS SPI1. Fourth independent boot.
binary     ff194b3828edc13d06ba26ef816c8616   repo == host == SD == board tmpfs
```

Capture md5s, board tmpfs == SD after sync == repo:

```
fc0677853b86a34bdc62f7fba7a7d17b   spi_bench_spidev1.0_20260908_141830.csv
597789e3330c122f3fe2f903293b6f50   spi_bench_spidev1.0_20260908_142131.csv
d8f8e7ce81b15e418ab92b7125bd0225   spi_bench_spidev1.0_20260908_142536.csv
15c87618a7f538dab6612a8560b94948   spi_bench_spidev1.0_20260908_142923.csv
```

Board clock set as the first action after login (`date -u -s`, `hwclock -w -u`,
verified by readback). RTC on this board does not persist across power-off.

Board restored to 1200 MHz before shutdown; filesystems synced and unmounted.

## THE CSV↔FREQUENCY MAPPING, SOURCED FROM THE LOG

**The CSV header does not record CPU frequency.** It records kernel, host,
device, requested speed, bufsiz — nothing about the operating point. The four
files are therefore distinguishable only by filename timestamp and by this log.
**The log is load-bearing evidence, not a supplement.**

Mapping established from log line numbers:

| readback line | value | following ACHIEVED | CSV |
|---|---|---|---|
| 76 | 1200000 | 107 -> 10.89 Mbps | `…141830` |
| 117 | 600000 | 148 -> 10.59 Mbps | `…142131` |
| 158 | 400000 | 189 -> 10.26 Mbps | `…142536` |
| 199 | 300000 | 230 -> 9.97 Mbps | `…142923` |
| 265-266 | 1200000 | — | restore before shutdown |

**HARNESS DEFECT, for a later session:** a capture should state its own
operating point. Adding a `cpu_freq_khz` header line would make each CSV
self-describing and remove the dependency on an external log. NOT changed
today: editing the harness mid-experiment would alter the binary and break the
`ff194b38` chain that ties these four captures to every prior capture.

## METHOD NOTES — TWO DEFECTIVE PROBES, RECORDED

**1. Anchored grep against a picocom log.** `grep -E '^[0-9]{6}$'` returned
nothing and looked like absence. Two faults: the log is `script(1)` output
through picocom, so lines end `\r\n` and `$` cannot match; and 1200000 is seven
digits, not six. `cat -A` showed line 76 as `pidev1.01200000^M$` — the value is
present but preceded by echoed input from the previous command, so `^` also
fails. **Rule: picocom-under-script logs interleave echoed input with output.
Do not anchor matches to line boundaries in them.**

**2. Commands pasted at the wrong prompt.** Two `md5sum` invocations against a
host path ran at the board prompt and failed with
`/root/msu2-verify/...: can't open`. Nothing was mis-measured, but this is the
third occurrence this week; the inventory session earlier today lost its log to
the same cause (`script: command not found` on the board). **Rule: check the
prompt before pasting a path.**

## DELIBERATELY NOT CLAIMED

- **That 2.f is complete.** It is not. One axis of three has been swept.
- That the +9.1% slope drift is fully explained by polling. Consistent with,
  not attributed.
- That the polling loop causes the jitter growth. Preemption is excluded by
  measurement; the mechanism is not established.
- That these results transfer to PS SPI1. That controller remains unreachable
  from Linux (ATF domain restriction).
- That the achieved Mbps reflects the requested rate. It does not — the driver
  ignores the speed request and the harness warns on every run.
- That anything was measured about bare-metal. Nothing was.
- That the CPU frequency change affects only the driver. At lower frequencies
  the harness's own measurement code is also slower. This does not confound
  the intercept-vs-slope separation but it is present in the absolute numbers.

## SOW POSITION

**SOW 2.f moves from NOT STARTED to STARTED.** One of three announced axes is
swept with a fitted, predictive law; a second is shown to be inapplicable on
this path with the measurement that shows it; the third is scoped to a kernel
rebuild.

2.f is not complete. 2.g remains DESIGN LOST and NOT IMPLEMENTED.
2.e Linux side remains EXECUTED; bare-metal side NOT WRITTEN.

## REPRODUCE

Standard bring-up (see `docs/environment/BRINGUP_ZCU102_2_20260820.md`), then:

```
for f in 1200000 600000 400000 300000; do
  echo $f > /sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed
  cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq
  ./spi_benchmark_v2_aarch64 /dev/spidev1.0
done
echo 1200000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed
```

The governor is already `userspace` and it is the only one available. All four
cores share one policy. ~66 s per run, ~4.5 min total.
