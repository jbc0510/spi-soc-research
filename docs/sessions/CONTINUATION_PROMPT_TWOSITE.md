Continuing MSU-2 Task 2. Building the reproducible bring-up sequence and the
SOW 2.g appliance, one verified step at a time, across two sites.

I'm Jerry (jconway), grad researcher at Morgan State CAP Center. Project MSU-2,
"Exploring System on Chip Architectures" (IAC/TAT P1-22-2393), Task 2: Performance
Characterization and Secure Integration of Embedded Operating Systems and Hardware
Interfaces. Xilinx ZCU102 (Zynq UltraScale+ MPSoC, xczu9eg). Repo
`jbc0510/spi-soc-research`, branch `feature/dma-benchmarking`. Sponsor: Booz Allen
Hamilton / LPS ACS. PI: Dr. Kevin Kornegay. Booz Allen POC: Monica Hill. Sponsor
contact: David Lattimore. I am the only person on this project.

This work is new to me. Be meticulous. Do not let me skip a verification because
the previous one passed.

================================================================================
SECTION A — THE TWO-SITE PROTOCOL. READ BEFORE PROPOSING ANYTHING.
================================================================================

New this session: every step of the bring-up sequence and the appliance build is
BUILT at one site and INDEPENDENTLY REPRODUCED at the other before it is
integrated. A step that has not been reproduced at the second site is not done.

  BUILD SITE      -> where the artifact is produced and first tested
  VERIFY SITE     -> Morgan CAP station; reproduces from the committed record ALONE
  TRANSFER PATH   -> GitHub only. This is load-bearing, not a preference.

The verify site must reproduce from what is COMMITTED, not from anything I say in
chat and not from anything in a session summary. If a step cannot be reproduced
from the repository alone, the record is incomplete and THAT is the defect — not
the verifier's environment. Fix the record, re-push, re-verify.

Per-step cycle, and no step skips a stage:

  1. DEFINE     what the step does, what it changes, and what "verified" means
                for it — stated BEFORE building, so success is not defined after
                the fact by whatever happened
  2. BUILD      at the build site, microsteps, md5-gated patches
  3. SELF-TEST  at the build site, with the readback for that step
  4. COMMIT     with a provenance block and an explicit reproduce-me procedure
  5. PUSH
  6. REPRODUCE  at Morgan CAP from a clean pull, following ONLY the committed
                procedure
  7. RECORD     the reproduction result — including any divergence — as a commit
                at the verify site or as an appended note
  8. INTEGRATE  only now does the step join the accumulated flow
  9. REGRESS    re-run the accumulated flow end to end; a new step that breaks an
                earlier one is a defect in the new step until proven otherwise

DIVERGENCE IS DATA. If the two sites disagree, that is a finding to document, not
an inconvenience to smooth over. Record what differed and why before proceeding.

THE MACHINE MAP, as established 2026-08-17:

  LPS (build site)
    stile        Ubuntu 24.04.4. Vivado/Vitis 2025.1 at `/tools/Xilinx/2025.1/`,
                 PetaLinux 2025.1, repo lives here. All builds and analysis.
    jeremiahc    LPS-issued laptop. Board access: SD card at
                 `/media/jeremiahc/BOOT/`, UART `/dev/ttyUSB0` @115200.
    ZCU102 #1    The board these sessions have measured. Hostname on the
                 currently-flashed image: `newQspi`.

  MORGAN CAP (verify site)
    opentitan    Intended verifier. CONFIGURATION STATE UNKNOWN — see Q1 below.
    ZCU102 #2    Morgan has its own board. Baseline UNKNOWN — see Q3.

Note that stile and jeremiahc are BOTH at LPS. The GitHub-only transfer
constraint between them is a network/policy constraint, not a geographic one,
and it applies to the Morgan machine as well.

BECAUSE THERE IS A BOARD AT EACH SITE, the full protocol is available: both
build artifacts AND hardware bring-up can be independently reproduced. That is
a materially stronger claim for the final technical report than same-bench
repetition, and it is the reason this protocol is worth its overhead. Say so in
the deliverable rather than leaving it implicit.

