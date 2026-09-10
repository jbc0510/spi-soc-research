# Demo Runbook — SOW 2.g Environment Recovery

**MSU-2 Task 2 · ZCU102 · repo `jbc0510/spi-soc-research`, branch `feature/dma-benchmarking`**
Established 2026-09-09. Commits `6908806`, `ac2a9d0`, `8e00c92`, `94d3cfe`.

---

## What this demonstrates

With one of the two U-Boot environment copies deliberately destroyed, the board
still boots and the interactive prompt is still reachable. The SOW language being
satisfied is:

> "Implement an update mechanism that ensures the device remains bootable in the
> event of an interrupted or corrupted software update."

**Runtime:** about 12 minutes including two boots. No PetaLinux build, no
synthesis, no host toolchain.

## What it does *not* demonstrate

Say this out loud during the demo. It is part of the result.

- Nothing about `image.ub`, kernel, or rootfs update robustness. **Environment
  redundancy only.**
- The corruption is authored on the host. It reproduces the on-media *state* of a
  torn write, not the interruption mechanism.
- The Verification leg of 2.g (`CONFIG_FIT_SIGNATURE`) is at zero and is not
  exercised here.
- The rootfs is INITRD and `libubootenv-bin` is not provisioned into it, so this
  is a demonstration, not a deployable appliance.

---

## The one idea to land

**A successful boot proves nothing.** A board with *no* environment files at all
also reaches a Linux login prompt — observed 2026-09-08. So "it booted" cannot
distinguish recovery from total environment loss.

The discriminator is a variable that exists in **only one copy**:

| observation | conclusion |
|---|---|
| `msu2_probe` **absent** | did not read the corrupted copy |
| `msu2_marker` **present** | did not fall back to compiled-in defaults |

Both together identify the surviving copy uniquely. `msu2_marker` is the positive
control — without it, absence alone would be consistent with the environment
having been lost entirely.

---

## Before you start

| requirement | check |
|---|---|
| Board | ZCU102, SD boot mode, console on the host |
| Host | any Linux box with an SD reader and a clone of the repo |
| Card state | two valid environment copies (see §5 to confirm or restore) |
| Console | `picocom` at 115200 |

**Card state after the 2026-09-09 session:** two valid copies, redundant active at
flag `05`, `msu2_probe` present in the redundant copy only. The demo is ready to
run as-is. Verify with §5 step 1 before presenting.

---

## 1 · Confirm the starting state (host, 2 min)

Insert the card. Identify it by differential, not assumption:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT     # before insertion
# insert card, wait 3 s
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT     # the new device is the card
```

The partition auto-mounts read-write. Make it read-only before touching anything —
vfat records a last-access date, so even a read can dirty the filesystem:

```bash
sudo mount -o remount,ro /media/$USER/BOOT
mount | grep BOOT                                    # GATE: options contain "ro,"
md5sum /media/$USER/BOOT/uboot.env /media/$USER/BOOT/uboot-redund.env
```

**GATE — expected healthy state:**

```
0b7781c0e30f35aa2d86e1da8e29d348  uboot.env          flag 04
8ad2c8af53b17db79433bfb92dd01410  uboot-redund.env   flag 05  ACTIVE
```

If either differs, go to §5 and restore before continuing.

## 2 · Corrupt one copy (host, 1 min)

This is the step the audience should watch. Target the **active** copy so the
fallback is a real fallback rather than U-Boot ignoring a copy it wasn't going to
read anyway.

```bash
sudo mount -o remount,rw /media/$USER/BOOT
mount | grep BOOT                                    # GATE: options contain "rw,"

sudo dd if=/dev/urandom of=/media/$USER/BOOT/uboot-redund.env \
        bs=1 seek=4096 count=512 conv=notrunc status=none
sync
```

`conv=notrunc` with byte-granular `seek`/`count` overwrites 512 bytes at offset
4096 and touches nothing else. Show that the fault is narrow:

```bash
ls -l /media/$USER/BOOT/uboot-redund.env             # still 262144 bytes
md5sum /media/$USER/BOOT/uboot-redund.env            # changed
```

What is still intact, and why it matters: **size, filename, the stored CRC at
offset 0, and the flag byte at offset 4.** U-Boot will therefore read this copy,
believe it is the newer one (`05` > `04`), compute the CRC, and find it wrong.
That is a torn write. A deleted file is a different code path and tests something
else.

Optional — prove the CRC is broken before booting. **Note:** the parser used on
2026-09-09 was written to `/tmp/parse_env.py` and is *not yet committed*; commit it
to `scripts/` before relying on this step in a demo:

```bash
python3 scripts/parse_env.py /media/$USER/BOOT/uboot-redund.env
# expect: NO LAYOUT MATCHED  (crc32 mismatch at both candidate offsets)
```

Unmount and move the card to the board:

```bash
sudo umount /media/$USER/BOOT
lsblk | grep BOOT                                    # GATE: no mountpoint
```

## 3 · Boot with the fault in place (5 min)

**Console first, then power on.** Starting picocom after power-on loses the U-Boot
output, which is the evidence.

```bash
script -q -c 'picocom -b 115200 --noreset --flow n --lower-rts --lower-dtr /dev/ttyUSB0' \
       ~/logs/demo_2g_$(date +%Y%m%d).log
