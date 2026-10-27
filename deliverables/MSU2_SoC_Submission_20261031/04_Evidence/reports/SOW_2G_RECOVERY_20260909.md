# SOW 2.g -- Induced-Corruption Recovery, ZCU102 #2, 2026-09-09

## Scope

SOW 2.g Robustness leg: "Implement an update mechanism that ensures the
device remains bootable in the event of an interrupted or corrupted
software update."

The 2026-09-08 session measured that `fw_setenv` rewrites exactly one copy
of the redundant U-Boot environment pair. That is a *precondition* for
interrupt-safe update, not a demonstration of it. This session induces the
fault and observes the outcome.

Environment redundancy only. Nothing here concerns `image.ub`, kernel or
rootfs update robustness.

## Environment on-media layout, established by CRC

Not assumed from Kconfig. `crc32(b[5:])` matched the stored value in both
copies; `crc32(b[4:])` matched neither.

    offset 0..3   crc32, little-endian
    offset 4      redundancy flag byte
    offset 5..    NUL-separated name=value payload
    total         262144 bytes (0x40000) per copy

## Method

Three `fw_setenv` writes to arm the test, each followed by `sync`, an md5
of both copies, and a flag-byte read via `od`.

    write                     uboot.env (primary)     uboot-redund.env
    (start)                   9afabc88... flag 02     5c78f167... flag 03  ACTIVE
    1  bootdelay 5            0b7781c0... flag 04     unchanged
    2  bootdelay 5 (again)    unchanged               unchanged
    3  msu2_probe probe_...   unchanged               8ad2c8af... flag 05  ACTIVE

Then 512 bytes of `/dev/urandom` written at offset 4096 of the ACTIVE copy
with `dd conv=notrunc`, on the host with the partition mounted rw. Size,
filename, stored CRC and flag byte all left intact -- this models a torn
write during an update, not a deleted file.

`bootdelay=5` was placed in BOTH copies so the U-Boot prompt stays
reachable whichever copy survives. `msu2_probe` was placed in ONE copy as
the discriminator.

## Why boot success is not the result

A boot with NO environment files present also reaches a Linux login
prompt. Observed 2026-09-08: U-Boot printed `*** Error - No Valid
Environment Area found` then `*** Warning - bad env area, using default
environment`, and booted to userspace normally.

So "the board booted" cannot distinguish fallback from total environment
loss. The variable-level check is the discriminator:

  - `msu2_probe` ABSENT      => did not read the corrupted copy
  - `msu2_marker` PRESENT    => did not fall back to compiled-in defaults

Both together identify the primary uniquely.

## Result

Console, recovery boot (`artifacts/2g-fwenv/zcu102-2_2g_corrupt_20260909.log`):

    Loading Environment from FAT... OK
    Hit any key to stop autoboot:  5
    ZynqMP> printenv msu2_probe
    ## Error: "msu2_probe" not defined
    ZynqMP> printenv msu2_marker
    msu2_marker=uboot_20260908
    ZynqMP> printenv bootdelay
    bootdelay=5

The device remained bootable and the interactive prompt remained
reachable with one of two environment copies destroyed. SOW 2.g
Robustness property DEMONSTRATED.

### Selection rule, measured

Each `fw_setenv` targets the INACTIVE copy and stamps it `active_flag + 1`.
Write 1 went 02 -> 04, skipping 03, because the active copy held 03. The
flag is a global counter, not a per-file increment.

The corrupted copy carried flag 05 against the primary's 04, so it was the
PREFERRED copy by that rule. U-Boot selected it, found the CRC wrong, and
used 04 instead.

### U-Boot does not self-heal

Post-boot hashes, card read on the host with the partition remounted ro:

    0b7781c0e30f35aa2d86e1da8e29d348  uboot.env          UNCHANGED, CRC MATCH, flag 04, 76 vars
    38b7167b8d48c5bd52342c80790ef49b  uboot-redund.env   UNCHANGED, CRC MISMATCH, parse fails

Not one byte moved. U-Boot does not write during environment load.

(This also disposes of a caveat: the card was pulled while the board sat
at the U-Boot prompt. Since nothing changed, there is no ambiguity between
"U-Boot repaired the copy" and "the pull disturbed FAT".)

## Recovery is silent -- design recommendation

U-Boot's environment-load line across three card states:

    both copies valid      Loading Environment from FAT... OK
    ONE COPY CORRUPT       Loading Environment from FAT... OK
    no environment at all   *** Error - No Valid Environment Area found

A single-copy failure is indistinguishable from a healthy boot on the
console. Combined with the no-self-heal result, a deployed appliance
silently continues with ZERO remaining redundancy after one corruption
event, and the next event is unrecoverable. There is no console
indication and no automatic repair.