REMAINING UNKNOWNS — ask me, do not guess:

  Q1. Is `opentitan` the machine Vinton offered to reconfigure with Ubuntu (RHEL
      8.10 is not a supported PetaLinux host)? If so, Step 0 has an EXTERNAL
      DEPENDENCY on his timeline and belongs on the December risk register: an
      unavailable verify site stalls the protocol, not the work.
  Q2. Does `opentitan` currently have Vivado/Vitis 2025.1 and PetaLinux 2025.1,
      or is it bare? This decides whether Step 0.5 is expected to pass or
      expected to refuse.
  Q3. ZCU102 #2's baseline: is its SD card / BOOT.BIN / image.ub the same as #1,
      different, or unknown? UNKNOWN IS THE EXPECTED ANSWER and is fine. Do not
      let anyone assume the two boards start from the same state.
  Q4. Can `opentitan` push to GitHub, or only pull? Step 7 differs — if pull-only,
      reproduction results come back to stile by another route and that route
      must be named.
  Q5. Is `opentitan` the actual hostname or shorthand? Commands and records
      should use the real one.

ON TWO BOARDS AND WHAT "DIVERGENCE" MEANS:
Two physical boards will differ — different SD contents, possibly different
silicon revision, certainly different flashed images until deliberately aligned.
A bring-up step that behaves differently on #2 is NOT automatically a defect. The
discipline is: establish #2's baseline FIRST (Step 0.6), then any divergence is
interpreted against a known starting state instead of against an assumption. A
procedure that only works on one board is a finding worth having; a procedure
that appears to fail because nobody recorded what the second board started from
is wasted effort.

================================================================================
SECTION B — SCOPE DISCIPLINE. HOLD ME TO THIS.
================================================================================

SOW status, honestly stated:

  2.a Characterize performance gaps ........ substantially done, PROVISIONAL
  2.b Analyze PIO vs DMA ................... PIO done; DMA = two negative results
  2.c Evaluate real-time suitability ....... bare-metal done; Linux PS impossible
  2.d Comparative benchmarking framework ... hardened, NEVER RUN
  2.e CPU utilisation metrics .............. Linux written, never run; BM not written
  2.f OS tuning / determinism analysis ..... NOT STARTED
  2.g Minimal appliance + security ......... DESIGNED, not implemented

The December 9-month deliverable is 2.f and 2.g. 2.g is now designed
(`docs/design/SOW_2G_APPLIANCE_DESIGN.md`). 2.f has not been started at all.

Rules:

  1. Every session must move at least one SOW activity forward. Documentation,
     provenance, and reproducibility-harness work is NECESSARY but is NOT a SOW
     activity. If a session produces only those, say so plainly in the recap.

  2. The two-site protocol in Section A is a METHODOLOGY UPGRADE, not a
     contracted requirement. It applies to the bring-up sequence and the
     appliance build. Do NOT apply it to trivial documentation fixes — that
     turns a good practice into a tax. If I start routing everything through it,
     say so.

  3. If I drift toward anything not on the ordered list, SAY SO IMMEDIATELY and
     point at this section. Do not follow me politely.

  4. Defects found in passing get RECORDED in a running list, not fixed on
     sight, unless they block the current step.

  5. DMA is closed (`hardware/sim/F_DECISION_DMA_SCOPE.md`). Quad SPI, data
     tunneling, and board-to-board are parked. None is a contracted deliverable.

  6. Post-quantum ML-DSA-44 is a RESEARCH EXTENSION layered on a conventional
     baseline, per the design doc §2. It is stage V3, after V1 (working RSA/FIT
     verification) and V2 (characterisation). If I try to start at V3, point at
     the measured fact that `CONFIG_FIT_SIGNATURE` is not set — there is no
     verification hook to extend yet. Recon for it happens in a SEPARATE session.

I want critical examination, not validation. If my plan is wrong, say so and why.

================================================================================
SECTION C — HOW I WORK. These rules earned their keep; do not relax them.
================================================================================

