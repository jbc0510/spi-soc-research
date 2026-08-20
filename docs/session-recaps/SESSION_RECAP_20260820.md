# MSU-2 Task 2 — Session Recap & Continuation, 2026-08-20 (Morgan)

**COMMIT THIS FILE IN THE SAME SESSION IT IS WRITTEN.** The SOW 2.g design
document was lost at exactly this point in a previous session — written at the
end, never committed, gone.

Host `bxqp8b3-ub22`, clone `~/msu2-verify/spi-soc-research`.
Session start HEAD `37f2816`. Session end HEAD `e2f8017`, pushed.
Next session: **LPS (stile / jeremiahc), Monday 2026-08-24.**

---

## 1. WHAT ADVANCED — the SOW position

**One SOW-contracted activity: 2.g design inputs, from live hardware.**

| commit | what | SOW |
|---|---|---|
| `cfb2ffd` | Step 0.5 cross-site artifact reproducibility result | protocol |
| `358ef7f` | recap 5.1 marker recording that result | record |
| `8516abe` | ZCU102 #2 bring-up from the committed record | **2.g** |
| `7352630` | raw console capture behind the bring-up | evidence |
| `53d1a8d` | rescued Vitis platform fix from a forgotten clone | repo integrity |
| `e2f8017` | cold-boot capture with live CRL_APB register reads | measurement |

2.f: still NOT STARTED. 2.g: still DESIGN LOST and NOT IMPLEMENTED — findings
and design inputs are not a design. No benchmark was run today.

---

## 2. STEP 0.5 — CLOSED

**Outcome: builds but differs, fully characterised.** The third of the three
outcomes named in advance, not reclassified after the fact.

Stripped of DWARF debug info and the BuildID note, the stile and Morgan
binaries are byte-identical at `cd32416b2baf7eb38939214d85a142a6` (71720
bytes). `.text` and `.rodata` match exactly. Divergence is confined to
`.debug_line_str` (the build-path string table) and the two sections holding
offsets into it.

The glibc sysroot strings are IDENTICAL at both sites, so changing
`XILINX_ROOT` did NOT resolve a different sysroot — the specific unknown the
wrapper's relative resolution created.

Full evidence: `docs/environment/STEP_0_5_CROSSSITE_20260820.md`
(md5 `ab75ca9ec1a1fb0ba1c9911cb2f01e01`).

**D-5 remains open:** `-ffile-prefix-map` would make builds byte-identical
across sites, at the cost of regenerating `ff194b38…` and every recorded
reference to it. Deferred by decision over the weekend.

---

## 3. ZCU102 #2 BROUGHT UP FROM THE COMMITTED RECORD

Blank 64 GB SD card, repartitioned FAT32, eight files copied per
`sd-images/RE-FLASH.md` and md5-verified ON THE CARD, then
`README.md:130-146` for the PL bitstream and device-tree overlay. Result: a
running Linux with a working `/dev/spidev1.0`.

**The reproduce path works. No single document covers it** — bring-up
currently requires `RE-FLASH.md`, then `README.md`, and knowing that order.

Five documentation defects found by following the documents, recorded in
`docs/environment/BRINGUP_ZCU102_2_20260820.md` section 10. The worst: a card
built from `RE-FLASH.md` alone boots and has NO SPI device.

### Measured on hardware, first time

- **`spidev1.0` is `a0000000.axi_quad_spi`**, not PS SPI1. Previously
  established by analysis; now read from sysfs. Direct evidence against the
  same-wire-same-clock framing in `MSU2_Session_Recap_Onboarding.docx`.
- **`if00` IS the console.** The AMD-convention caveat in
  `SESSION_RECAP_20260819.md` 5.2 can be struck.
- **Hostname `newQspi` comes from `image.ub`, not from board #1.** Hostname
  CANNOT distinguish the two ZCU102s. Bears on D-4.
- Base DTB enables ONLY QSPI; both PS SPI nodes are `disabled` with no child
  nodes. "spidev-enabled kernel" means the DRIVER is built in — the DEVICE
  comes entirely from the overlay.