RECOMMENDATION: the appliance requires periodic active verification of
both environment copies plus an explicit repair path. Transparent recovery
is desirable; undetectable loss of redundancy is not.

## Secondary findings

- **`fw_setenv` success is not evidence of a write.** Write 2 set
  `bootdelay` to a value it already held; libubootenv skipped it and did
  not touch the media at all. Only the hash is evidence. A no-op-skipping
  update tool is desirable for an appliance (no wear, no exposure window),
  but it breaks any inference from exit status.
- **A discriminator survives exactly one write cycle.** Each write copies
  the full active set to the other copy, so `msu2_linux_marker`
  (redundant-only before today) is now in both copies and is no longer a
  discriminator.
- **`bootdelay` already existed in the saved environment.** Var count went
  76 -> 76 -> 77 across three writes; write 1 changed its value in place.
- **U-Boot autoboot is now a repeatable demo procedure.** `bootdelay=5`
  prints `5` then backspace-overwrites to `0` on keypress
  (`: 5 \b \b \b   0`). Control: every `Hit any key` line in the baseline
  and August logs shows `0` with no preceding digit. The prior
  zero-second keypress race is retired.
- **RTC cold value is 1970, not 2025-01-08.** Three cold boots read
  `rtc_zynqmp ... setting system clock to 1970-01-01T00:00:05/00:00:10/
  00:01:10 UTC`. systemd then advances to the image build date
  (2025-01-08). Consequence: a failed `date` command leaves systemd's
  value, and `hwclock -w -u` then writes 2025-01-08 to the RTC.
- **`hwclock -w -u` does not survive a power cycle.** A boot that set
  16:58 and wrote the RTC was followed by a cold boot reading 1970. The
  write is accepted and lost.
- **FAT mtimes are not uniformly bogus.** `uboot.env` carries 2025-05-16;
  `uboot-redund.env` carried 2026-09-08 13:39:22 -0400 because the board
  clock had been set before that write. 13:39 EDT = 17:39 UTC corroborates
  the marker `linux_20260908_1738`. mtimes remain non-provenance; hashes
  only.

## Artifacts

    artifacts/2g-fwenv/env-snapshots/
      uboot.env.pre-fwsetenv-20260908         9afabc88dbd465d121decc96433cf518
      uboot-redund.env.pre-fwsetenv-20260908  5b2408144a8ad75e827feae14fdf4290
      uboot.env.post-fwsetenv-20260908        9afabc88dbd465d121decc96433cf518
      uboot-redund.env.post-fwsetenv-20260908 5c78f16778e05b1c75d858b4569e9e3a
      uboot.env.armed-20260909                0b7781c0e30f35aa2d86e1da8e29d348
      uboot-redund.env.armed-20260909         8ad2c8af53b17db79433bfb92dd01410
      uboot-redund.env.corrupted-20260909     38b7167b8d48c5bd52342c80790ef49b
      uboot.env.postboot-20260909             0b7781c0e30f35aa2d86e1da8e29d348
      uboot-redund.env.postboot-20260909      38b7167b8d48c5bd52342c80790ef49b

    artifacts/2g-fwenv/
      zcu102-2_2g_baseline_boot_20260909.log  4d84b519d6376fb72ec91682079574ad
      zcu102-2_2g_corrupt_20260909.log        f63039848dcf60884a37b10a8844e91a

`uboot-redund.env.armed-20260909` is the byte-exact restore source for the
corrupted copy.

## Reproducing the demo

1. Restore both copies from `env-snapshots/*armed-20260909` onto the FAT
   partition; verify md5.
2. Corrupt one copy: `dd if=/dev/urandom of=<copy> bs=1 seek=4096
   count=512 conv=notrunc`.
3. Boot. Press a key within the 5-second window.
4. `printenv msu2_probe` -> not defined; `printenv msu2_marker` -> set.

No PetaLinux build required. The `fw_printenv` binaries and
`fw_env.config` are committed under `artifacts/2g-fwenv/`.

## DELIBERATELY NOT CLAIMED

- The corruption was authored on the host, not produced by an interrupted
  write on the board. It reproduces the resulting on-media state, not the
  interruption mechanism.
- Only the ACTIVE copy was corrupted. Corrupting the inactive copy, or
  both, is untested.
- One trial. No repetition, no variation of corruption offset or length.
- Nothing established about `image.ub`, kernel or rootfs update
  robustness.
- Verification leg of 2.g (`CONFIG_FIT_SIGNATURE`) remains at ZERO. This
  session addressed Robustness only.
- The rootfs is INITRD and `libubootenv-bin` is not provisioned in it.
  2.g remains a demonstration, not a deployable appliance.
- `bootdelay=5` is now saved in the environment on this card. That is a
  deliberate test-fixture change, not a production setting.