- Microsteps. One verified change per commit. Nothing lands without a readback.
- File edits via python patch scripts written to `/tmp`, then run as a SEPARATE
  step. Never nano. Never `PYEOF`. Paste blocks under ~3 KB — over that they
  truncate. For anything larger, write the file out and let me download it.
- Every patch script: md5-gate the input, assert anchor counts == 1 BEFORE
  writing, print the resulting md5. Then verify with an independent `md5sum`.
- Anchors must match COMPLETE EXPRESSIONS or LINE-ORDER RELATIONS, never bare
  identifiers. Comments and `sizeof()` contain identifiers.
- ONE python patch per file per step. Write to `/tmp`, THEN run in the next step.
- Commit messages carry md5 chains, file+line citations, an explicit
  "DELIBERATELY NOT CLAIMED" section, and — new — a REPRODUCE section giving the
  exact commands the verify site runs.
- NO PLACEHOLDERS IN COMMIT BODIES. Draft the message after the values are known.
- Commit message subjects: ONE LINE. A wrapped subject folds badly in
  `git log --oneline`, which is what gets read during a demo. (Cost one amend.)
- C source: gate with `gcc -fsyntax-only -Wall -Wextra -x c`. The `-x c` is
  LOAD-BEARING — without it gcc treats a non-`.c` extension as linker input,
  compiles nothing, and exits 0. FALSE PASS. It happened.
- Shell scripts: gate with `sh -n`.
- Every source patch ends with an INDEPENDENT STRUCTURAL CHECK run outside the
  patch script. Anchor asserts verify that the specified edits applied; they
  cannot verify that the right edits were specified.
- Never write a command with a literal placeholder like `<filename>` into
  something I am meant to paste — bash rejects it as a redirection and eats the
  line. Give literal paths or ask me to read the file first. (Cost two round
  trips.)
- Never modify a tracked artifact without a backup first. A script that writes
  to a tracked path can destroy an uncommitted state with no copy anywhere.

================================================================================
SECTION D — CLAUDE'S FAILURE MODES. Do not repeat these.
================================================================================

- ASSERTED FACTS WITHOUT GREPPING. Claimed three times that the July build flags
  "were never recorded." They were in `linux/JITTER_CAPTURE_RESUME.md:32`. GREP
  FIRST, ALWAYS, INCLUDING FOR THINGS YOU EXPECT TO BE ABSENT.
- CITED A LINE NUMBER FROM A PARAPHRASE instead of from the file, and was wrong
  by two — inside a commit whose subject was citation accuracy. Caught only
  because the cited file was grepped before committing. Line numbers come from
  `grep -n`, never from a note or a summary.
- QUOTED md5 GATES FROM MEMORY and got one wrong. Pull gates from `git log`, the
  recap, or a live `md5sum`.
- WROTE GUARDS AGAINST BARE IDENTIFIERS. Five false positives across sessions.
- REASONED ABOUT THE TOOLCHAIN INSTEAD OF MEASURING IT. Four consecutive wrong
  predictions. CHECK THE CHEAP FACT FIRST — one `objdump`/`readelf`/board read
  beats any amount of inference.
- OVER-READ ABSENT EVIDENCE. Logs live in `hardware/logs/` and `dma/logs/`, not
  `hardware/sim/`.
- SOURCED TECHNICAL CLAIMS FROM SESSION SUMMARIES rather than original logs.

================================================================================
SECTION E — WHERE THINGS STAND
================================================================================

Last pushed: `f7b73ee`. Three commits last session, all pushed, tree clean:

  0d7728f  corrected the false GLIBC_2.38 rationale in spi_benchmark_v2.c
  cf7fd91  corrected build.sh's "July flags were never recorded" claim
  f7b73ee  exact-string compiler gate and verify-before-move in build.sh

Current tracked md5s (verify these first):

  linux/src/spi_benchmark_v2.c          8b4be15e270dad88db03fc95a7731ab3
  linux/src/spi_benchmark_v2_aarch64    ff194b3828edc13d06ba26ef816c8616
  linux/src/build.sh                    221d58effa7e4bdf3fecbb6f9bf88d98

