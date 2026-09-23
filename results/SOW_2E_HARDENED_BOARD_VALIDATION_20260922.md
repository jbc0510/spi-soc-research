# SOW 2.e — Hardened Bare-Metal SPI Board Validation, ZCU102

**Validation date:** 2026-09-22
**Repository branch:** `feature/dma-benchmarking`
**Source commit:** `aafb286f93e2e37e0f398815b522db0bdd91eda9`
**Source commit subject:** `2.e: automate reproducible Vitis bare-metal build`
**Board:** ZCU102
**Execution path:** SD boot, Vitis 2025.1 standalone / bare-metal

## Scope

This report records physical-board validation of the hardened SOW 2.e
bare-metal SPI benchmark image on the ZCU102.

The purpose of this run was to confirm that the reproducibly built benchmark
image:

- boots successfully from SD,
- initializes PS SPI1 successfully,
- completes all 11 configured payload sizes,
- completes 1000 successful transfers per payload,
- reports no transfer-status failures,
- produces UART timing output that agrees with an independent JTAG memory
  readback of the result structures.

This validation is intentionally limited to the evidence actually captured.
It does not claim RX payload correctness, externally measured SCK frequency,
or Linux-versus-bare-metal equivalence.

## Artifact provenance

Validated source commit:

    aafb286f93e2e37e0f398815b522db0bdd91eda9
    2.e: automate reproducible Vitis bare-metal build

Reproducible application ELF:

    bare_metal/vitis/spi_bm_repro_package/spi_bm_app_2e_hardened.elf
    MD5: 78df6d79b9ffd2d4c631f058602e4216

Board-executed boot image:

    sd-images/baremetal/BOOT_2e_hardened.bin
    MD5: cf11cd76850ee1044a50e23f949e6977

The prior Linux SD-card boot image was preserved on the card before the
bare-metal image was installed:

    BOOT_linux_pre_2e_a25d6549.bin
    MD5: a25d65490a95eed09632ff3af97eb42b

The Linux image was not restored as part of this validation report.

## Raw evidence

Complete UART capture:

    docs/environment/zcu102-2_2e_hardened_boot_20260922_full.log
    SHA-256: 20942ecb75b2710dc51d299b085266c3704e9b03c8ef5356c922f44e18b33e73

JTAG memory readback:

    docs/environment/zcu102-2_2e_hardened_jtag_20260922.log
    SHA-256: 0b06c0d5797d27cc3836f956076f4e5341e8de8fe8e0717714912b9828e3f165

An earlier three-minute UART capture was incomplete. It stopped after the
4096-byte timing row and contained neither the complete payload ladder nor
the CSV completion block. It was intentionally removed from the repository
working set rather than retained as final validation evidence.

Its recorded SHA-256 before removal was:

    03f2b9e7a3c03cb44dfb42bb082a4bd62d73187ed69b56e656303d5ccf4ce745

No historical tracked artifact was overwritten.

## Boot and initialization evidence

The complete UART log records:

- Zynq MP First Stage Boot Loader, release 2025.1.
- `SPI1_REF_CTRL before: 0x01001800`.
- `SPI1_REF_CTRL after : 0x01001800`.
- `SPI1 init + selftest OK. Prescaler=/64.`
- benchmark banner reporting `PS SPI1 @ 0.9766 MHz (62.5MHz/64), timing-only`.
- all 11 payload sizes.
- a complete sentinel-bracketed CSV block.
- final line `Benchmark complete.`

## UART benchmark results

| bytes | avg_ns | stddev_ns | ok_count | err_count | first_status |
|---:|---:|---:|---:|---:|---:|
| 1 | 10,295 | 77 | 1000 | 0 | 0 |
| 8 | 69,483 | 38 | 1000 | 0 | 0 |
| 16 | 137,179 | 51 | 1000 | 0 | 0 |
| 64 | 543,292 | 60 | 1000 | 0 | 0 |
| 128 | 1,084,783 | 63 | 1000 | 0 | 0 |
| 256 | 2,168,223 | 89 | 1000 | 0 | 0 |
| 512 | 4,335,050 | 123 | 1000 | 0 | 0 |
| 1024 | 8,668,739 | 183 | 1000 | 0 | 0 |
| 4096 | 34,670,813 | 352 | 1000 | 0 | 0 |
| 16384 | 138,679,156 | 683 | 1000 | 0 | 0 |
| 65536 | 554,713,109 | 1499 | 1000 | 0 | 0 |

