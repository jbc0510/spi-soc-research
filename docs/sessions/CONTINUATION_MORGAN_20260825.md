# CONTINUATION PROMPT — Morgan, 2026-08-25 (afternoon)

Paste this whole file as the first message of a new conversation.

---

## WHO AND WHAT

Jerry Conway, graduate researcher, Morgan State CAP Center. MSU-2, "Exploring
System on Chip Architectures", IAC/TAT P1-22-2393, **Task 2**: performance
characterization and secure integration of embedded OSes and hardware
interfaces. Sole researcher. PI Dr. Kevin Kornegay. Sponsor Booz Allen / LPS.

Core question: **OS vs bare-metal SPI performance on a Xilinx ZCU102**, AXI
Quad SPI (PL fabric, `0xA000_0000`) vs PS SPI1 (`0xFF05_0000`).

Repo `jbc0510/spi-soc-research`, branch `feature/dma-benchmarking`.
**HEAD at LPS close of session: `8aaa065`, pushed.**

Two sites, daily cadence from 2026-08-26: **two days LPS, three days Morgan.**

- **LPS**: build host `stile` (Ubuntu 24.04.4, Vivado/Vitis 2025.1, PetaLinux
  2025.1). **ZCU102 #1 console is on stile at `/dev/ttyUSB0`** (CP2108 serial
  `C68E7C4D227B4FA211ED7C38CE7DE91`, `if00`). Board #1 is **shared with a
  colleague (`sqclash`)** who uses her own SD card in it.
- **Morgan**: `bxqp8b3-ub22` (Ubuntu 22.04.5, Vivado 2025.1, PetaLinux 2025.2).
  ZCU102 #2. Authoritative clone `~/msu2-verify/spi-soc-research`. A second,
  stale clone at `~/spi-soc-research` is **kept deliberately** to show the
  summer's working state — do not work in it.

## FIRST ACTIONS AT MORGAN TODAY

```
cd ~/msu2-verify/spi-soc-research
git status --porcelain
git pull
git log --oneline -4
df -h
```

Expect a fast-forward to `8aaa065` and a clean tree.

**`df -h` is the D-1 gate.** PetaLinux 2025.1 needs **100 GB free** per UG1144.
If it clears, installing 2025.1 alongside the existing 2025.2 is the decided
action (`docs/design/D1_PETALINUX_VERSION_20260825.md`).

Second task: **add the Vivado block diagram to the deck.** The committed
schematic is `hardware/docs/bd_spi_benchmark_original.pdf` — landscape and
dense, so give it a full slide of its own. The deck itself is not in the repo;
it is a local `.pptx` (`MSU2_progress_20260826.pptx`, 11 slides). Meeting is
2026-08-26 with Lucia and possibly Dr. Kornegay, 30-60 minutes.

## SOW STATUS

| task | state |
|---|---|
| 2.a performance characterization | substantially done; **headline must be restated on AXI controller identity** |
| 2.b DMA | PIO done; ZDMA closed as a documented negative result (no flow control between ZDMA and SPI FIFO) |
| 2.c OS vs bare-metal | bare-metal done; **Linux side structurally impossible** — ATF/BL31 blocks APU access to PS SPI1, six attempts all `-EACCES` |
| 2.d fault handling | hardened, never run. Watchdog driver and DT nodes are READY; only `CONFIG_WDT` / `CONFIG_WDT_CDNS` unset |
| 2.e test harness | Linux harness written, never run; bare-metal not written |
| 2.f OS tuning / determinism | **NOT STARTED** — half the December deliverable |
| 2.g secure appliance | **DESIGN LOST**; 3 of 4 Section 7 unknowns closed; Q4/Q4-prime answered on hardware |

**2.f is the schedule risk.** Say so plainly whenever status is discussed.

## WHAT WAS ESTABLISHED THIS WEEK — do not re-litigate

- **`spidev1.0` is the AXI Quad SPI**, not PS SPI1. Measured from sysfs:
  `/sys/devices/platform/axi/a0000000.axi_quad_spi/spi_master/spi1/spi1.0`.
- **PS SPI1 is `disabled` in the base DTB** with no child nodes. Linux cannot
  reach it. Architectural, not configuration.
- **Clock chain, from live CRL_APB registers:** IOPLL 1500 MHz (FBDIV 90) ->
  PL0 250 MHz (div 6) -> AXI SCK 15.625 MHz (÷16, synthesis-frozen);
  SPI1 ref 62.5 MHz (div 24) -> PS SCK 0.9766 MHz (÷64). **Ratio 16.0x.**
- **The observed 14.24x throughput advantage sits under a 16.0x clock ratio.**
  It was not faster; it was clocked faster. This is the strongest result in the
  record and it is a methodology finding.
