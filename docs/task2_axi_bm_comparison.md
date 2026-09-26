# MSU-2 Task 2: fresh common AXI SPI experiment, Phase 1

## FACT: scope and provenance

This is software/build preparation, not board validation. Target:
`axi_quad_spi_0`, AXI Quad SPI 3.2, AXI4-Lite base `0xA0000000`, standard SPI,
8-bit words, master, CPOL=0/CPHA=0, MSB first, active-low SS0, 256-entry FIFOs.
The generated standalone driver is `spi` / `XSpi` (available BSP: spi_v4_14).
`XSpiPs` controls a different PS peripheral. Historical PS SPI1 measurements
at approximately 0.976465 MHz cannot establish pure OS overhead against the
Linux PL AXI SPI path. Even matched hardware requires reporting driver policy,
CPU/cache/compiler settings and timing scope when interpreting a difference.

Historical Linux sources, binaries and captures are preserved. They establish
timing/API outcomes but did not verify RX bytes or prove external loopback.
Recorded Linux SPI_LOOP requests were rejected. Fresh RX-verified captures on
one pinned common hardware baseline are required for the definitive comparison.

### Hardware identities

| Input | Identity |
|---|---|
| `hardware/xsa/spi_benchmark_wrapper.xsa` | MD5 `a698a18521c106272480b8ab260e886a`; SHA-256 `42d271dae9a4f4a441190e1a77eba870ee127907a4826f0a1bcc2554b3b3740d` |
| Its embedded `spi_benchmark_wrapper.bit` | SHA-256 `a62cd21ef5a8b8430639018b7cae85a9612f1b93ce33c491ccb0d06642f43534` |
| Historical June bitstream, `sd-images/spi_benchmark_wrapper.bit.bin` | MD5 `61f2c33f6ce6138eee81a862a466ae4e`; SHA-256 `49b80a4a022dc37ceaff856d0a7bace7be259664885298bbd09812a0a1e165ff` |
| Historical Linux FIT overlay `fdt-pl.dtbo` | SHA-256 `2912ee463b2f60652dd64fc8009d1836e8a5c7824008eb26940a753eeb09dfcd` |
| Historical Linux v2 executable | MD5 `ff194b3828edc13d06ba26ef816c8616` |

The XSA was introduced at `90d93f7` (May 26). Its embedded bitstream corresponds
to the older May image introduced at `8006155`, not the June rebuild introduced
at `a472d8b` and used by the August 27 Linux capture. The June file was verified
against the above hash before Phase 1 edits. It must not be altered.

During Phase 1 validation a transient one-byte working-file discrepancy was
observed in the historical June bitstream while Git status still reported no
tracked change. Subsequent `git fsck --full` independently exposed corruption
in the local Git object database: a packed-object inflate failure, broken tree
link, and missing blob for `hardware/dtb/Image-spidev`. `git fetch origin`
restored the missing object; a repeated full fsck then passed with only
unreferenced dangling blobs. The June bitstream was force-restored from HEAD
and both working-file and HEAD MD5 subsequently verified as
`61f2c33f6ce6138eee81a862a466ae4e`. The earlier byte discrepancies therefore
remain unattributed and must not be assigned to Codex, Vitis, or an intentional
external modification. Recheck cryptographic hashes before future hardware
loads; Git status alone is not sufficient provenance. The XSA retained its
pinned SHA-256 throughout.

References: [August session](sessions/SESSION_20260825_MORGAN.md),
[cross-boot evidence](../results/CROSSBOOT_REPRO_20260827.md),
[overlay source](../linux/petalinux/device-tree/spi_benchmark_pl.dts).

### Clock provenance

FACT: XSA HWH annotates PL0 at 99.990005 MHz and C_SCK_RATIO=16. Embedded
`psu_init.c` specifies IOPLL configuration `0x00013C00` and PL0 configuration
`0x01010A00`. Historical Linux readbacks include IOPLL `0x00015A00` and
PL0 `0x01010600`. The established runtime reference is 249.975 MHz, yielding
**configured/derived** SCK 15.6234375 MHz. This is not physically measured SCK.
The hash-matched Linux overlay requests nominal 250 MHz through clock ID 71.