```

Power on the board. Watch for:

```
Loading Environment from FAT... OK
Hit any key to stop autoboot:  5
```

**Press any key inside the five-second window.** You will get `ZynqMP>`.

> `bootdelay=5` is a deliberate test fixture on this card. The board's stock
> autoboot delay is zero, which the project record flagged as "works, but not a
> repeatable demo procedure." The fixture is what makes the prompt reachable on
> cue, and it is present in **both** copies so the prompt survives either way.

Now the two reads. One command per paste — multi-line pastes have raced on this
console before.

```
printenv msu2_probe
```
```
printenv msu2_marker
```

**Expected:**

```
ZynqMP> printenv msu2_probe
## Error: "msu2_probe" not defined
ZynqMP> printenv msu2_marker
msu2_marker=uboot_20260908
```

### The point to make here

Scroll back to the environment-load line and read it aloud:

```
Loading Environment from FAT... OK
```

That is **byte-for-byte what a healthy boot prints.** One of two copies is
destroyed and the console says nothing. Three states, for contrast:

| card state | U-Boot prints |
|---|---|
| both copies valid | `Loading Environment from FAT... OK` |
| **one copy corrupt** | **`Loading Environment from FAT... OK`** |
| no environment at all | `*** Error - No Valid Environment Area found` |

Recovery is transparent, which is the desired behaviour. But a deployed appliance
would continue with **zero remaining redundancy**, report nothing, and never
repair itself — and the next corruption is unrecoverable. Hence the
recommendation: periodic active verification of both copies plus an explicit
repair path.

## 4 · Show that U-Boot did not self-heal (host, 2 min)

Power off **at the switch.** Do not use `poweroff` at the U-Boot prompt — on this
board it drops back into FSBL rather than powering down, which gives U-Boot
another pass at the environment before you have measured it.

Card to the host, remount read-only, re-hash:

```bash
sudo mount -o remount,ro /media/$USER/BOOT
md5sum /media/$USER/BOOT/uboot.env /media/$USER/BOOT/uboot-redund.env
```

**Both hashes are unchanged from §2.** Not one byte moved. U-Boot does not write
during environment load, so the broken copy stays broken until something
explicitly repairs it.

## 5 · Restore (host, 2 min)

Restore out of the **git object store**, not the working tree — that catches a
corrupt blob before it propagates.

```bash
cd ~/msu2-verify/spi-soc-research
git show HEAD:artifacts/2g-fwenv/env-snapshots/uboot-redund.env.armed-20260909 \
  > /tmp/restore-redund.env
