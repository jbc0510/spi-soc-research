# Operator validation of clock_candidate_v4

Status: IN PROGRESS. Source/build commit: 32a2da9.
ELF SHA-256: 53c9e5f07946c6f97bf6dec79068cef3d70aafe3967604f248363391230f3ab0.
This document summarizes UART output pasted by the operator in the Codex
session on 2026-10-30. It is not a raw UART capture or an independent agent
measurement. External physical MOSI-to-MISO loopback is the operator's stated
test topology; internal loopback remains disabled in the firmware.

## Confirmed completed menu options

| Option | Observed result |
| --- | --- |
| 1 integrity | PASS: all 11 shared sizes, 1,000 trials each, 11,000 timed/verified successes, zero API errors, timeouts, RX mismatches, short returns or timer errors. Completion summary: failures=0. Returned to menu. |
| 2 custom sustained | PASS: sizes 1,8,16,256,512,65536; 1 second each, 1 repetition. Zero errors/mismatches at every point; completion marker and return to menu observed. |
| 4 one-byte smoke | PASS: 452,444 verified transfers in 1.000000830 seconds; zero errors/mismatches; completion marker and return to menu observed. TX byte is zero under the shared contract; nonzero/multi-byte integrity is established by option 1. |
| 3 full baseline | IN PROGRESS: see below. |
| q return to Linux | PENDING on v4. Earlier v3 q reset reached U-Boot and operator resumed boot manually; that does not establish unattended return to Linux on v4. |

## Clock and RX evidence

Before v4 initialization: IOPLL_CTRL=0x00015a00, PL0_REF_CTRL=0x01010600.
Restore diagnostic: before=0x01010600 target=0x01010f00 readback=0x01010f00.
First eight-byte transfer: status=0 completed=8,
TX=0001020304050607 RX=0001020304050607, idle CR=0x00000186 SR=0x00000025.
Subsequent tests observed before/target/readback all equal 0x01010f00.
SPI remained mode 0, 8 bits, MSB first. Physical SCK was not measured.

V3 at divider 6 had RX=0000810182028303 for the same TX. Restoring the
Linux-observed divider 15 in v4 resolved the observed integrity failure.
FIFO batching also allowed all payloads to complete. No firmware RX shifting
or internal loopback was used to obtain matching data.

## Option 2 observed counts

| Payload bytes | Verified transfers | Window seconds | API errors | Mismatches |
| --- | --- | --- | --- | --- |
| 1 | 452444 | 1.000000940 | 0 | 0 |
| 8 | 124493 | 1.000004770 | 0 | 0 |
| 16 | 68152 | 1.000013441 | 0 | 0 |
| 256 | 4638 | 1.000116032 | 0 | 0 |
| 512 | 2322 | 1.000085389 | 0 | 0 |
| 65536 | 19 | 1.046224250 | 0 | 0 |

All attempts equaled verified transfers at each point.

## Option 3 partial observation

Operator selected all 11 sizes, 60 seconds per point, 3 repetitions.
Repetition 1 completed all sizes with zero errors/mismatches. Repetition 2
completed 1,8,16,64,128,256,512 bytes with zero errors/mismatches. The latest
received output stops after repetition 2, 512 bytes; no final completion
marker has been supplied. Do not describe the baseline as complete yet.

## Remaining acceptance

Receive the rest of option 3 including its completion marker and menu return.
Then select q and observe an unattended Linux login prompt, without stopping
U-Boot autoboot. Preserve the tested ELF and card backups; BOOT.BIN and
boot.scr were not changed by these candidates. The firmware's generic
NOT_PERFORMED/UNVERIFIED banners are conservative build-time labels; this
document records the actual operator observations for the identified ELF.