NOT YET COMMITTED — two documents produced last session, transfer and verify
their md5s before committing:

  docs/design/SOW_2G_APPLIANCE_DESIGN.md   599e04044ba73ef22d1318f2a7ad3f5f
  docs/sessions/SESSION_RECAP_20260817.md  475a53a058c85c204e84ccce13b4db4d

`build.sh` now reproduces `ff194b38` byte-for-byte (BuildID
`77e00aefea51384d655b0481d467c4c53c2a6a00`), confirmed three times. This is the
first genuinely reproducible build in the project and it is the model for
everything in Section A.

================================================================================
SECTION F — MEASURED FACTS. Do not rediscover.
================================================================================

BOARD (live root shell on `newQspi` over UART, 2026-08-17):
- glibc **2.39**; `GLIBC_2.36`/`2.38`/`2.39` all defined. Toolchain sysroot
  compatible. No glibc floor assertion needed.
- `spidev.bufsiz` = **1048576** live. `results/PAYLOAD_CEILING_FINDINGS.md:70` is
  CORRECT; `docs/notes/block_design_review.md:99` (claims 65536) is WRONG.
- Kernel `6.12.10-xilinx-g0a0f70e531c7`, `#1 SMP`, **NO PREEMPT STRING** — this
  is 2.f's non-preempt baseline.
- `CONFIG_SPI_SPIDEV=y`, built in, not a module.
- **RTC IS NOT SET.** Board clock reads January 2025. Any capture or signing
  timestamp will be wrong until handled. MUST be addressed in the bring-up
  sequence, and whether it persists across power cycle is UNKNOWN — test
  `hwclock -w` then `hwclock -r` after a reboot.

THE BLOCKER:
- `BOOT.BIN` `a25d65490a95eed09632ff3af97eb42b` + `image.ub`
  `ffe0c75b60f043a48e585377fce44202` are known-good FOR BOOTING, NOT for SPI
  benchmarking. Project notes conflate these.
- It is a QSPI build. Hostname literally `newQspi`. Only SPI master is
  `spi0` = `spi@ff0f0000` (QSPI). No PS SPI0/SPI1, no AXI Quad SPI.
- `/dev/spidev*` DOES NOT EXIST.
- `/sys/class/fpga_manager/fpga0/state` = `unknown`. No bitstream, so
  `0xa0000000` is not in the address map.
- `root=/dev/ram0`. SD FAT partition NOT mounted at boot; mounts fine manually
  (`mount /dev/mmcblk0p1 /mnt/sd`).

U-BOOT 2025.01-xilinx-v2025.1, read from the live `.config` at
`~/zcu102-spidev/build/tmp/work/zynqmp_generic_xczu9eg-amd-linux/u-boot-xlnx/2025.01-xilinx-v2025.1+git/build/.config`:
- `CONFIG_FIT=y`, `CONFIG_SPL_FIT=y`, `CONFIG_FIT_FULL_CHECK=y` (structural only)
- `CONFIG_FIT_SIGNATURE` **NOT SET**. `CONFIG_RSA` **NOT SET**. There is NO
  cryptographic verification at boot today.
- `CONFIG_LEGACY_IMAGE_FORMAT=y` — unsigned legacy images also boot. Must be
  disabled as part of V1.
- `CONFIG_ENV_IS_IN_FAT=y` + `CONFIG_SYS_REDUNDAND_ENVIRONMENT=y` — atomic,
  power-loss-tolerant env write ALREADY ENABLED. This is the A/B pointer
  mechanism. Do not hand-roll one.
- `CONFIG_BOOTCOUNT_LIMIT` not set — must be enabled for revert-on-failure.
- `CONFIG_WDT`, `CONFIG_WATCHDOG`, `CONFIG_SPL_WATCHDOG`,
  `CONFIG_SYSRESET_WATCHDOG` ALL NOT SET. `CONFIG_WATCHDOG_TIMEOUT_MSECS=60000`
  is an ORPHANED DEFAULT with no driver consuming it. Watchdog is greenfield.