md5sum /tmp/restore-redund.env      # GATE: 8ad2c8af53b17db79433bfb92dd01410
ls -l  /tmp/restore-redund.env      # GATE: 262144 bytes
```

Only if both gates pass:

```bash
sudo mount -o remount,rw /media/$USER/BOOT
sudo cp /tmp/restore-redund.env /media/$USER/BOOT/uboot-redund.env
sync
md5sum /media/$USER/BOOT/uboot.env /media/$USER/BOOT/uboot-redund.env
```

**GATE:** `0b7781c0…` and `8ad2c8af…`.

To close the loop in front of the audience, boot once more and re-read:

```
printenv msu2_probe
```

Expected: **`msu2_probe=probe_20260909`**. Same board, same card, same U-Boot
binary — one variable flipped by the state of one file. That reciprocal is what
makes the discriminator a measurement rather than a single observation.

---

## Optional: the Linux-side half (adds ~10 min)

Only if asked. Shows that the environment is writable from Linux as well as from
U-Boot, which is the 2026-09-08 result (`42b6616`).

The rootfs is **INITRD** — `/tmp` and `/etc` reset on every power cycle, so this
has to be rebuilt each boot.

```
date -u -s "YYYY-MM-DD HH:MM:00"
```

> **Substitute the real digits before sending.** A command containing a
> placeholder character has been sent literally twice on this project; `date`
> rejects it, and anything following it then operates on the wrong clock. The
> cold RTC reads **1970**; systemd advances it to the image build date
> (2025-01-08). Skip `hwclock -w -u` — the write is accepted and lost on the next
> power cycle.

```
mkdir -p /tmp/fw && cp /run/media/BOOT-mmcblk0p1/{fw_printenv,libubootenv.so.0.3.5,libyaml.so.0.2.5} /tmp/fw/
```
```
md5sum /tmp/fw/*
```

**GATE — all three, and all three matter.** Checking only the executable's
`DT_NEEDED` rather than the full transitive closure cost this project two physical
card transfers:

```
02f2e6c32aaa44ee71577a4bece1c647  fw_printenv
28309c4d1f0ca05dd450f217809084cd  libubootenv.so.0.3.5
b88998efa5cbb661de1ae90a16ee57f5  libyaml.so.0.2.5
```

```
chmod 755 /tmp/fw/fw_printenv /tmp/fw/libubootenv.so.0.3.5 /tmp/fw/libyaml.so.0.2.5
```
```
ln -sf /tmp/fw/fw_printenv /tmp/fw/fw_setenv
```
```
ln -sf /tmp/fw/libubootenv.so.0.3.5 /tmp/fw/libubootenv.so.0
```
```
ln -sf /tmp/fw/libyaml.so.0.2.5 /tmp/fw/libyaml.so.0.2
```
```
printf '/run/media/BOOT-mmcblk0p1/uboot.env 0x0 0x40000\n/run/media/BOOT-mmcblk0p1/uboot-redund.env 0x0 0x40000\n' > /etc/fw_env.config
```
```
LD_LIBRARY_PATH=/tmp/fw /tmp/fw/fw_printenv | wc -l
```

**GATE: 77.** The count is diagnostic, not decoration — it tells you which copy
libubootenv selected. Two valid copies with `msu2_probe` in the redundant one give
77; reading the primary would give 76.

### Two traps if you write from Linux during a demo

1. **`fw_setenv` returning success is not evidence that a write occurred.**
   libubootenv skips a write whose value already matches and does not touch the
   media at all. Confirm by hash, never by exit status.
2. **A write destroys the discriminator.** Every `fw_setenv` copies the *full*
   active variable set to the other copy, so `msu2_probe` would end up in both.
   **A discriminator survives exactly one write cycle.** If you write anything
   from Linux, re-arm with a *fresh* variable name before running §2 again.

---

## Troubleshooting

| symptom | cause | action |
|---|---|---|
| No autoboot countdown, boots straight through | `bootdelay` not 5 in the copy in force | Card is not in the demo state. Restore per §5 |
| `printenv msu2_probe` returns a value during §3 | Corruption didn't take, or the wrong copy was hit | Re-check §2 hashes; confirm you targeted `uboot-redund.env` |
| `*** Error - No Valid Environment Area found` | **Both** copies invalid | Restore both from `env-snapshots/*armed-20260909` |
| `msu2_marker` also undefined | Running on compiled-in defaults, not a fallback | Negative result — say so; do not present it as a pass |
| Console log is empty or truncated | `script` block-buffers | Exit picocom (`Ctrl-A Ctrl-Q`) to flush before reading the log |
| `fw_printenv` fails on `libyaml.so.0.2` | Missing library or symlink | Re-do the three `ln -sf` lines; check all three md5s |

---

## Artifacts this demo depends on

All committed; nothing needs rebuilding.

```
artifacts/2g-fwenv/
  fw_printenv                              02f2e6c32aaa44ee71577a4bece1c647
  libubootenv.so.0.3.5                     28309c4d1f0ca05dd450f217809084cd
  libyaml.so.0.2.5                         b88998efa5cbb661de1ae90a16ee57f5
  fw_env.config                            1a48e1725e401fde09584a255af4fb22
  zcu102-2_2g_baseline_boot_20260909.log   4d84b519d6376fb72ec91682079574ad
  zcu102-2_2g_corrupt_20260909.log         f63039848dcf60884a37b10a8844e91a
  zcu102-2_2g_restore_20260909.log         8d59d175262a34f02b881832796b7c7a
  env-snapshots/
    uboot.env.armed-20260909               0b7781c0e30f35aa2d86e1da8e29d348
    uboot-redund.env.armed-20260909        8ad2c8af53b17db79433bfb92dd01410   <- restore source
    uboot-redund.env.corrupted-20260909    38b7167b8d48c5bd52342c80790ef49b
    uboot.env.postboot-20260909            0b7781c0e30f35aa2d86e1da8e29d348
    uboot-redund.env.postboot-20260909     38b7167b8d48c5bd52342c80790ef49b

results/SOW_2G_RECOVERY_20260909.md        41ae624e176a636c18cea3fc4efc822a
results/SESSION_RECAP_20260909.md          8821d0394f6e806923b4acd39f122ea0
```

Environment on-media layout, established by CRC rather than assumed
(`crc32(b[5:])` matched the stored value in both copies; `crc32(b[4:])` matched
neither):

```
offset 0..3   crc32, little-endian
offset 4      redundancy flag byte
offset 5..    NUL-separated name=value payload
total         262144 bytes (0x40000) per copy
```

The flag byte is a **global counter, not a per-file increment**: each `fw_setenv`
targets the inactive copy and stamps it `active_flag + 1`. That is why the primary
moved `02 → 04`, skipping `03`.
