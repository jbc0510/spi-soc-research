# Step 0.5 — Cross-Site Artifact Reproducibility: Result

Executed at Morgan (`bxqp8b3-ub22`), 2026-08-20. Build site was `stile` (LPS),
2026-08-19, commit `a00a522`. MSU-2 Task 2, IAC/TAT P1-22-2393.

## OUTCOME

**Not byte-identical. Fully characterized. The divergence is confined to DWARF
debug metadata and the BuildID derived from it.**

With debug info and the BuildID note removed, the two binaries are byte-
identical:

```
aarch64-linux-gnu-objcopy --strip-debug --remove-section=.note.gnu.build-id

  stile   ->  cd32416b2baf7eb38939214d85a142a6   71720 bytes
  Morgan  ->  cd32416b2baf7eb38939214d85a142a6   71720 bytes
```

That single hash covers everything allocated — code, read-only data,
relocations, symbol table, dynamic linking structures. It is the primary claim
of this document. The section-by-section evidence below supports it; it does not
replace it.

This is the third of the three outcomes named in advance
(`SESSION_RECAP_20260819.md` §5.1): **builds but differs.** It was recorded as
"the most informative outcome available" before the build was run, and it was
not reclassified after the fact.

## THE TWO ARTIFACTS

| | stile | Morgan |
|---|---|---|
| md5 | `ff194b3828edc13d06ba26ef816c8616` | `1232ebcd051ca9716e83ef929ded1e5e` |
| BuildID | `77e00aefea51384d655b0481d467c4c53c2a6a00` | `b4ab90402dfd89efe679b2cdc3a6980662c9ce61` |
| size | 94544 | 94872 |
| `.comment` | `GCC: (GNU) 13.3.0` | `GCC: (GNU) 13.3.0` |
| `--version` line 1 | `aarch64-amd-linux-gcc.real (GCC) 13.3.0` | identical |
| `file(1)` | PIE, dynamically linked, debug_info, not stripped | identical |

stile's artifact is the one tracked in git; it was extracted for comparison with
`git show HEAD:linux/src/spi_benchmark_v2_aarch64` and confirmed at
`ff194b38…` before use. Both binaries were therefore compared **on one machine**,
not across sites by description.

## PRECONDITIONS VERIFIED BEFORE THE BUILD RAN

Deliberately measured first, so that no result could later be explained away by
an unverified assumption.

- **Clean clone.** `git status --porcelain` empty before `git pull`; fast-forward
  `fdd43fa..37f2816`; all four tracked md5s reproduced, including the target
  artifact at `ff194b38…`.
- **Compiler wrapper identical.** 189 bytes, Apr 25 2025, at both sites. `cat`
  shows the same script: same relative globs for the real compiler and the
  sysroot, same `--sysroot=$LIBC`, same `-mbranch-protection=none`.