- mbedTLS is present in the tree (`lib/mbedtls/external/mbedtls/`); whether it
  is ENABLED was not checked.

PETALINUX (`~/zcu102-spidev/project-spec/configs/config`):
- `CONFIG_SUBSYSTEM_ROOTFS_INITRD=y`; `INITRAMFS` explicitly NOT set;
  `EXT4` NOT set. It is **INITRD, not initramfs** — earlier notes had this
  wrong. The rootfs is a separate ramdisk carried inside the FIT.
- `CONFIG_SUBSYSTEM_INITRAMFS_IMAGE_NAME="petalinux-image-minimal"` — the
  minimization baseline.
- `CONFIG_SUBSYSTEM_UBOOT_FIT_IMAGE="image.ub"`, offset `0x10000000`.

BOOT.SCR (`strings sd-images/boot.scr`, tracked):
- `fitimage_name=image.ub` is a VARIABLE. Slot selection is a variable
  assignment, not a boot-logic rewrite.
- `uEnv.txt` is imported and `uenvcmd` run BEFORE the FIT load — a supported
  pre-boot hook already exists.

HARDWARE / CLOCKS:
- PL0 is 250 MHz by FSBL override (live CRL_APB readback), NOT the 100 MHz
  design intent. AXI SCK = PL0/16 = 15.625 MHz. PS SCK = 0.9766 MHz. Ratio
  16.0x, fully accounting for the retracted 14.24x.
- ATF WALL: `bm.bif` boots the app to EL3 with no `bl31.elf` partition, so ATF
  is never loaded. Linux boots THROUGH ATF, which owns the PMU policy denying
  APU access to Node 36 / domain12. PS SPI1 is unreachable from any context with
  ATF between it and the PMU. Belongs in the paper's 2.c section.
- `xilinx_spi` acknowledges and IGNORES speed requests. Trust achieved Mbps from
  measured wire time.
- Enhanced mode passes 1 SPI byte per 32-bit AXI beat. Assert on measured SPI
  bytes, never BTT.
- SmartConnect blocks FIXED bursts unconditionally (UG1037). Use
  `axi_interconnect`.

TOOLCHAIN:
- `build.sh` pins `CC` to
  `/tools/Xilinx/2025.1/Vitis/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-gcc`
- Its `--version` first line: `aarch64-amd-linux-gcc.real (GCC) 13.3.0`
- Its `.comment` output: `GCC: (GNU) 13.3.0`
- These are TWO DIFFERENT STRINGS. Both are asserted exactly. Neither implies
  the other.
- Ubuntu's cross compiler DOES NOT EXIST on stile (`/usr/bin/aarch64-linux-gnu-gcc`
  absent, not on PATH). `spi_benchmark_aarch64` (`.comment`:
  `GCC: (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0`) CANNOT be reproduced there.
- `$READELF` resolves to a 117-byte WRAPPER SCRIPT, not a binary. It works; the
  gate depends on a shim. Relevant if the verify site's layout differs.
- `make build-linux` HAS NEVER WORKED — delegates to `linux/`, no Makefile there.

UNRESOLVED ANOMALY, carry forward:
- `aarch64-linux-gnu-gcc -E` on a bare `#include <stdlib.h>` piped to
  `grep -c isoc23` returned **0**, yet `spi_benchmark_v2_aarch64` imports
  `__isoc23_strtol@GLIBC_2.38`. The two measurements contradict. No conclusion
  was drawn and none should be until resolved. Commit `0d7728f` claims only the
  artifact fact.

================================================================================
SECTION G — ORDERED WORK. Step 0 first. Do not reorder without telling me why.
================================================================================

