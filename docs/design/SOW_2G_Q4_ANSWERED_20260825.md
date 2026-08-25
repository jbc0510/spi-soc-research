# SOW 2.g — Q4 and Q4-prime ANSWERED on ZCU102 #1

Measured at LPS on `stile`, 2026-08-25, at the U-Boot prompt of ZCU102 #1.
MSU-2 Task 2, IAC/TAT P1-22-2393. Repo commit `94e9119`.

Raw evidence: `docs/environment/zcu102-1_saveenv_20260825.log`
(33718 bytes, md5 `88f24140fb934e31cc5ec23567b47123`), a single `script(1)`
capture of the whole session.

## THE HEADLINE

**The SOW 2.g A/B environment mechanism EXISTS, INITIALISES, and RECOVERS —
demonstrated on hardware, not inferred from config symbols.**

This changes the standing of 2.g. Until today the record had two config
symbols (`CONFIG_ENV_IS_IN_FAT`, `CONFIG_SYS_REDUNDAND_ENVIRONMENT`) and no
evidence that they did anything. Yesterday's measurement on ZCU102 #2 showed
U-Boot creates no environment file at boot, which read as a mechanism that
might not function at all. The honest position going into today was that 2.g's
robustness requirement might need a different design entirely.

It does not. One command initialised it, and the next two boots exercised the
**recovery path** — U-Boot detected a bad copy, fell back to the good one, and
carried on. That is the exact behaviour the requirement asks for after an
interrupted update, and it is now on the record as an observed event with a
raw console capture behind it.

Two qualifications, both material:

1. **It does not work the way the record assumed.** The file is
   `uboot-redund.env` — one file, not `uboot.env` plus `uboot.env.bak`. Every
   procedure written against those two names would have failed on contact with
   the hardware.
2. **The Linux half is still absent.** No `fw_setenv`, no `fw_printenv`, no
   `/etc/fw_env.config`. U-Boot can maintain the pointer; nothing in userspace
   can move it.

So 2.g's robustness requirement goes from *open design question* to *bounded
implementation task* — and the bound is now known, because the hard half turned
out to already work.

## Q4 (ORIGINAL) — ANSWERED: NO ENVIRONMENT EXISTED

The question: is the FAT redundant environment initialised on the board's own
card? Morgan could not answer it (the card in the reader there was blank exFAT,
and ZCU102 #2's slot was empty). This card is ZCU102 #1's own.

**Answer: NO.** Confirmed two independent ways.

U-Boot said so itself on the first boot of the session (log line ~40):

```
Loading Environment from FAT... *** Error - No Valid Environment Area found
*** Warning - bad env area, using default environment
```

And `fatls mmc 0:1` listed 20 files with no environment file among them.
`printenv` showed 6223 of 262139 bytes used, entirely compiled-in defaults —
no `serverip`, no custom variables, nothing project-specific.

That 262139 also establishes `CONFIG_ENV_SIZE` = 0x40000 (256 KB).

### The card is confirmed to be the project card

Not a stray or a supervisor's card. `fatls` showed:

```
BOOT.BIN.linux-backup            BOOT.BIN.pre-rebuild-20260708
BOOT.BIN.linux-a25d6549          BOOT.BIN.baremetal-cb9548d5
spi_benchmark_1mhz.bit.bin       spi_benchmark_12mhz.bit.bin
spi_benchmark_25mhz.bit.bin      spi_benchmark_50mhz.bit.bin
spi_benchmark_jitter_aarch64     spi_pl_dma.dtbo
emio_internal_results.csv        mio_internal_results.csv
```

**Note the last two.** The project record states `emio_internal_results.csv`
and `mio_internal_results.csv` were "renamed out of existence by `0dc3d8f`".
They are still present on this card, 414 bytes each. Renamed in the repo, not
on the hardware.

## Q4-PRIME — ANSWERED: saveenv WORKS, AND THE FILENAME IS NOT WHAT WE ASSUMED

The question: on a FAT partition with no environment files, does U-Boot create
them? Answered on ZCU102 #2 at Morgan as "not at boot"; the open half was
whether an explicit `saveenv` does it.

**Answer: YES, `saveenv` creates it. But it creates ONE file, not two.**

```
ZynqMP> saveenv
Saving Environment to FAT... OK

ZynqMP> fatls mmc 0:1
   262144   uboot-redund.env
21 file(s), 0 dir(s)
```

**`uboot-redund.env`, 262144 bytes (0x40000, matching CONFIG_ENV_SIZE).**

The project record — and `SESSION_RECAP_20260820.md` 8.1 — expected
`uboot.env` AND `uboot.env.bak`. **Neither filename appears.** U-Boot's FAT
environment driver with `CONFIG_SYS_REDUNDAND_ENVIRONMENT` writes a single
file holding both copies, distinguished internally, rather than two files.

**This matters practically.** Any 2.g recovery procedure, update script, or
`fw_env.config` written around two filenames would have failed against a
device that has one. The assumption was never tested until now.

NOT MEASURED: the internal two-copy structure of `uboot-redund.env`. What is
measured is the filename, the size, and that `saveenv` reported OK. The
two-copy explanation is the documented behaviour of that driver, cited here as
the reading that fits, not as something observed.

## THE RECOVERY PATH FIRED — TWICE

Before `saveenv`, every boot said:

```
Loading Environment from FAT... *** Error - No Valid Environment Area found
```

After `saveenv`, both subsequent boots said:

```
Loading Environment from FAT... *** Warning - some problems detected reading
environment; recovered successfully
OK
```

Two occurrences in the capture, on two separate boots.

**Reading:** `uboot-redund.env` holds two slots; `saveenv` wrote one valid
copy; the other is still blank; U-Boot found one bad, fell back to the good
one, and reported success. That is precisely the behaviour SOW 2.g's
robustness requirement needs after an interrupted update.

**Stated as a reading, not a measurement.** Confirming it means a second
`saveenv`, which should write the other slot and produce a clean load with no
warning. NOT DONE.

## WHAT 2.g STILL LACKS

`SOW_2G_SEC7_UNKNOWNS.md` Q1, and the same measurement repeated on ZCU102 #2
yesterday: **no `fw_setenv`, no `fw_printenv`, no `/etc/fw_env.config`** on
the rootfs.

So the position is now precise:

| half | state |
|---|---|
| U-Boot side: redundant FAT env | **WORKS** — initialises and recovers |
| Linux side: userspace tool to flip the pointer | **ABSENT** |

The remediation is no longer a design question. It is: run `saveenv` once at
provisioning time, and add a userspace env tool (`libubootenv-bin`) to the
rootfs with an `fw_env.config` that names `uboot-redund.env` — NOT
`uboot.env`/`uboot.env.bak`.

That is a bounded piece of work. It was not attempted here.

## CORRECTION TO THE RECORD — RTC IS PER-BOARD

ZCU102 #1 set its clock correctly during this session:

```
rtc_zynqmp ffa60000.rtc: setting system clock to 2026-08-25T14:47:08 UTC
```

The project record carries "board RTC reads January 2025 (incorrect)". That
was measured on **ZCU102 #2** on 2026-08-20 (audit stamp `1736360581` =
2025-01-08). **RTC state is per-board.** Captures from #1 carry a valid
`capture_utc`; captures from #2 do not, until its clock is set.