- **readelf resolved INSIDE Vitis, not to the host.** `build.sh` derives
  `READELF` from `dirname "$CC"`; that file exists at Morgan (117 bytes,
  matching stile's recorded 117-byte wrapper) and reports
  `GNU readelf (GNU Binutils) 2.42.0.20240723`. Host binutils here is **2.38**.
  The instrument is therefore identical at both sites and **cannot explain any
  difference below.** This check was run BEFORE the build.
- **The `$PATH` hazard is real, not theoretical.** `/usr/bin/aarch64-linux-gnu-gcc`
  exists at Morgan and reports
  `aarch64-linux-gnu-gcc (Ubuntu 11.4.0-1ubuntu1~22.04.3) 11.4.0`. Had
  `build.sh` searched `$PATH`, it would have found that, built successfully, and
  produced different bytes with no refusal. The decision recorded in `a00a522`
  not to search `$PATH` is vindicated by measurement.

## SECTION EVIDENCE

Extracted with `objcopy --dump-section` (see METHOD ERROR below) and compared by
md5. Sizes in bytes.

| section | stile | Morgan | |
|---|---|---|---|
| `.text` (3800) | `f7a2462f087384f15a84ae4b5227c8bb` | same | identical |
| `.rodata` (3452) | `2a5ab85f36fc2dec7db1391f918f65a3` | same | identical |
| `.debug_str` (2654) | `b3dfcefe` | `b3dfcefe` | identical |
| `.debug_abbrev` (1324) | `0d1699eb` | `0d1699eb` | identical |
| `.debug_loclists` (2846) | `fc28e779` | `fc28e779` | identical |
| `.debug_rnglists` (603) | `06e441ac` | `06e441ac` | identical |
| `.debug_aranges` (304) | `c1b92711` | `c1b92711` | identical |
| `.debug_line_str` | 1386 / `77ab6d70` | **1715** / `eacdcf35` | differs, +329 |
| `.debug_info` (9743) | `17e64603` | `2e0e786b` | same size, differs |
| `.debug_line` (2754) | `de34cf11` | `aeeb8cd3` | same size, differs |

`.text` size `0xed8` at offset `0xf40` and `.rodata` size `0xd7c` at `0x1e30`
match the values recorded on stile at build time.

Section-header comparison (`readelf -SW`, diffed): every section through
`.debug_str` has identical offset AND size. Only `.debug_line_str` changes size.

## MECHANISM

`.debug_line_str` is the DWARF line-number string table. It holds compilation
directories and source file paths. Measured contents:

```
stile   /home/jconway/spi-soc-research/linux/src/spi_benchmark_v2.c
Morgan  /home/opentitan/msu2-verify/spi-soc-research
```

(First differing entry. The listing was truncated at five lines, so this is not
the complete set of differing strings.)

**The glibc sysroot strings are IDENTICAL at both sites** —
`/usr/src/debug/glibc/2.39+git/csu`, `/posix/bits`, `/bits`, `/elf`. This is the
specific hypothesis the wrapper's relative sysroot resolution created, and it is
killed by measurement: changing `XILINX_ROOT` did NOT cause a different sysroot
to be found.

`.debug_info` and `.debug_line` hold 4-byte offsets INTO `.debug_line_str`, so
their contents change while their sizes do not. That is consistent with the
observed pattern and is the expected consequence, not a separate finding.

Arithmetic, all measured from the section table:

- `.debug_line_str` grows 329 bytes (1386 -> 1715).
- `.debug_loclists` and `.debug_rnglists` shift by exactly `0x149` = 329.
- `.symtab`, `.strtab`, `.shstrtab` and the section-header table shift by
  `0x148` = **328**, one less.
- The file grows 328 bytes, not 329.

The missing byte is alignment padding. `.symtab` has alignment 8. On stile
`.debug_rnglists` ends at `0x1555ae` and `.symtab` starts at `0x1555b0` — 2 bytes
of padding. At Morgan the same boundary is `0x1556f7` -> `0x1556f8` — 1 byte. The
extra content byte was absorbed by the padding gap. Stated because a 328-vs-329
discrepancy left unexplained is the kind of loose end that invites a wrong
conclusion later.

First differing byte in the files is at offset 41, which is `e_shoff` in the ELF
header — consistent with the section-header table moving from `0x16810` to
`0x16958`.

## METHOD ERROR — recorded

The first attempt to compare debug sections used:

```
objcopy -O binary --only-section=<name> <in> <out>
```

`-O binary` emits only SHF_ALLOC sections. Debug sections are not allocated, so
**all sixteen extractions produced zero-byte files** and every pair hashed to
`d41d8cd9…` — the md5 of an empty file. The comparison reported eight false
"identical" results and gave no error.

Corrected with `objcopy --dump-section <name>=<out>`, which does not filter on
SHF_ALLOC. The `.text` / `.rodata` results were re-verified by checking the
extracted file sizes (3800 and 3452, matching the section table) before their
hashes were trusted.

**Rule: check the SIZE of an extraction before trusting its HASH. An empty
extraction hashes equal to another empty extraction.** This is the same class as
the `echo $?`-after-a-pipeline error recorded in `SESSION_RECAP_20260819.md`
§3.2: a check that could not have failed.

## SITE DIFFERENCE THAT IS NOT DRIFT

`linux/src/build.sh` is mode `775` at Morgan and `755` on stile. This is the
local umask (002 vs 022), not a tree difference. Git records only the exec bit
and it survived the round trip (`git ls-tree` = `100755`). Recorded so it is not
later mistaken for corruption.

## D-5 — OPEN DECISION, NOT DECIDED HERE

`-ffile-prefix-map` (or `-fdebug-prefix-map`) would normalise the build path and
make future builds byte-identical across sites.

**Cost:** the flag changes output at BOTH sites. `ff194b38…` would no longer be
what `build.sh` produces, so the committed artifact must be regenerated and
every recorded reference to that md5 updated. The current provenance chain would
be broken deliberately and re-established.

Not urgent — nothing is broken, and the equivalence above is already established
by measurement. Deferred by decision, not by omission.

## DELIBERATELY NOT CLAIMED

- That either binary is correct. Neither was executed. This is a byte-level
  comparison only, and says nothing about runtime behaviour on either board.
- That the two binaries are interchangeable in any sense beyond the stripped
  equivalence measured above.
- That the complete set of differing `.debug_line_str` strings is known. Only
  the first five entries of each were listed.
- Q4 (FAT redundant environment on the SD card). Untouched. Still open.
- Any SOW contractual activity. This is the two-site protocol, not a SOW
  deliverable. Nothing in SOW 2.a–2.g advanced by this document.

## REPRODUCE

At Morgan, from `~/msu2-verify/spi-soc-research` on commit `37f2816`:

```
export XILINX_ROOT=/home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1
env -u CC sh linux/src/build.sh
git show HEAD:linux/src/spi_benchmark_v2_aarch64 > /tmp/v2_stile
cp linux/src/spi_benchmark_v2_aarch64 /tmp/v2_morgan
O="$XILINX_ROOT/Vitis/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-objcopy"
for f in stile morgan; do
  "$O" --strip-debug --remove-section=.note.gnu.build-id /tmp/v2_$f /tmp/strip_$f
done
md5sum /tmp/strip_stile /tmp/strip_morgan
git checkout -- linux/src/spi_benchmark_v2_aarch64
```

Both stripped files must be `cd32416b2baf7eb38939214d85a142a6`.

The working tree MUST be restored afterwards. Morgan's binary is evidence and
must not enter the tree; the tracked artifact stays at `ff194b38…`.
