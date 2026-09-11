# CONTINUATION PROMPT — MSU-2 Task 2, after the 2026-09-11 LPS session

Paste this whole file as the first message of a new conversation.

---

## CADENCE CHANGE — read this first

**From now on, Morgan sessions are 4 hours minimum, every day, and they are
gap-attack sessions.** The project is past the midpoint of a 12-month period of
performance and one deliverable window is already open with work incomplete
inside it. Sessions that produce only documentation, tooling or investigation
must be named as such at the outset and justified against the gap list in
§TIMELINE.

Do not let a session drift into interesting side work. Today's QSPI session was
scientifically good and contractually marginal — it advanced 2.e by a side door
while 2.d and the 2.e bare-metal harness, both inside an open deliverable
window, went untouched. Name that tradeoff out loud when it happens.

## STATE

Repo `jbc0510/spi-soc-research`, branch `feature/dma-benchmarking`.
**HEAD `bb42c45`, pushed.** Verify with `git log`, do not trust this line.

Jerry Conway, graduate researcher, Morgan State CAP Center. MSU-2, "Exploring
System on Chip Architectures", IAC/TAT P1-22-2393, **Task 2**. Sole researcher.
PI Dr. Kevin Kornegay. Sponsor Booz Allen / LPS. Booz Allen POC Monica Hill.
LPS lead Lucia Jesus Santana.

Core question: **OS vs bare-metal SPI performance on a Xilinx ZCU102.**

### Sites and machines

| site | machine | role |
|---|---|---|
| Morgan | `bxqp8b3-ub22` (Ubuntu 22.04.5, login `opentitan`) | board #2, clone at `~/msu2-verify/spi-soc-research` |
| LPS | `stile` (login `jconway`) | board #1 **console only**, `/dev/ttyUSB0`, clone at `~/spi-soc-research` |
| LPS | `jeremiahc` (login `jeremiahc`) | **laptop — SD card flashing and network**, clone at `~/spi-soc-research` |

`stile` is NOT a supported PetaLinux host (24.04.4). Morgan (22.04.5) is.
GitHub is the only transfer path between sites. Board has no network; host↔board
transfer is by SD card or console paste.

**Three clones exist. Check `rev-list --count origin..HEAD` on each before
pulling.** On 2026-09-11 `jeremiahc` was 78 commits behind and `stile` 17 behind;
both were clean, but that was verified, not assumed.

## TIMELINE — the actual pressure

12-month PoP from March 2026. **Month ~6.5 of 12.**

| deliverable | due | state |
|---|---|---|
| Monthly Status Report | monthly, 5th working day | ongoing; September MSR due early October |
| Interim Progress Report | month 4 | **SUBMITTED** |
| Sim/emulation results + code — incl. **2.d, 2.e** | months 5–8 (Aug–Nov 2026) | **WINDOW OPEN NOW, PENDING** |
| OS tuning + appliance — **2.f, 2.g** | month 9 (Dec 2026) | ~11 weeks |
| Final Technical Report | 15 days before end (~Feb–Mar 2027) | ~22 weeks |

### The two things that are not engineering problems

1. **Task 1 has nobody assigned.** The 5–8 month deliverable bundles Jerry's
   2.d/2.e with Task 1's RTL items (1.b, 1.c, 1.d). That package cannot be
   complete regardless of what Task 2 delivers. **This needs to be in writing to
   the PI and Booz Allen.** As of 2026-09-11 it has not been.
2. **The August MSR deliverables-table clarification was never answered.** A
   March annotation about two no-longer-requested items is ambiguous and
   materially affects what is owed. Monica Hill has since reached out saying she
   has questions — re-ask this when replying to her.

## GAP LIST — attack in this order

### Tier 1 — inside an OPEN deliverable window

- **2.d fault handling.** Hardened, **never run on hardware.** Needs
  `CONFIG_WDT=y` + `CONFIG_WDT_CDNS=y` and a U-Boot rebuild. Driver and DT nodes
  confirmed ready. Both `cdns-wdt` instances probe under Linux
  (`fd4d0000.watchdog` 60 s, `ff150000.watchdog` 10 s).
- **2.e bare-metal harness. NOT WRITTEN.** The Linux side is executed and
  corroborated. This is the largest single unwritten deliverable item.

### Tier 2 — December

- **2.f preemption axis.** ONE axis remains, not two. CPU frequency scaling is
  done (fitted law, R²=1.00000). Interrupt handling is closed as a documented
  negative (AXI Quad SPI interrupt count is zero at all four setpoints;
  `xilinx_spi` polls). **Two builds, not one** — see THE ONE BUILD.
