# Operator validation of clock_candidate_v4

Status: ALL FIVE MENU CHOICES OPERATOR VALIDATED. Source/build commit: 32a2da9.
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
| 3 full baseline | PASS: all 33 points, 11 shared sizes x 60 seconds x 3 repetitions. All attempts verified, zero API errors, zero mismatches, first_error_code=0 throughout. Completion marker and post-test Enter prompt observed. |
| q return to Linux | PASS on v4: after the requested q test, operator supplied Linux boot output through PetaLinux 2025.1 newQspi ttyPS0 and newQspi login:. SD FAT mount and Multi-User System reached. No additional U-Boot command was reported for this test. |

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

## Option 3 completed observation

Operator selected all 11 sizes, 60 seconds per point, 3 repetitions and pasted
all 33 CSV rows and human-readable summaries. Every point completed with
attempts=verified_transfers, api_errors=0, mismatches=0, first_error_code=0.
Completion: sustained_sweep_complete=1, followed by "Sustained benchmark
complete: no errors." and the post-test Enter prompt. Selected CSV fields
are preserved in baseline_observed.csv; these are extracted from operator
output, not a direct serial-port capture. Physical SCK remains unmeasured.

## Return-to-Linux observation and acceptance

After the completed baseline, the operator was instructed to press Enter,
select q without Enter, and leave U-Boot autoboot uninterrupted. The operator
then supplied Linux kernel and systemd output ending in:

```
PetaLinux 2025.1+release-S05180137 newQspi ttyPS0
newQspi login:
```

The supplied excerpt shows the resulting Linux boot, not the q keystroke or
PSCI instruction itself. It includes FIT SHA-256 verification, kernel startup,
Multi-User System, and SD FAT mount at /run/media/BOOT-mmcblk0p1. No manual
boot command was reported for this final test.

All five requested menu options have now been individually exercised by the
operator on the identified ELF. All observed transfer tests completed without
hangs, and integrity/custom sustained/full baseline had zero RX mismatches.
This establishes the requested menu acceptance on this setup; it is not an
exhaustive fault-injection proof for every possible hardware or input fault.

Preserve the tested ELF and card backups; BOOT.BIN and
boot.scr were not changed by these candidates. The firmware's generic
NOT_PERFORMED/UNVERIFIED banners are conservative build-time labels; this
document records the actual operator observations for the identified ELF.
