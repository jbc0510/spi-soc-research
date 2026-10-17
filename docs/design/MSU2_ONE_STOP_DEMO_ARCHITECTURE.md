# MSU-2 one-stop board demo — initial architecture

**Status:** The Linux operator menu is validated on the ZCU102 after PetaLinux login. Bare-metal menu parity builds against the validated XSA. A post-login Linux/bare-metal selector, reboot handoff, return path, and bare-metal hardware validation remain open. This demo is not secure boot.\
**Board:** ZCU102\
**Validated PL image:** September 29 ratio-2 J55 design, SHA-256 `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`

## Goal

Give an operator one entry point to select the demonstration, set supported test parameters, run it on the ZCU102, and save results. The operator should not have to replace `BOOT.BIN` or manually type separate commands for every test.

The FPGA image stays fixed for this demo. Switching between Linux and bare-metal still requires a processor reboot because they are separate A53 software environments; it must not require changing the FPGA image or removing the SD card.

## What the repository has today

- Linux uses a PetaLinux `BOOT.BIN` plus `image.ub`; Linux test programs use `/dev/spidev1.0`.
- Bare-metal currently uses a separate `BOOT.BIN` containing FSBL, PMUFW, the validated PL bitstream, and one A53 benchmark ELF. It boots straight into that ELF.
- The Linux sustained runner and new bare-metal menu accept operator-selected shared payloads and bounded run parameters. The bare-metal menu also exposes the common integrity sweep and original full baseline.
- The AXI Quad SPI design is `C_SCK_RATIO=2`; the Linux driver accepts speed requests but does not change that synthesized divider. A requested speed is therefore not a physical clock control.
- The validated application path is external J55 MOSI-to-MISO loopback. The current project has no specified production SPI workload to call “normal operation.”

The current separate boot images explain why replacing the SD-card `BOOT.BIN` appears to be required. The demo needs a boot-flow change and parameter handling, not a different FPGA design.

## Proposed operator experience

Boot the existing Linux image normally. After login, one command opens a top-level choice between Linux and bare-metal test menus. Test selection is always explicit; no long run starts at boot. Selecting bare metal requests a one-shot reboot into the standalone A53 test program. Exiting it returns to the existing Linux default. Both backends use the same validated PL bitstream. Preserve the current Linux default and all known-good backups. No replacement BOOT.BIN is part of this menu implementation.

**Separate security work:** The development menu and one-shot handoff are not secure boot. Authentication of Linux, U-Boot, the selector, and the bare-metal payload belongs to the separate Task 2g secure-boot workstream. No signature or tamper-resistance claim should be made for this operator menu.

FIT verification by U-Boot is not sufficient by itself: the earlier chain must authenticate U-Boot and its required-key control DTB. On ZynqMP that trust chain begins with BootROM authenticating FSBL using the configured device root of trust. The existing project has a signed-FIT host prototype, but no evidence that the live U-Boot/FSBL chain is hardware-rooted. Do not call the menu secure or deploy it as a secure-boot solution until the complete chain is validated. Keep development FIT-signing keys separate from production keys, and do not program eFUSE/BBRAM trust material as part of this software-only prototype.

The post-login launcher should offer:

1. **Normal run / loopback check** — one or a small configured number of transfers with a visible pass/fail result.
2. **Integrity and latency sweep** — selected payloads and trial count, using the existing shared payload pattern and receive-byte comparison.
3. **Sustained throughput** — selected payloads, window length, and repetitions.
4. **Payload stress** — a bounded payload ladder up to the configured spidev transfer limit; stop at the first API failure, timeout, or receive mismatch and save that boundary.
5. **Backend selection** — Linux tests stay in the current session. Bare-metal selection records a one-shot request and reboots to the standalone test menu. That menu returns to the Linux default on exit. A comparison can then run the same test parameters in each backend and label reboot intervals in the result manifest.
6. **System information** — report bitstream hash, kernel/BSP identity, PL0/controller clock, CPU operating point, SPI mode, and measured physical SCK when a scope/logic analyzer reading is available.

The bare-metal ELF should present a serial menu and use the same payload list, transfer checks, and result schema as the Linux runner. Its initial defaults should exactly match the existing baseline. Parameters should be range-checked and echoed before a run; cancellation must be available before starting a long test.

## Parameter contract

Each run should save a machine-readable configuration with:

```json
{
  "test": "sustained",
  "payload_bytes": [1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536],
  "window_seconds": 60,
  "repetitions": 3,
  "stop_on_first_error": true,
  "spi_mode": 0,
  "bits_per_word": 8,
  "requested_sck_hz": null
}
```