INFERENCE: Linux overlay/clock handling could account for the PL0 setting.
The exact FSBL/firmware/U-Boot/Linux sequence establishing both register values
is not proven. The new application does not write PS clocks. It prints raw
IOPLL and PL0 readbacks only when explicitly armed for execution; it never
interprets them as a pin measurement.

REQUIRED BOARD VALIDATION: reconcile and pin one XSA/bitstream pair; establish
the PS initialization/PL loading/clock procedure in both environments. The
Phase 1 XSA pin is a reproducible software-build input, **not certification of
the future common hardware pair**. No BOOT.BIN packaging is provided.

## Implemented software contract

New files:

- `common/spi_benchmark_contract.h`: shared payloads, pattern, poison, RX check,
  Welford population statistics and CSV fields.
- `bare_metal/src/spi_benchmark_bare_axi.c`: XSpi application.
- `linux/src/spi_benchmark_v3_rxverify.c`: separate spidev application.
- `scripts/build_spi_axi_bm_vitis.py`: isolated, hash-gated Vitis 2025.1 build.
- `tests/test_spi_bench_phase1.py`: host-only mocked transfers and statistics.

Payloads are exactly `1,8,16,64,128,256,512,1024,4096,16384,65536`, with 1000
attempts per payload if the sweep progresses. `tx[i]=i&0xFF`; before **every**
attempt RX is set to `tx[i]^0xFF`, outside timing. Every byte is compared after
full API completion. A mismatch excludes that transfer from timing statistics.
First mismatch trial, offset, expected and actual byte are retained separately
from the first overall error. Trial indices are zero-based.

`timed_success_count` means API success, correct RX and valid timer readings.
`api_success_count` includes completed transfers with incorrect RX. Linux treats
every nonnegative return unequal to payload length as an API error and records
the returned length; `short_return_count` is that non-full-return subset.
`api_error_count` and `rx_mismatch_count` are distinct. Timing errors have their
own count. `first_status` is a native Xilinx status, negative Linux errno, or
a negative harness code (`-10001` RX mismatch, `-10002` non-full return,
`-10003` timer error); `first_failure_kind` disambiguates the namespace.

Statistics are min/mean/max/population standard deviation in ns over the stated
valid samples, using floating-point Welford accumulation. No samples means
all four timing values are `-1`, not zero. `attempt_count=api_success_count +
api_error_count` for completed rows. A hung call produces no completed row and
no sweep-completion record. UART output and RX checks are outside each transfer
interval. The Linux interval includes saving errno immediately after ioctl.

CSV is bracketed by `---CSV-BEGIN---` / `---CSV-END---`; provenance and ancillary
metrics are `#` lines (filter those before CSV ingestion). No output filename is
chosen or overwritten by either program. Preserve complete stdout/stderr in a
new capture file. `topology=UNVERIFIED` is always emitted: a separate board/run
manifest must establish wiring and attach the validation evidence.

Standalone uses `XTime_GetTime` and reports BSP `COUNTS_PER_SECOND`; its
frequency must be checked against the runtime timer configuration. Linux uses
`CLOCK_MONOTONIC_RAW`; it explicitly requests/readbacks mode 0, eight bits,
and requested speed (default 15623438 integer Hz). Speed request/readback is
not achieved SCK. No SPI_LOOP request is made. One message/transfer per attempt,
CS change false, no extra delay. SS continuity and inter-FIFO gaps need tracing.

Linux additionally reports thread CPU ns, wall ns and context switches across
the **whole trial loop**, including buffer preparation and RX verification.
These are not historical v2 transfer-loop CPU measurements and exclude IRQ CPU
cost. Scheduling/affinity are unchanged and memory is not locked; record the
launch environment and apply any desired scheduling policy explicitly to both
the run procedure and provenance. No bare-metal CPU utilization equivalence is
claimed.

### BLOCKER: bounded transfer/recovery

