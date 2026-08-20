# MSU-2 Task 2 — Session Recap & Continuation, 2026-08-19 (stile / LPS)

**COMMIT THIS FILE IN THE SAME SESSION IT IS WRITTEN.** The SOW 2.g design
document was lost at exactly this point in a previous session — written at the
end, never committed, gone. If this file is still uncommitted when the session
ends, it does not exist.

Repo `jbc0510/spi-soc-research`, branch `feature/dma-benchmarking`.
Session start HEAD `fdd43fa`. Session end HEAD `157f367`, pushed.

---

## 1. WHAT ADVANCED — the SOW position

**One SOW-contracted activity: 2.g, three of four Section 7 unknowns closed.**

Everything else today was methodology or record correction, and the commits say
so in their own bodies rather than leaving it to be inferred.

| commit | what | SOW |
|---|---|---|
| `a00a522` | `build.sh` site-portable via `XILINX_ROOT` | methodology |
| `0f48230` | corrected false 2.g design-doc reference | record correction |
| `157f367` | three of four §7 unknowns answered from measurement | **2.g** |

2.f: still NOT STARTED. 2.g: still DESIGN LOST and NOT IMPLEMENTED — findings
are not a design. Nothing was built, configured, or flashed. No board was
touched all session.

### The actionable finding

`docs/design/SOW_2G_SEC7_UNKNOWNS.md` (md5 `15adb3ba8624a4bca483ce365f8d5028`,
205 lines) carries all citations. The headline:

- **Q1 `fw_setenv` on rootfs: NO.** A/B env mechanism exists in U-Boot
  (`CONFIG_ENV_IS_IN_FAT=y`, `CONFIG_SYS_REDUNDAND_ENVIRONMENT=y`) but there is
  no userspace tool to flip the pointer. Half a mechanism. **Open design
  decision: add `libubootenv-bin`, or design the update path to not need it.**
- **Q2 mbedTLS: NO.** `LEGACY_CRYPTO` instead. `CONFIG_FIT_SIGNATURE` also
  unset — 2.g verification is unstarted, not partially met.
- **Q3 watchdog: driver and DT are READY, only the config is off.** Remediation
  is `CONFIG_WDT=y` + `CONFIG_WDT_CDNS=y`. No driver work, no DT work.
- **Q4 FAT redundant env on the card: OPEN.** Needs physical card access.

**Caveat that governs all of the above:** measured in `~/zcu102-spidev` on
stile, whose `BOOT.BIN` (`57f6a85d…`) and `image.ub` (`f8f6a757…`) do NOT match
the recorded known-good artifacts (`a25d6549…`, `ffe0c75b…`). These are
properties of that build tree, not of either physical board.

---

## 2. THE 2.g DESIGN DOCUMENT IS GONE

`CONTINUATION_PROMPT_TWOSITE.md` asserted an md5 for
`docs/design/SOW_2G_APPLIANCE_DESIGN.md` and stated 2.g "is now designed."
Neither that file nor `SESSION_RECAP_20260817.md` has ever existed.

Four independent negatives, all on stile 2026-08-19: absent from the working
tree (`docs/design/` existed and was EMPTY); absent from every branch's history;
absent from stash; and absent BY CONTENT — nothing under `~` hashes to
`599e0404` or `475a53a0`, which rules out a rename. `git check-ignore` later
confirmed `docs/design/` carries no ignore rule, closing the last alternative
mechanism.

`~/.bash_history` was checked and is **inconclusive** — exactly 2000 lines
(HISTFILESIZE default, truncated), no timestamps. It is not cited as evidence.

Most likely mechanism: directories created in preparation, md5s recorded from
documents that existed only in a chat session, nothing written to disk. This is
the exact failure Section A of that same file warns against.

Corrected in `0f48230` at four sites, with the two false lines **preserved
verbatim** so the error stays legible. 2.g status line changed to DESIGN LOST.

**Consequence for the MSR:** 2.g's "designed, not implemented" was not backed by
a durable artifact. 2.g is half the December 9-month deliverable. Realized risk,
disclosed — not defended after the fact.

---

## 3. CLAUDE FAILURE MODES OBSERVED THIS SESSION

Recorded as a pattern with a named mechanism, so the next session knows what to
check rather than merely that errors occurred.

### 3.1 Citation from inference — recurred repeatedly, all caught pre-commit

Line numbers and section letters written into commit messages from arithmetic or
recollection instead of read off the file. Wrong every time it happened, in both
directions (pre- vs post-patch numbering; a section letter that named a different
section entirely; edit ranges never measured at all).

Mechanism: **a number written from inference rather than read off the file.**