- **2.g Verification leg.** `CONFIG_FIT_SIGNATURE` at ZERO, untouched.
- **2.g provisioning.** Rootfs is INITRD; `libubootenv-bin` not in it. 2.g is a
  demonstration, not a deployable appliance.

### Tier 3 — repo only, no board, no build

- 4 files still open from the clock triage (`a23f32b`):
  `spi_benchmark_clean.c` (prints a false SCK at runtime),
  `block_design_review.md`, `ILA_SCK_MEASUREMENT_PLAN.md`,
  `compare_spi.py:7` (clarity defect).
- `SESSION_RECAP_20260909.md:141` says the triage spans "six files". It is
  sixteen. Amend when next touching that file.
- `recon_host.sh` five defects; LPS baseline recapture.
- 2.a headline restatement on AXI controller identity.

### THE ONE BUILD — highest-leverage move available

Four outstanding items are all PetaLinux-build-gated and the gates overlap:

    2.f preemption      CONFIG_PREEMPT*            kernel
    2.g provisioning    libubootenv-bin            rootfs
    2.g verification    CONFIG_FIT_SIGNATURE       U-Boot + signing keys
    2.d watchdog        CONFIG_WDT, CONFIG_WDT_CDNS  U-Boot

**Sequence is fixed by the lineage caveat:** stock rebuild FIRST, demonstrate it
reproduces current behaviour, THEN one build carrying all four changes. Skipping
the stock rebuild varies preemption model and build lineage at once and measures
neither.

    project images/linux/image.ub   1427571b143b66bfc8433fed1ff20d3b
    board   (SD card) image.ub      ffe0c75b60f043a48e585377fce44202

The running image reports **PetaLinux 2025.1**; the project tool is **2025.2**.
Different TOOL VERSION, not merely a different build instance.

## ESCALATIONS — outrank documentation cleanup

**E-1. The retraction mechanism and the benchmark build disagree.**
`results/Clash_clock_answers.md:38` records the 14.2× build as PL0 divisor 10 →
99.99 MHz → SCK 6.25 MHz. The August MSR explains the 14.24× retraction as a
**16.0× clock artifact**, which requires PL0 = 250 MHz. At PL0 = 100 the ratio is
~6.4× and 14.24× cannot be a clock artifact. Both cannot be true of one dataset.
Needs the bitstream provenance of the 14.2× capture. **Bears on a claim already
delivered to the sponsor.**

**E-2. Does an ILA SCK capture exist?**
`CLOCK_DISCREPANCY_FINDINGS.md:120` records an "ILA verdict (Jun 3): SCK = 6.25
MHz exactly". `SESSION_20260825_MORGAN.md:567` and `README.md:20` both state
there has been NO SCK measurement. One is wrong. Determines whether 15.625 MHz
rests on one line of evidence or two.

**E-3. Does QSPI reopen 2.c?**
2.c's same-controller Linux-vs-bare-metal comparison is closed as structurally
impossible because ATF blocks APU access to PS SPI1. **The QSPI controller at
`0xFF0F0000` is NOT blocked** — as of 2026-09-11 it is reachable from Linux with
`/dev/mtd0`. Whether it can carry that comparison is UNTESTED. If it can, a
closed SOW activity reopens. Scope this before committing to the December build.

## SOW STATUS

| task | state |
|---|---|
| 2.a performance characterization | substantially done; headline must be restated on AXI controller identity |
| 2.b DMA | PIO done; ZDMA closed as documented negative; PL CDMA simulation only |
| 2.c OS vs bare-metal | bare-metal done; Linux side closed as structurally impossible — **but see E-3** |
| 2.d fault handling | hardened, **NEVER RUN**. Tier 1 |
| 2.e test harness | Linux executed; QSPI clock work added 2026-09-11; **bare-metal side NOT WRITTEN**. Tier 1 |
| 2.f OS tuning / determinism | 1 of 3 axes remains (preemption). Two builds |
| 2.g secure appliance | Robustness DEMONSTRATED and reproduced cross-site. Verification at ZERO. Not provisioned |

## WHAT 2026-09-10/11 ESTABLISHED

### 2.g cross-site reproduction — `ce122b0`

Demo runbook's "reproduction from a clean clone is UNTESTED" is now tested.
ZCU102 #1 at LPS, from a pull of `44e8716`, no local modifications. Two
independent trials in `artifacts/2g-fwenv/zcu102-1_2g_demo_20260911.log`
(`a4e42be938786bf26a930d57acadc5fc`).

- `msu2_probe` absent + `msu2_marker` present → fell back to the primary, not to
  compiled-in defaults.