`requested_sck_hz` is deliberately null for the validated ratio-2 image: Linux speed requests do not change the fixed hardware divider. Report PL0 rate and physical SCK as separate fields. Clock sweeps require an explicitly selected and identified hardware clock configuration; they cannot be implemented by changing a spidev speed argument. A physical SCK measurement remains separate evidence.

## Execution and evidence model

- Keep Linux as the default boot and operator shell.
- Keep both Linux and bare-metal payloads on the same SD card with immutable names and recorded hashes.
- Use a one-shot mode request to choose Linux or bare-metal, then return to the unchanged Linux default after a bare-metal leg. Verify the selector and both reboot paths on a test card before changing the working card. This development path is not a secure-boot validation.
- Store run configuration, raw console output, CSV, start/end timestamps, software/image hashes, and clock/CPU context under a unique run ID. The Linux menu can write this to storage; bare-metal evidence is currently captured from UART and needs a matching host collector. Do not silently overwrite previous results.
- For the physical demo, capture both UART output and the evidence directory. A run should be resumable or visibly cancellable; it should never silently begin a 33-minute run on boot.
- Keep the separate Task 2g secure-boot workstream distinct. The development operator menu does not claim image authentication or tamper resistance.

## Host-side integration result (17 October 2026)

`scripts/task2g_signed_selector_sandbox_test.py` now demonstrates a single required-key FIT with two configurations: Linux and a standalone SPI-test program. U-Boot sandbox accepted the signed Linux selection, loaded the signed standalone selection with execution disabled, and rejected the standalone selection after its payload was modified. Logs and hashes are in `results/task2g_signed_selector_sandbox_20261017/`.

This sandbox result is separate from the requested post-login selector and its one-shot handoff. The live SD image still uses separate Linux and bare-metal paths; see `results/MSU2_ONE_STOP_SIGNED_SELECTOR_AND_SD_AUDIT_20261017.md` for the independent security audit. Secure boot remains a separate unverified objective.

## Linux menu board validation (17 October 2026)

The no-Python shell menu was installed on the SD boot partition and run on the
ZCU102. It offered explicit Linux actions for PL bring-up, one-byte loopback,
the 11-size integrity/latency sweep, parameterized sustained throughput,
system information, and return to the ordinary Linux shell. Bring-up checked
the known bitstream file hash, set PL0 to 99.99 MHz, released PL reset, created
`/dev/spidev1.0`, and the smoke returned TX `0xa5` / RX `0xa5`.

The menu-driven integrity sweep passed 11,000 transfers with no API errors,
short returns, timeout errors, or receive mismatches. A separate short sustained
demonstration passed 55,937 transfers across 256 B, 4 KiB and 64 KiB payloads
with zero API errors or mismatches. The operator chose all parameters and
explicitly confirmed `RUN`; option `q` returned to the regular PetaLinux shell.
The program labels external topology and physical SCK unverified. This validates
the Linux-side operator workflow and transfer path; it does not validate the
pre-OS chooser, bare-metal selection, measured pin frequency, long-run
repeatability, or secure boot. Raw logs remain on the SD card until archived on
the host. Full run details are in
`results/MSU2_ONE_STOP_LINUX_DEMO_PROGRESS_20261017.md`.

## Open decisions and limits

- “Normal operation” needs a concrete SPI workload from the project owner. Until then, the defensible demo label is “J55 loopback / SPI transfer,” not a claimed end-product operating mode.
- Linux and bare-metal cannot execute concurrently on the A53. The menu must reboot for a mode switch, then return to Linux after the bare-metal selection.
- The integrated post-login mode selector and reboot path have not been assembled or tested.
- The current spidev buffer is 1 MiB, but the AXI SPI driver's maximum transfer behavior above the shared 65,536-byte benchmark payload has not been validated. The stress runner must probe this safely and stop on first failure.
- A physical instrument must be used to confirm SCK during the final demo if the result claims an actual clock frequency.

## Implementation sequence

1. Keep the read-only card backup `results/sd_card_host_backup_20261017/` unchanged; its contents match the source partition byte-for-byte.
2. Implement a Linux-launched top-level mode menu and one-shot bare-metal request while retaining the existing Linux BOOT.BIN as the default.
3. Select a supported U-Boot handoff mechanism, package the bare-metal ELF as a separately named payload, and prove that exit returns to Linux. This will require boot-flow and SD-card file changes, but not replacing BOOT.BIN.
4. Prepare a separate candidate SD card from the preserved backup; validate both modes, cancellation, reboot/return, result persistence, and identical PL bitstream on the ZCU102.
5. Treat Task 2g signature enforcement and hardware root of trust as a separate future validation. Do not label this demo secure boot.

This proposal makes the operator workflow one-stop while keeping the Linux-versus-bare-metal distinction explicit and preserving the same FPGA design across both modes.