**Countermeasure that worked:** every `file:line` in a commit message gets a
`grep -n` before the commit fires. `157f367`'s message was deliberately written
with NO independently-derived line numbers — all citations live in the committed
document where they were measured — which removes the failure surface entirely.

### 3.2 A check that could not have failed

`echo "exit=$?"` after `cpio … | grep …` captured **grep's** status, not cpio's
— so it could not distinguish "not present" from "archive unreadable", which was
the entire reason for the check. Replaced with a real positive control:
`bin/mkimage` matches exactly 1 entry in the same 2503-entry archive.

**Rule:** a zero-result grep is meaningless without either a line/entry count or
a positive control on the same input. Applied throughout §7 work thereafter.

### 3.3 Absence inferred from a failed probe — caught before it propagated

`ls docs/design/…` failed, and the reflex read was "the directories don't
exist." Wrong: both existed. Only listing the parent showed it. Earlier in the
same session a `find` hit was over-generalized into "the convention is
`docs/session-recaps/`, not `docs/sessions/`" — both exist.

**Rule:** a failed path probe is evidence about the path, not about the file.

### 3.4 Mode stripped by a patch script

The first patch script wrote via a fresh temp file and `os.replace()`, which
does not inherit the target's mode. `build.sh` went 100755 → 100644. **Not**
visible in `git status --porcelain` (` M` covers mode changes) or in
`git diff --stat`; only the full `git diff` header showed it.

**Standing fix, applied in the second patch script and verified:** capture
`os.stat(PATH).st_mode` before the write, `os.chmod` after, assert it.

---

## 4. STATE OF THE RECORD

- `linux/src/build.sh` — `fcf86708805042cc6f9589c78cf8f5d4`, mode 100755 in the
  tree. Regression verified: with `XILINX_ROOT` and `CC` both unset it still
  produces `ff194b38…` / BuildID `77e00aef…`.
- **The session prompt's premise was wrong.** `build.sh` was never "pinned" —
  line 70 was already `${CC:-…}`, so Morgan could always have run it by
  exporting `CC`. The commit narrows the site-varying surface from a full path
  to a prefix; it does not create an ability that did not exist. Recorded in
  `a00a522` so the narrower claim is what survives.
- **Wrapper facts re-measured on stile today** rather than carried forward: the
  compiler at the path tail is 189 bytes, mode 100755, Apr 25 2025, a bash
  script that re-invokes `aarch64-amd-linux-gcc` with `--sysroot` and
  `-mbranch-protection=none` injected. Only "11.4.0 at the verify site" remains
  carried forward from 2026-08-18.
- `docs/sessions/CONTINUATION_PROMPT_TWOSITE.md` —
  `f313500a432872d69305585ae48d6aa6`. Still authoritative for Sections A–H, but
  its `build.sh` description and 2.g state are superseded by this file.

---

## 5. NEXT SESSION — MORGAN (`bxqp8b3-ub22`)

Both open items need Morgan. Do them in this order.

### 5.1 Step 0.5 — cross-site artifact reproducibility

**EXECUTED 2026-08-20 at Morgan. Outcome: BUILDS BUT DIFFERS** -- the third
outcome listed below, not reclassified after the fact. Result and full
evidence: `docs/environment/STEP_0_5_CROSSSITE_20260820.md`
(md5 `ab75ca9ec1a1fb0ba1c9911cb2f01e01`, commit `cfb2ffd`).

Stripped of DWARF debug info and the BuildID note, both binaries are
byte-identical at `cd32416b2baf7eb38939214d85a142a6` (71720 bytes). The
divergence is confined to `.debug_line_str` and the two sections holding
offsets into it; the mechanism is the differing build path. The glibc
sysroot strings are identical at both sites, so changing `XILINX_ROOT` did
NOT resolve a different sysroot -- the specific unknown flagged at the end
of this section.

The procedure below is retained as the reproduce steps. The three-outcome
list is retained UNEDITED: that it named this outcome in advance is part of
what makes the result credible.

From `~/msu2-verify/spi-soc-research`, after `git pull`:

```
export XILINX_ROOT=/home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1
ls -l "$XILINX_ROOT/Vitis/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-gcc"
ls -l "$XILINX_ROOT/Vitis/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-readelf"
env -u CC sh linux/src/build.sh
```

The second `ls` matters: `build.sh:107` derives `READELF` from
`dirname "$CC"`. If that file is absent the fallback takes host readelf —
binutils **2.38** at Morgan vs **2.42** on stile. **Rule out the measuring
instrument before blaming the build.**

Three legitimate outcomes, none of them a failure by default:

- **Byte-identical** → cross-site artifact reproducibility established.
- **Refuses** → record the refusal verbatim, then ask whether the refusal is
  CORRECT before treating it as a problem.
- **Builds but differs** → the most informative outcome. Record `.comment`,
  `--version` line 1, BuildID, and `.text`/`.rodata` sizes from BOTH sites
  before drawing any conclusion.

Record regardless of outcome: compiler `--version` first line, produced
`.comment`, BuildID, md5, and **which readelf was actually used**.

Why the result cannot be predicted from stile: the 189-byte wrapper resolves
both the real compiler and the sysroot **relative to its own location**
(`` `dirname $0`/../x86*/… `` and `` `dirname $0`/../cortexa72-cortexa53-amd-linux ``).
Changing `XILINX_ROOT` moves the sysroot in lockstep.

### 5.2 Q4 — FAT redundant environment on the card

Morgan has console, JTAG **and** card reader on one machine. Card reader is
Realtek RTS5129; no card was inserted at recon time.

Mount the SD card's FAT partition read-only and establish whether the redundant
environment files exist and are valid. `CONFIG_ENV_IS_IN_FAT=y` +
`CONFIG_SYS_REDUNDAND_ENVIRONMENT=y` mean U-Boot is BUILT for it; the card is a
separate question.

**Never hardcode `ttyUSB<N>`.** Use `by-id`; node numbers shift with plug order.
Console (CP2108 quad bridge, serial `B66A78CB12A648B611E661AF58A7182`):
`usb-Silicon_Labs_CP2108_Quad_USB_to_UART_Bridge_Controller_…-if00-port0`.
**`if00` being the console is AMD convention, NOT measured — confirm on a boot.**
JTAG is the Digilent FT232H, serial `210308A46334`.

### 5.3 If time remains, at either site

- **Recapture the LPS host baseline from a clean tree.** The committed one
  (`docs/environment/recon_host_LPS_stile_20260817.txt`) self-flags
  `dirty_paths: 2` and so cannot establish reproducibility by its own rule.
- **Fix the five `recon_host.sh` defects** (probes only `/tools/Xilinx/2025.1`;
  hardcodes a host-gcc version; misses the installed PetaLinux SDK; probes only
  two of five ttyUSB nodes; records node existence rather than device identity).
  Do not commit Morgan recon output until these are fixed.

---

## 6. OPEN — carried forward

- **Q4** (§5.2 above).
- **D-1 PetaLinux 2025.1 vs 2025.2** at Morgan. Gates any 2.g U-Boot rebuild,
  including the Q3 watchdog remediation. Check UG1144 for whether Ubuntu 22.04
  is a supported host for 2025.1 BEFORE downloading; needs `df -h` to price it.
- **D-2 mkimage** 2022.01 vs 2025.10 against a U-Boot 2025.01 target.
- **D-4 board alignment** — common flashed image first, or must the procedure
  work from both starting states?
- **Image md5 mismatch.** Establish which tree produced the board's current boot
  image. `~/zcu102-spidev` did not.
- **Double SPI alias.** The built U-Boot DTB aliases BOTH `spi1` and `spi2` to
  `/axi/spi@ff050000`. Given this project's history with mislabeled controller
  identity, verify before reasoning from U-Boot SPI aliases.
- **TPM2-over-SPI is enabled in U-Boot** (`CONFIG_TPM=y`, `TPM_V2`,
  `TPM2_TIS_SPI`, `TPM_RNG`). Relevant to 2.g verification. NOT claimed: that a
  TPM is physically present, wired, or bound by any DT node.
- **Device tree identity unresolved.** `CONFIG_DEFAULT_DEVICE_TREE` names
  zcu100-revC (Ultra96); the built blob is generic `xlnx,zynqmp` with no `model`
  and zero board-name occurrences. Not Ultra96, not provably ZCU102.

## 7. NOT RECONCILED — flagged, not actioned

`MSU2_Session_Recap_Onboarding.docx` presents a bare-metal vs Linux table
(3.73× at 1 B settling to 1.21×, "~28 µs fixed OS overhead") as measured on the
same wire at the same clock. Per the established record, `spidev1.0` maps to AXI
Quad SPI at `0xa0000000`, not PS SPI1, and Linux access to PS SPI1 is blocked at
the ATF. If that holds, the comparison is Linux-on-AXI vs bare-metal-on-PS-SPI1
and the OS-tax attribution does not survive as written.

Separately, `emio_results.csv` / `mio_results.csv` are 3-column with a flat
1.0 µs placeholder stddev, and the reduction from 5+ columns was done BY HAND
with the reducing step absent from the repo.

**Do not put that table in front of a demo audience until both are reconciled.**