- **Silent recovery confirmed on a second board.** `Loading Environment from
  FAT... OK` on both trials, identical to a healthy boot.
- `bootdelay=5` countdown renders identically: raw bytes `: 5 \b\b\b   0`.
- Fallback now: 3 trials, 2 boards.

**Board #1's card had only ONE environment copy on arrival** —
`uboot-redund.env`, `5b2408144a8ad75e827feae14fdf4290`, identical to board #2's
`pre-fwsetenv-20260908` snapshot. The pair was created by writing both copies
from the committed `armed-20260909` snapshots. So this reproduces the RECOVERY
BEHAVIOUR on different hardware, not the whole chain from a board that
independently had a pair. **Why `saveenv` yields one file on board #1 and two on
board #2 is unexplained.**

No post-boot hash was taken on board #1, so **no-self-heal is confirmed on board
#2 only.**

### 2.e QSPI clock ceiling — `bb42c45`

Full note: `results/SOW_2E_QSPI_CLOCK_20260911.md`
(`226efaf7c8c9df50d8eb592a81014972`). Log:
`artifacts/2e-qspi/zcu102-1_qspi_recon_20260911.log`
(`6e12b83c860901a5ce422a1578d93005`).

**The QSPI flash was unreachable from every software layer.**
`/axi/spi@ff0f0000/flash@0` has NEITHER `compatible` NOR `reg`. Linux: "cannot
find modalias". U-Boot `sf probe`: `Invalid chip select 0:0 (err=-19)`. Both
consume the same broken node. Kernel config was never the problem.

**Fixed by a 394-byte device-tree overlay, NO REBUILD.**
`hardware/overlays/qflash_probe.dts`, compiled dtbo md5
`2099a8d6a0b5765c9460a5ac8b19a0d8`. Adds a NEW child at the same chip-select —
property edits to the existing node do not re-trigger the SPI core's OF
notifier, which fires on node ADDITION. Result: `/dev/mtd0`, `/dev/mtd0ro`,
`/dev/mtdblock0`; `spi0.0` binds `spi-nor`; 64 MiB, 64 KiB erase.

Clock sweep, 1 MiB at flash `0x100000`, baseline
`b4014a90c5187987c47ae375f33e5e91`:

| divisor | SCK MHz | time | overhead | result |
|---|---|---|---|---|
| /16 | 15.623 | 0.577 s | +7.5% | match |
| /8 | 31.247 | 0.309 s | +15.1% | match |
| /4 | 62.494 | 0.180 s | +34% | match |
| /2 | 124.987 | 0.098 s | +46% | **MISMATCH** |

**Corruption is ADDRESS-dependent, not LENGTH-dependent.** A 1 MiB read at
`0x200000` is byte-identical at both 62 and 125 MHz. A 64 KiB read at
`0x1D0000` is stable at 62 and unstable at 125. Unstable regions at 125 MHz:
**`0x1D0000`–`0x1FFFFF` (192 KiB contiguous)** and **`0x380000`**.
**There is no payload ceiling.**

Highest clock clean everywhere tested: **62.494 MHz**.

## ESTABLISHED — do not re-litigate

- **`spidev1.0` is the AXI Quad SPI** (`0xA000_0000`), not PS SPI1. Four boots.
- **PS SPI1 is unreachable from Linux.** ATF/TrustZone. Architectural.
- **Clock chain:** IOPLL 1500 MHz → PL0 250 MHz (÷6) → AXI SCK 15.625 MHz;
  SPI1 ref 62.5 (÷24) → PS SCK 0.9766 MHz. **Ratio 16.0×.**
- **The 14.24× advantage was a 16.0× clock artifact.** Withdrawn in August.
- **`xilinx_spi` accepts a speed request and ignores it**; `C_SCK_RATIO = 16`
  frozen at synthesis.
- **QSPI `qspi_ref` = 249,975,000 Hz**, IOPLL ÷6 — same chain as PL0. GQSPI
  divides by powers of two only: /2 /4 /8 /16 /32. Driver picks the largest
  divisor ≤ `spi-max-frequency`, so a 10 MHz request yields 7.81 MHz.
- **Board #1 boots SD.** `modeboot=sdboot`. QSPI flash is dormant.
- **Latency model at 1200 MHz:** t ≈ 15.7 µs + 0.735 µs/byte.
  2.f fitted law: `intercept = 18042 / f_MHz + 0.62 µs`, R² = 1.00000.
- **`chrt`, `taskset`, `nice` do not exist**, including busybox. Do not propose
  a scheduling-policy axis again.
- **IRQ affinity is a dead axis.**
- **Rootfs is INITRD.** `/tmp`, `/etc`, password changes, applied overlays all
  reset on power cycle.