- **SOW 2.g A/B environment: the U-Boot half WORKS.** `saveenv` creates
  **`uboot-redund.env`** (ONE file, 262144 bytes) — NOT `uboot.env` plus
  `uboot.env.bak`, which the record wrongly assumed. Two subsequent boots
  showed `recovered successfully`. The **Linux half is ABSENT**: no
  `fw_setenv`, no `fw_printenv`, no `/etc/fw_env.config`, measured on both
  boards.
- **RTC is per-board.** #1 reads correctly; **#2 reads January 2025** and will
  corrupt `capture_utc` until set.
- **Hostname `newQspi` comes from `image.ub`** and appears on BOTH boards. It
  cannot identify a board.
- **`image.ub` "spidev-enabled" means the DRIVER is built in.** The spidev
  DEVICE comes only from the PL overlay. A card built from `RE-FLASH.md` alone
  boots with no SPI device.
- **The overlay programs the PL itself** (`/fpga-region/firmware-name`);
  README's separate `fpga_manager` write is redundant.
- **PL state does not survive a power cycle.** Bitstream + overlay must be
  reapplied every boot. Rootfs is INITRD.
- **stile (Ubuntu 24.04.4) is NOT a supported host for PetaLinux 2025.1.**
  Morgan (22.04.5) is. This inverts the earlier assumption about which site is
  the reference.

## OPEN — carried forward

- **D-1 install** — gated on `df -h` at Morgan today.
- **2.g remediation** (bounded, not a design question): run `saveenv` at
  provisioning; add `libubootenv-bin` to the rootfs; write `fw_env.config`
  naming **`uboot-redund.env`**.
- **2.d watchdog**: set `CONFIG_WDT=y` + `CONFIG_WDT_CDNS=y`, rebuild U-Boot.
  LPS or Morgan once 2025.1 is installed.
- **6.25 vs 15.625 MHz sweep.** Six files assert SCK = 6.25 MHz from design
  intent: `results/CLOCK_DISCREPANCY_FINDINGS.md`,
  `results/ILA_SCK_MEASUREMENT_PLAN.md`, `results/spi_benchmark_clean.c`,
  `results/PAYLOAD_CEILING_FINDINGS.md`, `results/Clash_clock_answers.md`,
  `docs/notes/block_design_review.md`. **Classify each as
  historical-and-correct or current-and-wrong. Do not bulk-edit.**
- **D-2 mkimage**, **D-4 board alignment**, **D-5 `-ffile-prefix-map`**.
- Five documentation defects (`BRINGUP_ZCU102_2_20260820.md` section 10) — goal
  is ONE document from blank card to working SPI device.
- Five `recon_host.sh` defects; LPS baseline self-flags `dirty_paths: 2`.
- Spontaneous reboot on ZCU102 #1 at t≈2.28 s into Linux boot, unexplained.
- Two CRL_APB questions (`PL0_REF_CTRL` bit 24; `SPI1_REF_CTRL` divisor
  attribution).
- `scripts/export_bd_diagrams.tcl` untested in 2025.1.

## NOT RECONCILED — do not present

`MSU2_Session_Recap_Onboarding.docx` shows a bare-metal vs Linux table
(3.73x at 1 B settling to 1.21x, "~28 us fixed OS overhead") as same-wire,
same-clock. It is not: `spidev1.0` is AXI, PS SPI1 is unreachable. Separately,
`emio_results.csv` / `mio_results.csv` carry a flat 1.0 us placeholder stddev
and were hand-reduced with the reducing step absent from the repo.

**Do not put that table in front of an audience until both are reconciled.**

## HOW TO WORK WITH ME

- **Microsteps.** One verified change per commit. Every file edit via a Python
  patch script written to `/tmp` and run as its own step, md5-gated on input
  with anchor counts asserted, md5 verified independently after.
- **Base64 chunked transfer**, ~1900 chars per chunk, byte-count gate after
  every few chunks and an md5 gate at the end. No heredocs over ~3 KB, never
  nano.
- **Nothing is committed that was not observed this session.** Commit messages
  carry md5 chains and an explicit DELIBERATELY NOT CLAIMED section.
- **Measure, don't infer.** Never assert a fact without reading it off the file
  or device. Register readback beats design intent, every time.
- **Flag SOW drift at session outset.** If a session is methodology rather than
  contracted activity, say so plainly.
- **I want critical examination, not validation.** Call out errors and
  challenge claims.
- **A zero-result probe is meaningless without a positive control** or a
  line/entry count on the same input. Five checks that could not have failed
  were caught on 2026-08-20 alone; the recurring shape is a probe whose failure
  mode is indistinguishable from a true negative.
- **Cite no line number you have not just grepped.**
- **Write the session recap before the session ends and commit it in the same
  session.** The 2.g design document was lost at exactly that point.