- The overlay carries `/fpga-region/firmware-name` and programs the PL by
  itself; README's separate `fpga_manager/firmware` write is redundant.

### 2.g design inputs — the A/B mechanism has NEITHER half

- **Q4-prime: U-Boot did NOT create `uboot.env` on a fresh FAT32 partition.**
  After a full boot, the partition holds exactly the eight files copied.
  **CAVEAT: U-Boot conventionally writes only on explicit `saveenv`.** This may
  be expected behaviour, not a defect. NOT MEASURED.
- **Q1 confirmed on running silicon:** no `fw_setenv`, no `fw_printenv`, no
  `/etc/fw_env.config`.

So U-Boot is built for a redundant FAT environment, nothing initialises the
files, and no userspace tool exists to flip the pointer.

---

## 4. THE CLOCK CHAIN, DERIVED FROM LIVE REGISTERS

Cold boot (power-cycled, not a reattach), three `devmem` reads. First time the
IOPLL figure comes from a register rather than the record.

```
IOPLL_CTRL     0xFF5E0020  0x00015A00   FBDIV [14:8] = 0x5A = 90
PL0_REF_CTRL   0xFF5E00C0  0x00010600   DIVISOR0 [13:8] = 6, SRCSEL = IOPLL
SPI1_REF_CTRL  0xFF5E0080  0x01001800   DIVISOR0 [13:8] = 0x18 = 24

IOPLL = 33.333 x 90 / 2 = 1500 MHz
PL0   = 1500 / 6  = 250 MHz   -> AXI SCK = 250 / 16   = 15.625 MHz
SPI1  = 1500 / 24 = 62.5 MHz  -> PS SCK  = 62.5 / 64  = 0.9766 MHz
ratio = 15.625 / 0.9766 = 16.0x
```

The observed 14.24x throughput advantage sits under a 16.0x clock ratio. The
AXI controller was not faster; it was clocked faster.

Capture: `docs/environment/zcu102-2_clocks_20260820.log`
(md5 `aed22e304015e11170d7478dfdbf25c6`).

**Two open questions, stated as questions:**

1. `PL0_REF_CTRL` reads `0x00010600`; the record carries `0x01010600`. One bit
   apart, bit 24, believed to be CLKACT but NOT verified against UG1085.
   DIVISOR0 = 6 either way, so 250 MHz is unaffected.
2. `SPI1_REF_CTRL` reads DIVISOR0 = 24 under Linux with no bare-metal code
   run. The record attributes that value to a bare-metal override correcting
   an FSBL DIVISOR0 = 6. Either this `BOOT.BIN` sets 24, or the attribution is
   wrong.

---

## 5. SECOND CLONE — RESCUED AND CLEANED

A second clone exists at `~/spi-soc-research` on the Morgan machine, 58 commits
behind. `e0b5e78` is an ancestor of HEAD, so nothing diverged — but it held an
uncommitted, single-copy edit to `dma/baremetal/create_zdma_platform.py`.

Rescued and committed in `53d1a8d`, with the deleted rationale restored and an
UNTESTED label (written 2026-07-15 against a broken Vitis install, never run).

Deleted from that clone as worthless: a repo-hygiene report and its prompt
(both describing edits that never landed, resting on a since-overturned 6.25
MHz SCK conclusion), a Vitis interactive-session journal, a duplicate
block-design PDF, and `export_bd.tcl`.

**`export_bd.tcl` was superseded by something already tracked:**
`scripts/export_bd_diagrams.tcl` builds the BD from the tracked Tcl into a
throwaway project, is already portable (`$::env(HOME)`, `$REPO`), and exports
both the original and CDMA variants to `hardware/docs/`. It is untested in
2025.1 — the record notes BD 5-349 batch-mode failures, and this script uses
`create_project` in batch.

**The clone is being KEPT deliberately**, to show the summer's working state.
Note that its history is identical to origin's; only the working copy is old.
**`~/msu2-verify/spi-soc-research` is the authoritative clone at Morgan.**

---

## 6. CLAUDE FAILURE MODES — five checks that could not have failed