Vendor `XSpi_Transfer` polling contains a TX-empty wait without a deadline.
An outer timer cannot bound it. The default standalone ELF refuses transfers
before controller initialization, returning 2. An explicit build switch
`--allow-unbounded-polling` enables this known-unbounded path only for deliberate
later bring-up. It prints the blocker and `timeout_count=-1` (unavailable).
There is no timeout detection or bounded recovery in this phase. This must be
resolved before unattended definitive sweeps. Do not describe the opt-in ELF
as bounded, or its API success as independent hardware error detection.

Linux counts only returned `ETIMEDOUT` errors as timeouts, a subset of API errors.
It has no userspace deadline that can abort a hung kernel ioctl. A zero timeout
count only means no ETIMEDOUT was returned. Board watchdog/operator abort and
recovery policy remain to be established. Existing driver status alone never
certifies RX correctness.

## Reproducible build and static checks

From the repository root:

```sh
clang -std=c11 -O2 -Wall -Wextra -Werror -Icommon \
  linux/src/spi_benchmark_v3_rxverify.c -lm -o /tmp/spi_benchmark_v3_rxverify
python3 tests/test_spi_bench_phase1.py
python3 scripts/build_spi_axi_bm_vitis.py --timeout-seconds 180
```

For board Linux, use the AMD AArch64 Linux compiler with the same flags and a
new output path; never invoke the historical v2 build script for v3.

The new Vitis script checks version, XSA/embedded-bit hashes, IP parameters,
generated XSpi metadata and sources; creates an A53-0 standalone platform/app;
uses explicit `-O2`, libm and a DDR origin of `0x00100000` while preserving the
DDR upper bound; checks AArch64 ELF entry, LOAD placement and new result symbols.
It writes input/generated/output hashes, compiler identification and logs in
the **new** workspace only. Vitis configuration files are directed there too.
The Vitis process group has a hard timeout (default 180 s, maximum 300 s).
Existing workspaces are refused, never deleted; use a new `--workspace-name
spi_axi_bm_<suffix>` for another attempt. Historical PS workspaces are untouched.
Each run directory contains logs/manifests/configuration alongside a separate
`workspace/` subdirectory, which Vitis initializes itself.

### Phase 1 validation record (2026-09-26)

- Linux compiled with Clang and the AMD AArch64 Linux GCC toolchain using
  `-std=c11 -O2 -Wall -Wextra -Werror`; outputs were placed under `/tmp`.
  Host GCC 11.4 encountered an internal compiler error; that compilation is not
  reported as passing. Clang static analysis reported no findings.
- Python AST parsing and XSA metadata/hash gates passed. Five host-only tests
  passed: injected ioctl/timeout/short-return/RX faults, RX poisoning, no-valid-
  sample sentinels, clean simulated sweep, mode mismatch rejection, and known
  population variance (some tests check multiple properties). None used hardware.
- Vitis 2025.1 build passed in approximately 50 seconds within a 180-second cap.
  ELF placement and symbols, including `XSpi_Transfer`, passed validation.
  Default unbounded-polling opt-in is **false**. No boot image was packaged.
- Successful run directory: `bare_metal/vitis/spi_axi_bm_ws_validated/`.
  `build_manifest.json`, `workspace/generated_hashes.json` and `build.log` retain
  tool/input/output provenance. ELF: `workspace/spi_axi_bm_app/build/spi_axi_bm_app.elf`.
  These generated files are ignored by Git. Earlier isolated failed attempts
  were retained: HOME write failure, nonempty-workspace rejection, and a
  sandboxed startup that was killed at its 180-second limit.

- Hardware reconciliation flow added in `scripts/build_spi_common_hw.tcl`
  (commit `99e7243434db26ea40b43b8812564848d70f7c75`). Vivado 2025.1 now starts
  normally on the Morgan workstation, and the required board part
  `xilinx.com:zcu102:part0:3.4` resolves. The flow creates an isolated project
  from the repository BD/XDC, explicitly pins `xczu9eg-ffvb1156-2-e` and the
  ZCU102 board part, generates the BD/wrapper/HWH, and launches synthesis.
  AXI Quad SPI remains assigned at `0xA0000000 [64K]`.