## UNEXPLAINED — SPONTANEOUS REBOOT DURING LINUX BOOT

The capture contains **three** FSBL banners, at log lines 28, 205 and 592.
Line 205 follows an explicit `reset` at line 203. **Line 592 has no preceding
command.** The board restarted itself.

It died at **t = 2.279s**, immediately after the last line printed:

```
[    2.279764] macb ff0e0000.ethernet: invalid hw address, using random
```

U-Boot on both boots also reported `Net: No ethernet found.`

**NOT CLAIMED: that the Ethernet probe caused the reset.** The timing is
suggestive and nothing more. A watchdog, a power event, or an unrelated fault
landing at that moment would look identical from this log. One occurrence.

**This does not affect Q4 or Q4-prime.** Both were measured at the U-Boot
prompt (log lines 75-203), before the first Linux boot was attempted.

**It should be raised with the board's other user.** ZCU102 #1 is shared, and
a board that restarts itself two seconds into Linux is worth her knowing about.

## OTHER OBSERVATIONS FROM THE SAME CAPTURE

- FSBL 2025.1 (May 14 2025), U-Boot `2025.01-ga09d2660433d` (May 16 2025).
- `Bootmode: LVL_SHFT_SD_MODE1`; silicon v3; zu9eg; 2 GiB DRAM (effective 4).
- `Secure Boot: not authenticated, not encrypted` — consistent with
  `CONFIG_FIT_SIGNATURE` unset.
- `image.ub` FIT subimages are dated 2026-05-28 15:53:39, the same timestamp
  as ZCU102 #2's card. Kernel subimage described as "Linux kernel with
  spidev"; FDT subimage as "DTB with spidev.bufsiz=1MB".
- `spi_master spi0: cannot find modalias for /axi/spi@ff0f0000/flash@0` —
  the same QSPI flash-child bind failure seen on #2. Not investigated.

## DELIBERATELY NOT CLAIMED

- That a second `saveenv` produces a clean load. Not attempted.
- That the internal structure of `uboot-redund.env` is two copies. Reading,
  not measurement.
- That the spontaneous reboot has a known cause.
- That SOW 2.g is implemented. It is not. Nothing was built, configured, or
  flashed. `fw_setenv` is still absent.
- That anything was measured about the AXI SPI path. No PL bitstream was
  loaded, no overlay applied, no benchmark run.

## SOW POSITION

Q4 and Q4-prime are both SOW 2.g robustness inputs, measured on hardware.
This is SOW-contracted activity.

2.g remains DESIGN LOST and NOT IMPLEMENTED. 2.f remains NOT STARTED.

## REPRODUCE

On `stile`, with `/dev/ttyUSB0` free (CP2108 serial
`C68E7C4D227B4FA211ED7C38CE7DE91`, `if00`):

```
script -q -c 'picocom -b 115200 --noreset --flow n --lower-rts --lower-dtr /dev/ttyUSB0' <log>
```

Power-cycle ZCU102 #1 and press a key during the ~2 s countdown to reach
`ZynqMP>`. Then:

```
printenv
fatls mmc 0:1
saveenv
fatls mmc 0:1
```

Note: `printenv | wc -l` fails with `syntax error`. U-Boot has no shell and no
pipes. Use bare `printenv`.

The environment on this card is now initialised, so a repeat will NOT
reproduce the `No Valid Environment Area found` first-boot message.
