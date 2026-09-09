# Session Recap -- 2026-09-09, Morgan CAP, ZCU102 #2

## SOW scope

SOW 2.g, Robustness leg. Contracted activity, not methodology.

Entering the session, 2.g's robustness claim rested on a measured
*precondition*: `fw_setenv` rewrites exactly one copy of the redundant
U-Boot environment pair (2026-09-08, `42b6616`). The SOW asks for a
mechanism that "ensures the device remains bootable in the event of an
interrupted or corrupted software update." A single-copy write pattern
does not demonstrate that. This session induced the fault.

## Result

**SOW 2.g Robustness leg CLOSED on hardware.** With one of two
environment copies destroyed, the device booted and the interactive
prompt remained reachable. Full note:
`results/SOW_2G_RECOVERY_20260909.md` (`41ae624e176a636c18cea3fc4efc822a`).

Commits, all pushed:

    6908806  archive post-fw_setenv pair off the SD card
    ac2a9d0  arm and corrupt the pair (pre-boot state)
    8e00c92  induced-corruption recovery DEMONSTRATED
    94d3cfe  restore leg verified, discriminator confirmed both directions

## What was established

- **Fallback works.** Corrupted copy identified positively by
  `msu2_probe` absent + `msu2_marker` present -- not by boot success. A
  boot with no environment at all also reaches a Linux login prompt, so
  boot success alone distinguishes nothing.
- **Discriminator demonstrated in both directions.** `msu2_probe` absent
  on the corrupted boot, `probe_20260909` on the restored boot. Same
  board, same card, same U-Boot binary.
- **Selection rule measured.** Each `fw_setenv` targets the INACTIVE copy
  and stamps it `active_flag + 1`; the flag is a global counter, not a
  per-file increment (write 1 went 02 -> 04, skipping 03). The corrupted
  copy was the PREFERRED copy at flag 05; U-Boot selected it, found the
  CRC wrong, used 04.
- **U-Boot does not self-heal.** Both copies byte-identical across the
  recovery boot. U-Boot does not write during environment load.
- **On-media layout established by CRC**, not assumed: 4-byte LE crc32,
  flag byte at offset 4, payload from offset 5.
- **Byte-exact restore out of the git object store** verified by hash on
  readback.

## Design recommendation produced

U-Boot prints `Loading Environment from FAT... OK` identically whether
both copies are valid or one is destroyed. Combined with no self-heal, a
deployed appliance silently continues with ZERO remaining redundancy and
the next corruption is unrecoverable. No console indication, no automatic
repair.

The appliance requires periodic active verification of both copies plus
an explicit repair path. This is only findable by inducing the fault.

## Demo procedure -- the session's reproducibility goal

No host, no PetaLinux build, no hashing at demo time:

1. Press a key within the 5-second autoboot window.
2. `printenv msu2_probe` -- present => both copies healthy;
   absent => running degraded on the primary.

`bootdelay=5` now saved in both copies retires the zero-second keypress
race the record flagged as "not a repeatable demo procedure."

## Record corrections

- **RTC cold value is 1970, not 2025-01-08.** Three cold boots read
  `1970-01-01T00:00:05 / 00:00:10 / 00:01:10`. systemd then advances to
  the image build date (2025-01-08). Consequence: a failed `date`
  command leaves systemd's value and `hwclock -w -u` writes 2025-01-08
  to the RTC.
- **`hwclock -w -u` does not survive a power cycle at all.** A boot that
  set 16:58 and wrote the RTC was followed by a cold boot reading 1970.
  Accepted and lost. No point writing it for persistence.
- **FAT mtimes are not uniformly bogus.** `uboot.env` carries 2025-05-16;
  `uboot-redund.env` carried a correct 2026-09-08 13:39:22 -0400 because
  the board clock had been set before that write. Hashes remain the only
  provenance.
- **`bootdelay` already existed in the saved environment.** Var count
  76 -> 76 -> 77 across three writes; write 1 changed its value in place.
- **Running `image.ub` is 2025.1-built** (`PetaLinux
  2025.1+release-S05180137`), while the project's tool is 2025.2. This
  independently corroborates the lineage caveat blocking the 2.f
  preemption axis: the running image differs from a local build by TOOL
  VERSION, not just build instance. Strengthens the case for a stock
  rebuild first.
- **`fw_setenv` success is NOT evidence of a write.** libubootenv skips a
  write whose value already matches and does not touch the media. Only
  the hash is evidence.
- **A discriminator survives exactly one write cycle.** Any write copies
  the full active set to the other copy. `msu2_linux_marker`, previously
  redundant-only, is now in both copies. A future demo cycle needs a
  FRESH discriminator written before arming.

## Card state on leaving

Two valid copies, redundant active at flag 05. NOT the pre-session state:
`bootdelay=5`, `msu2_probe`, `msu2_marker` and `msu2_linux_marker` are all
present as deliberate test fixtures. Pre-session `bootdelay` was 0.

Pre-session pair is recoverable from `env-snapshots/*post-fwsetenv-20260908`
if a clean baseline is ever needed.

## Process notes

- Two heredocs were interrupted mid-write and produced truncated files.
  Both were caught by the `wc -c` gate before use. The byte-count gate on
  every heredoc is load-bearing, not ceremony.
- `script` block-buffers: a boot log read 12288 bytes (3 x 4096) with the
  U-Boot section missing until picocom exited and flushed. An apparently
  empty `grep` against a live log is not a negative result.
- `dmesg` was unavailable (`kernel.dmesg_restrict`). Recorded as no
  information obtained, not as absence of kernel messages.
- The corruption was executed before the armed pair was committed.
  Reversibility survived because untracked copies existed in two places,
  but that is the state the commit-before-you-break rule exists to
  prevent.

## Still open on 2.g

- Verification leg (`CONFIG_FIT_SIGNATURE`) at ZERO. Untouched.
- Rootfs is INITRD; `libubootenv-bin` not provisioned. 2.g is a
  demonstration, not a deployable appliance. Needs a 2025.2 rebuild.
- Untested: corrupting the INACTIVE copy; corrupting BOTH copies;
  repeated trials; varied corruption offset and length.
- Corruption was host-authored. It reproduces the on-media state of a
  torn write, not the interruption mechanism.
- Nothing established about `image.ub`, kernel or rootfs update
  robustness.

## Next session candidates

Board-free, repo-only:
  - `recon_host.sh` five documented defects; LPS baseline recapture
  - 6.25 vs 15.625 MHz triage across six files (classify each as
    historical-and-correct or current-and-wrong; do not bulk-edit)

Needs a build:
  - Provision `libubootenv-bin` into the rootfs under 2025.2, removing the
    INITRD caveat
  - 2.f preemption axis -- STOCK REBUILD FIRST per the lineage caveat,
    now corroborated by the 2025.1-vs-2025.2 observation above

Primary schedule risk remains 2.f. December deliverable is 2.f and 2.g.
September MSR due the 5th working day of October; this session supplies
2.g content traceable to four commits.