The dominant pattern of the day. Each probe's failure mode was
indistinguishable from a true negative, so an empty result looked like an
answer.

1. `objcopy -O binary --only-section=.debug_*` — `-O binary` emits only
   SHF_ALLOC sections, so all sixteen debug extractions produced ZERO-byte
   files and every pair hashed equal. Eight false "identical" results.
   Corrected with `--dump-section`.
2. `find /proc/device-tree -name '*quad_spi*'` — `/proc/device-tree` is a
   SYMLINK; `find` does not traverse symlinks without `-L`. Could not have
   matched. `find -L` returns the node.
3. `git merge-base --is-ancestor` run in the clone that lacked one of the
   commits — returned **128** (error), which was nearly read as a verdict.
   Valid only in a clone holding both revisions.
4. A gate asserting the SD card would show `RM=1` (removable). It shows `0` —
   SD cards on an MMC controller often do. The gate was written from
   expectation, not knowledge.
5. "git will treat it as binary" for the console log — it did not; git
   reported 885 insertions. A prediction stated as fact in a commit message.

**Rules now in the committed record:**
- A zero-result probe is meaningless without a positive control or a line/entry
  count on the same input.
- When a probe under `/proc` or `/sys` returns empty, check whether the path is
  a symlink before concluding absence.
- Exit code 128 from a git plumbing command is an error, not an answer.

Yesterday's pattern (citations written from inference rather than read off the
file) did not recur today.

---

## 7. STATE OF THE RECORD

- `docs/environment/` now holds: the LPS host baseline, the Step 0.5 result,
  the ZCU102 #2 bring-up document, and two raw console captures.
- ZCU102 #2 was left **power-cycled after the clock reads** — PL not
  programmed, overlay not applied, `/dev/spidev1.0` absent. Rootfs is INITRD,
  so the forced password change recurs every boot and nothing persists.
- The block-design diagram is committed and confirmed good for onboarding:
  `hardware/docs/bd_spi_benchmark_original.pdf` / `.svg`. It shows all four
  instances, both SPI paths, and the `_o_en` tristate ports.

---

## 8. NEXT SESSION — LPS, MONDAY 2026-08-24

Ordered. The first two are the December deliverable; the rest is hygiene.

### 8.1 `saveenv` — one command, decides the 2.g remediation

On ZCU102 #1 (board via `jeremiahc`), interrupt U-Boot at the prompt and run
`saveenv`. Then check whether `uboot.env` and `uboot.env.bak` appear on the FAT
partition.

- **They appear** → the A/B mechanism works and needs only provisioning-time
  initialisation. Cheap.
- **They do not** → `CONFIG_ENV_IS_IN_FAT` is not functioning as the record
  assumes, and 2.g robustness needs a different design.

Either way, `fw_setenv` is still absent from the rootfs (Q1, measured twice) —
so a userspace path to flip the pointer must be added or designed around.

### 8.2 Q4 (original) — the board's own card is at LPS