Across all 11 payload sizes:

- `ok_count = 1000`,
- `err_count = 0`,
- `first_status = 0`.

Thus the benchmark recorded 11,000 successful transfer calls and no reported
driver-status failures.

## JTAG readback evidence

ELF-derived symbol addresses:

    results      = 0x10e178
    g_done       = 0x10e2d8
    ok_count     = 0x12e338
    err_count    = 0x12e368
    first_status = 0x12e398

The `results[]` ABI contains 11 entries, each 32 bytes:

    { min_ns, max_ns, avg_ns, stddev_ns }

with each field represented as a little-endian `u64`.

The completion sentinel read through JTAG was:

    g_done = 0x0000D09E

JTAG also captured all 88 words of `results[]`, eleven `ok_count` values of
1000, eleven zero `err_count` values, and eleven zero `first_status` values.

## UART-to-JTAG cross-check

A programmatic parser independently decoded the complete UART CSV and JTAG
memory dump.

For all 11 payload sizes:

- UART `avg_ns` matched JTAG `results[].avg_ns`,
- UART `stddev_ns` matched JTAG `results[].stddev_ns`,
- UART `ok_count` matched JTAG `ok_count[]`,
- UART `err_count` matched JTAG `err_count[]`,
- UART `first_status` matched JTAG `first_status[]`.

It also verified:

    g_done == 0x0000D09E
    UART contains "Benchmark complete."

Programmatic result:

    CROSS-CHECK: PASS

## Validation result

The hardened SOW 2.e bare-metal image is validated on the tested ZCU102 for
the following claims:

1. The SD-boot image boots successfully.
2. SPI1 initialization and self-test report success.
3. All 11 configured payload sizes complete.
4. Every payload records 1000 successful transfer calls.
5. No transfer call records a nonzero error count.
6. No payload records a nonzero first failure status.
7. UART timing results agree with the JTAG-resident result data.
8. `g_done = 0x0000D09E` confirms the benchmark populated the JTAG result
   table before readback.

## Limitations and deliberately unclaimed results

### RX data was captured but not validated

This benchmark does not establish end-to-end receive-data correctness.
A successful transfer status is not equivalent to proving that every received
byte matches an expected payload pattern.

Therefore this report does **not** claim SPI loopback or peripheral data
integrity.

### No physical SCK measurement exists

The software reports a nominal SPI1 rate of 0.9766 MHz based on the configured
reference clock and prescaler, and `SPI1_REF_CTRL` readback was captured.

No oscilloscope, logic-analyzer, or ILA measurement of physical SCK was made.

### Results are timing-only

The timing values describe software-observed transfer-call duration. They are
not direct wire-level measurements.

### No Linux-versus-bare-metal apples-to-apples claim

Linux and bare-metal runs differ in software stack, execution environment,
timing source, system activity, and potentially clock/control conditions.

These results must not be presented as an apples-to-apples quantitative
Linux-versus-bare-metal comparison without a separately controlled method.

### Other exclusions

- No DMA result is validated by this report.
- No signal-integrity margin is established.
- No maximum sustainable SCK frequency is established.
- No payload corruption threshold is established.
- No temperature sensitivity was evaluated.
- No repeated-board population study was performed.

## Disposition

The complete UART and JTAG logs listed above are the intended raw artifacts
for this validation.

The incomplete three-minute UART capture was intentionally excluded because it
was superseded by the complete run and could be mistaken for final evidence.

The SD card remains configured with the hardened bare-metal `BOOT.BIN`.
Restoration of the backed-up Linux `BOOT.BIN` is a separate explicit action.