STEP 0 — ESTABLISH AND RECORD BOTH SITE BASELINES.
  Nothing can be "reproduced at Morgan" until Morgan's state is recorded. This
  step produces a committed environment record, not a claim. It is the longest
  Step 0 this project has had and it is not optional — every later reproduction
  result is interpreted against it.
    0.1  Answer Q1-Q5 in Section A. Written down and committed, including "not
         yet known" where that is the truth.
    0.2  On `opentitan`: OS and version, Vivado/Vitis presence and version,
         PetaLinux presence and version, python3 version, `dtc` presence, git
         version, `readelf` presence and whether it is a real binary or a
         wrapper (stile's is a 117-byte shim), and push access.
    0.3  Clean clone at the verify site. Confirm `git log -1` matches stile and
         `git status --porcelain` is empty.
    0.4  Verify the three tracked md5s in Section E from that clean clone.
    0.5  FIRST CROSS-SITE ARTIFACT TEST: run `linux/src/build.sh` on
         `opentitan`. Does it produce `ff194b38` with BuildID `77e00aef…`?
         - If YES: cross-site artifact reproducibility is established. This is
           the foundation for the U-Boot rebuild and signed-image work, none of
           which needs a board.
         - If IT REFUSES TO BUILD: check whether that is CORRECT before treating
           it as a failure. If `opentitan` lacks the Xilinx toolchain, the gate
           SHOULD refuse — that is the gate working as designed, not a
           reproducibility defect. Record the refusal message verbatim.
         - If IT BUILDS BUT DIFFERS: this is the most valuable finding available.
           Record `.comment`, `--version` first line, BuildID, and `.text` /
           `.rodata` sizes from both sites before drawing any conclusion.
    0.6  ZCU102 #2 BASELINE. Record, do not assume — the expectation is that it
         DIFFERS from `newQspi`:
           BOOT.BIN md5, image.ub md5, SD partition layout, hostname,
           `/proc/cmdline`, kernel version string and whether PREEMPT appears,
           glibc version, `/dev/spidev*` presence and what they bind to,
           `/sys/class/fpga_manager/fpga0/state`,
           `/sys/module/spidev/parameters/bufsiz`, RTC state, and which SPI
           masters exist under `/sys/bus/spi/devices/` or in the device tree.
         Compare against Section F's `newQspi` facts and record every difference.
    0.7  DECIDE, and flag it as a decision: do the two boards get ALIGNED to a
         common flashed image before bring-up work starts, or does the procedure
         have to work from both starting states? Aligning is simpler and makes
         divergence meaningful; not aligning is a stronger test but risks
         chasing differences that are not defects. My call — ask me.
    0.8  Commit the environment record for both sites and both boards, as one
         document with a per-site section.

STEP 1 — PRE-READS FOR THE BRING-UP PROCEDURE. Pure reads, build site, no board.
    1.1  `dtc -I dtb -O dts sd-images/spi_pl_dma.dtbo` — READ IT BEFORE ANY PLAN
         MENTIONS APPLYING IT. It is named for DMA and DMA is closed. It may be
         the wrong overlay entirely. This decides what Step 2 says.
    1.2  Extract the `.hwh` from `hardware/xsa/spi_benchmark_wrapper.xsa` and
         recover `C_SCK_RATIO`, `C_FIFO_DEPTH`, `C_SPI_MODE`, `C_NUM_SS_BITS`,
         and the AXI base address. Five bitstreams beside it encode a frequency
         in the filename; `wrapper` — the one on the card — does not. Without
         this, the bring-up procedure's "verify SCK" step has no expected value.
    1.3  Establish which `.xsa` built the on-card `spi_benchmark_wrapper.bit.bin`
         (`a472d8b` says it was rebuilt for correct J55 routing). If that chain
         cannot be closed, say so — a capture inherits the ambiguity that forced
         the `e89bb63` rename.
    1.4  Commit the findings. These are facts, not a procedure.

STEP 2 — WRITE THE BRING-UP PROCEDURE. Written and committed BEFORE any hardware
execution. Each stage needs a readback and a stated expected value.
    2.1  Mount `/dev/mmcblk0p1`; verify contents against committed md5s
    2.2  RTC: set it, write it, power-cycle, read it back. Record whether it
         persists. If it does not, setting it is a numbered per-boot step
         forever and the time source must be named.
    2.3  Load the bitstream via fpga_manager; verify `fpga0/state` changes from
         `unknown`
    2.4  Apply the overlay decided in 1.1; verify by reading back, not by
         assuming the apply succeeded
    2.5  Verify `/dev/spidev*` appears AND that the node maps to `0xa0000000` —
         read `/sys/class/spi_master/*/of_node` or equivalent, do not assume
    2.6  Verify SCK from CRL_APB against the value recovered in 1.2, not from
         the request
    2.7  Define the FAILURE behaviour of each stage, not just success
    DO NOT execute this on hardware in the same session it is written unless
    the write is finished and committed first.

STEP 3 — REPRODUCE STEP 2 AT THE VERIFY SITE, from the committed procedure only.

STEP 4 — THEN capture. Not before Step 3 passes.

PARALLEL, NOT BLOCKED BY THE BOARD — appliance work per the design doc §6.
Items 1-7 there need no working SPI. Same two-site cycle. Before starting item 1,
close the cheap unknowns from design doc §7: is `fw_setenv` on the rootfs, is
FAT redundant env initialised on the card, is mbedTLS enabled, does a ZynqMP
watchdog driver exist in U-Boot 2025.01.

================================================================================
SECTION H — BACKLOG. Record, do not fix on sight.
================================================================================

- `docs/notes/block_design_review.md:99` says bufsiz 65536; measured 1048576.
- `README.md:95,155` and `linux/JITTER_CAPTURE_RESUME.md:54,60,82,83` reference
  `emio_internal_results.csv`, renamed out of existence by `0dc3d8f`.
- `README.md:87,153,154` name `spi_benchmark_jitter_aarch64` as the live tool;
  the live tool is `spi_benchmark_v2_aarch64`.
- `linux/src/README.md` mapping binaries to CSVs, including the Ubuntu-vs-Xilinx
  compiler split. md5s:
    02555284c651afa4e7ee8ecaddee9f96  spi_benchmark_jitter_aarch64  (Xilinx)
    32ed4093b44f4f23f851cd30a3b76ec1  spi_benchmark_aarch64         (Ubuntu)
- `build.sh` override (`ALLOW_COMPILER_MISMATCH=1`) replaces a good `$OUT` with
  no backup. Add a `.prev` copy before `mv` under override.
- CSV schema and semantic labels live in three places that must agree by hand.
  Consolidate to string constants — AFTER a defect series, never mid-series.
- `emio_results.csv` / `mio_results.csv` are 3-column with a FLAT 1.0 placeholder
  stddev. The reduction from 5+ columns to 3 was done BY HAND and the reducing
  step is not in the repo.
- `results/unidentified_internal_results_20260708_1319.csv` was captured at ~16x
  the PS clock. NOT the PS controller. NOT PROVEN to be AXI either. See
  `results/LINUX_JITTER_PROVENANCE.md` §8.
- `emio_internal_results.csv` / `mio_internal_results.csv` on the SD card dated
  Jan 8 2025, both 414 B. Possible third provenance thread. Low priority.
- Bare-metal `cpu_pct` (SOW 2.e): 100.0 BY CONSTRUCTION — `XSpiPs_PolledTransfer`
  spins, no scheduler, no WFI. Either emit 100.0 labelled structurally-derived
  while still measuring `cpu_us` via `PMCCNTR_EL0` so agreement is a CHECK, or
  emit -1 and report cycles-per-byte. `nvcsw`/`nivcsw` emit -1, never 0.
  `PMCCNTR_EL0` at EL3 needs `PMCR_EL0.E` and `PMCNTENSET_EL0.C` set, and
  divides by 64 if `PMCR_EL0.D` is set — read that back before trusting a count.
- August MSR: proactive disclosure of the Task 1 gap as a risk item. The former
  group member who owned Task 1 has left; responsibility is not mine, but MSR
  accuracy is self-interest for my defense.
- Vinton offered to reconfigure a standalone machine with Ubuntu (RHEL 8.10 is
  not a supported PetaLinux host). Possibly relevant to Q1.

================================================================================
START BY
================================================================================

Answering Q1-Q5 is on me — ask me for them. Then confirm tree state against the
Section E md5s and tell me whether the Section G ordering is wrong and why. Do
not begin Step 0.2 until you have said so.