- **RTC cold value is 1970**, not 2025-01-08. systemd then advances to the image
  build date, which is where 2025-01-08 comes from. **`hwclock -w -u` does not
  survive a power cycle at all** — accepted and lost.
- **FAT mtimes are not uniformly bogus** — depends on whether the clock was set
  before the write. Hashes only, always.
- **`fw_setenv` success is NOT evidence of a write.** libubootenv skips a write
  whose value already matches and does not touch the media.
- **A discriminator survives exactly one write cycle** — any write copies the
  full active set to the other copy.
- **U-Boot does not self-heal** a corrupted environment copy (board #2).
- **U-Boot uses its own built-in device tree** (`devicetree: board`), and Linux
  takes its FDT from inside `image.ub`. **`system.dtb` on the SD card may be used
  by neither.** Do not propose patching it without checking.

### Board #1 tool inventory — matters for transfers

No `base64`, `python3`, `openssl`, `xxd`, `perl`, `uudecode`. Busybox `dd` has
**no `conv=notrunc`** and no `seek` on piped input. Busybox `head` has no `-c`.
**`printf '\xNN'` works** — that is the transfer mechanism. Use hex-escaped
printf chunks with cumulative byte-count gates and a final md5 gate. Split and
re-`cat` for in-place byte patches.

## WORKING AGREEMENTS

- **4 hours minimum at Morgan, daily. Gap-attack focus.**
- **Microsteps.** One verified change per commit. File edits via a Python patch
  script written to `/tmp`, md5-gated on input, anchor counts asserted, md5
  verified independently after, `st_mode` captured and restored.
- **Check `wc -c` on every heredoc before using it.** Four truncated on
  2026-09-11 alone. A truncated commit message or patch script is silent.
- **Unique log filename per capture attempt.** Three console captures were lost
  on 2026-09-11 to filename reuse — `script` truncates on open, and the failure
  is invisible until you look.
- **`script` block-buffers.** An apparently empty log is not a negative result;
  exit picocom to flush before reading it.
- **Verify committed content out of the git object store**, not the working
  tree: `git show HEAD:path | md5sum`.
- **Measure, don't infer.** Register readback beats design intent.
- **A zero-result probe is meaningless without a positive control.**
- **Cite no line number, hash, or byte count you have not just produced.**
- **Flag SOW drift at session outset.**
- **Write the session recap before the session ends and commit it in the same
  session.**
- **State the session budget early** and scope to it.
- **Critical examination, not validation.** Challenge claims, including Jerry's.

### Claude failure modes observed 2026-09-11 — watch for these

- **Confounded experiment design.** A payload sweep varied transfer length and
  address range together; the result was read as a length ceiling. It was an
  address effect. Same confound class as the 14.24× artifact. **Before running a
  sweep, state what is held constant.**
- **Mislabelled output.** A scan `printf` added `0x100000` that `dd` never
  applied, so every address printed by two scan loops was wrong by 1 MiB.
- **Fabricated a hash.** The md5 of 64 KiB of `0xFF` was asserted from memory and
  was wrong. Caught only because the real value happened to be checked.
- **Proposed fixes without checking the mechanism.** Suggested patching
  `system.dtb` when neither U-Boot nor Linux reads it; suggested `sf probe` when
  the same broken DT node blocks U-Boot too.
- **Over-investigated a simple request.** Jerry asked to pull and test; the
  session turned into a repo-wide audit. When the ask is narrow, answer narrowly.
- **Asserted an uncommitted file that was already committed.** Check before
  telling someone work is outstanding.
- **Placeholder characters in commands.** `date -u -s "... HH:MM:00"` was sent
  literally and rejected. Never send a command containing a placeholder meant to
  be edited.

## SHARED-RESOURCE ETIQUETTE — LPS

Board #1 and `stile` are shared with `sqclash` (Shelly). On 2026-09-11 a stale
`screen` session of hers held `/dev/ttyUSB0` (opened Sep 2, board powered off)
and was killed with `sudo` to proceed. **Tell her.** Check `fuser -v
/dev/ttyUSB0` before assuming a node is free, and ask before killing another
user's process.

## NEXT SESSION — start here

1. `git log`, `git status`, `rev-list --count origin..HEAD` on the clone in use.
2. State the SOW scope and the session budget.
3. Pick from Tier 1 unless there is a stated reason not to.
4. Recommended opening move: **scope the one build** — enumerate every Kconfig
   change needed across 2.d/2.f/2.g, confirm each against the actual PetaLinux
   project at Morgan, and produce a single build plan. That is repo-and-host
   work, needs no board, and unblocks four deliverable items at once.