- The reconciliation build is currently **BLOCKED BY LICENSE INFRASTRUCTURE**,
  not by a demonstrated SPI design failure. All synthesis sub-runs terminate
  with Vivado `[Common 17-345]` reporting no valid `Synthesis` and/or `xczu9eg`
  license. Bypassing DNS with `2100@172.20.3.171` produces the same result.
  TCP port 2100 is reachable, but FlexLM reports `lmgrd` not responding
  correctly. Available local Vivado Enterprise/XCZU9EG licenses are expired.
  Therefore no new implemented `.bit`, reconciled XSA, `.bit.bin`, timing, or
  utilization result is claimed yet.

SHA-256 values for the validated software:

| Input/output | SHA-256 |
|---|---|
| AXI standalone source | `fc3ccb2e752f137357dc819fc3ae4e462630efd8f74041557c5cbc584fd29c9d` |
| Shared contract | `862c78c1a1d8a8ae044ac168410c45da1bf3768044cfc94693d1c068ee6a7534` |
| Build script | `ea32fce908a16a2f865cd5c592097818b04ee51e4e21732b57fd3c8080beea53` |
| Standalone ELF | `366b2dc53d466a18bcca62e645daa1cfa5b3144a3e808d6396d515a3cb91aad2` |
| Linux v3 source | `d6db1f27431e3fdd563ff14527495e28a2d56bf354c1cf66281bf0743cfbf35e` |
| Linux v3 AArch64 executable | `d4e0e6b747789eb44e9013397e8956703ab41d8b78800e18d5586e72e5037c85` |

This is **BUILD/STATIC validation only**, not evidence of SPI functionality.

## REQUIRED BOARD VALIDATION: exact sequence after review

1. Resolve bounded completion/recovery. Reconcile the XSA/bitstream pair and pin
   both hashes plus FSBL/PMUFW/boot recipe, Linux FIT/kernel/overlay and each
   application/compiler/flags. Confirm ELF PL-load behavior explicitly.
2. Record board ID/revision, power/boot method, selected image hashes and exact
   loaded controller mapping. Confirm AXI base `0xA0000000`, FIFO depth 256,
   standard SPI, mode 0, MSB first, eight bits and SS0 in both environments.
3. Before/after PL load and immediately before each sweep, capture IOPLL_CTRL
   (`0xFF5E0020`), PL0_REF_CTRL (`0xFF5E00C0`) and runtime timer frequency.
   Record configured/derived SCK separately from any physical measurement.
4. Inspect the reconciled design's pin assignments, then establish external
   MOSI-to-MISO wiring shared by both environments. The existing XDC lists
   D12/J55-1 MOSI and E10/J55-2 MISO, F11/J55-4 SCK, D11/J55-7 SS0, LVCMOS18;
   verify those assignments against the selected image before connecting.
5. With available instrumentation, measure SCK, CPOL/CPHA, CS assertion across
   the entire transfer, and FIFO-service gaps in both environments. Record
   probe points, instrument settings and traces. Otherwise mark physical SCK
   UNKNOWN; do not substitute throughput or speed readback.
6. Run separate bring-up checks at 1, 8, 256, 512 and 65536 bytes, including an
   intentional RX-path failure to demonstrate mismatch detection. Verify
   bounded abort/recovery with a controlled fault once that mechanism exists.
7. Run all 11 payloads, exactly 1000 attempts each, with the same hardware,
   clock, mode, CS behavior and topology. Linux spidev buffer limit must support
   65536 bytes; record its actual value. Save full new logs and hashes. Require
   1000 verified timing samples per payload and no errors for a clean baseline.
8. Repeat across cold boots. Compare matching transfer-only timing statistics;
   report CPU/cache/scheduling differences separately. Preserve failed runs and
   explain any missing samples. Never retrofit new validation onto old results.

No board experiment or completed hardware regeneration is part of Phase 1. The reconciliation flow has been exercised through BD/IP generation, but implementation remains blocked by the synthesis-license infrastructure.