ZCU102 #1's SD card is the one that might already carry a redundant
environment. Mount its FAT partition READ-ONLY and look for `uboot.env` /
`uboot.env.bak`. This is the question Morgan could not answer (the card in the
reader there was blank exFAT, and #2's slot was empty).

Note ZCU102 #1 is recorded as a QSPI build with no `/dev/spidev*`.

### 8.3 2.g watchdog remediation — LPS-only, gated by D-1

`SOW_2G_SEC7_UNKNOWNS.md` Q3: the ZynqMP watchdog driver and both DT nodes are
ready; only `CONFIG_WDT` and `CONFIG_WDT_CDNS` are unset. A U-Boot rebuild is
an LPS job (PetaLinux 2025.1 lives on stile).

**D-1 must be decided first** — PetaLinux 2025.1 (stile) vs 2025.2 (Morgan)
gates any 2.g U-Boot rebuild. Check UG1144 for whether Ubuntu 22.04 is a
supported host for 2025.1 BEFORE downloading; needs `df -h` at Morgan to price
it.

### 8.4 D-5 — decide

`-ffile-prefix-map`. Weekend thinking. If yes, it is an LPS job: regenerate
`spi_benchmark_v2_aarch64`, update every recorded reference to `ff194b38…`,
and re-run the Morgan verification afterwards.

### 8.5 Documentation consolidation

Five defects in section 10 of `BRINGUP_ZCU102_2_20260820.md`. The goal is ONE
document from blank card to working SPI device. Pure doc work; possible at
either site.

### 8.6 If time remains

- Recapture the LPS host baseline from a clean tree
  (`recon_host_LPS_stile_20260817.txt` self-flags `dirty_paths: 2`).
- Fix the five `recon_host.sh` defects. Do not commit Morgan recon output
  until they are fixed.

---

## 9. OPEN — carried forward

- **6.25 vs 15.625 MHz sweep.** Six files assert SCK = 6.25 MHz from PL0 =
  99.99 MHz (BD Tcl `ACT_FREQMHZ`, design intent). Live CRL_APB gives PL0 =
  250 MHz -> SCK = 15.625 MHz. Files: `results/CLOCK_DISCREPANCY_FINDINGS.md`,
  `results/ILA_SCK_MEASUREMENT_PLAN.md`, `results/spi_benchmark_clean.c`,
  `results/PAYLOAD_CEILING_FINDINGS.md`, `results/Clash_clock_answers.md`,
  `docs/notes/block_design_review.md`. **Each occurrence must be classified as
  historical-and-correct or current-and-wrong — do not bulk-edit.** A
  2026-07-15 hygiene pass would have stamped RESOLVED/6.25 onto two of them;
  those edits never landed.
- **Q4 (original)** — 8.2 above.
- **`saveenv` untested** — 8.1 above.
- **D-1 PetaLinux**, **D-2 mkimage**, **D-4 board alignment**, **D-5
  file-prefix-map**.
- **Image md5 mismatch.** `~/zcu102-spidev` on stile does not produce the
  known-good `BOOT.BIN` / `image.ub`. Establish which tree did.
- **Double SPI alias.** The built U-Boot DTB aliases BOTH `spi1` and `spi2` to
  `/axi/spi@ff050000`.
- **TPM2-over-SPI enabled in U-Boot.** Relevant to 2.g verification. NOT
  claimed: that a TPM is present, wired, or bound.
- **Device tree identity unresolved.** `CONFIG_DEFAULT_DEVICE_TREE` names
  zcu100-revC (Ultra96); the built blob is generic `xlnx,zynqmp`.
- **Two CRL_APB questions** — section 4 above.
- **`scripts/export_bd_diagrams.tcl` untested in 2025.1.**

## 10. NOT RECONCILED — flagged, not actioned

`MSU2_Session_Recap_Onboarding.docx` presents a bare-metal vs Linux table
(3.73x at 1 B settling to 1.21x, "~28 us fixed OS overhead") as measured on the
same wire at the same clock. **Today's sysfs measurement is direct evidence
against that framing:** `spidev1.0` is the AXI Quad SPI, and PS SPI1 is
`disabled` in the base DTB and unreachable from Linux. The comparison is
Linux-on-AXI vs bare-metal-on-PS-SPI1.

Separately, `emio_results.csv` / `mio_results.csv` are 3-column with a flat
1.0 us placeholder stddev, and the reduction from 5+ columns was done BY HAND
with the reducing step absent from the repo.

**Do not put that table in front of a demo audience until both are reconciled.**

## 11. PRESENTATION MATERIAL — what is ready

Three assets, all committed and all defensible:

1. `hardware/docs/bd_spi_benchmark_original.pdf` — the block design. Four
   instances, both SPI paths, the tristate enables.
2. The clock chain of section 4, derived end to end from live registers.
3. `docs/environment/zcu102-2_clocks_20260820.log` — the three `devmem` reads
   on a cold boot. Evidence, not assertion.

The line that ties them: the AXI controller looked 14.24x faster; the clock
ratio was 16.0x. It was not faster, it was clocked faster — and only a live
register read revealed it.

**What is NOT demo-ready:** no benchmark has been run on ZCU102 #2, its
configured state does not survive a power cycle, and the headline OS-tax table
is unreconciled (section 10).
