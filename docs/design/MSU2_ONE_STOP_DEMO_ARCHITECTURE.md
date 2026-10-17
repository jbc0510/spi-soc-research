# MSU-2 one-stop board demo — initial architecture

**Status:** design proposal, not yet implemented or board-validated\
**Board:** ZCU102\
**Validated PL image:** September 29 ratio-2 J55 design, SHA-256 `c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd`

## Goal

Give an operator one entry point to select the demonstration, set supported test parameters, run it on the ZCU102, and save results. The operator should not have to replace `BOOT.BIN` or manually type separate commands for every test.

The FPGA image stays fixed for this demo. Switching between Linux and bare-metal still requires a processor reboot because they are separate A53 software environments; it must not require changing the FPGA image or removing the SD card.

## What the repository has today

- Linux uses a PetaLinux `BOOT.BIN` plus `image.ub`; Linux test programs use `/dev/spidev1.0`.
- Bare-metal currently uses a separate `BOOT.BIN` containing FSBL, PMUFW, the validated PL bitstream, and one A53 benchmark ELF. It boots straight into that ELF.
- The Linux sustained runner accepts payload, duration, requested speed, and repetition as command-line arguments. The current bare-metal sustained ELF fixes its 11 payload sizes, 60-second windows, and three repetitions in source.
- The AXI Quad SPI design is `C_SCK_RATIO=2`; the Linux driver accepts speed requests but does not change that synthesized divider. A requested speed is therefore not a physical clock control.
- The validated application path is external J55 MOSI-to-MISO loopback. The current project has no specified production SPI workload to call “normal operation.”

The current separate boot images explain why replacing the SD-card `BOOT.BIN` appears to be required. The demo needs a boot-flow change and parameter handling, not a different FPGA design.

## Proposed operator experience

Use one SD card and a single verified boot chain. Power-on must present an operator choice between normal Linux and the SPI test environment; neither long tests nor bare-metal may auto-start. Both modes load/use the same validated PL bitstream. Do not overwrite the current Linux or bare-metal backups while assembling this image.

The chooser and every selectable payload are part of the security boundary. Do not implement the chooser as an unsigned `boot.scr`, and do not load a bare-metal ELF from a mutable FAT file without authenticating it. The Linux chooser and tests must be inside the FIT-protected filesystem or otherwise authenticated. The bare-metal image must be selected through an authenticated U-Boot FIT or Bootgen partition path. Tampering with either menu or payload must fail before the menu is displayed or the program is entered.

FIT verification by U-Boot is not sufficient by itself: the earlier chain must authenticate U-Boot and its required-key control DTB. On ZynqMP that trust chain begins with BootROM authenticating FSBL using the configured device root of trust. The existing project has a signed-FIT host prototype, but no evidence that the live U-Boot/FSBL chain is hardware-rooted. Do not call the menu secure or deploy it as a secure-boot solution until the complete chain is validated. Keep development FIT-signing keys separate from production keys, and do not program eFUSE/BBRAM trust material as part of this software-only prototype.

The Linux launcher should offer:

1. **Normal run / loopback check** — one or a small configured number of transfers with a visible pass/fail result.
2. **Integrity and latency sweep** — selected payloads and trial count, using the existing shared payload pattern and receive-byte comparison.
3. **Sustained throughput** — selected payloads, window length, and repetitions.
4. **Payload stress** — a bounded payload ladder up to the configured spidev transfer limit; stop at the first API failure, timeout, or receive mismatch and save that boundary.
5. **Linux versus bare-metal comparison** — run the Linux leg, reboot into the bare-metal test mode, and return to Linux after capture. Label backend changes and reboot intervals in the result manifest.
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
- Use a signed boot selector/one-shot mode marker to choose Linux or bare-metal, then return to Linux after a bare-metal leg. Verify the valid path and signature-rejection paths in a non-deployed image before changing the working card.
- Store run configuration, raw console output, CSV, start/end timestamps, software/image hashes, and clock/CPU context under a unique run ID. The Linux menu can write this to storage; bare-metal evidence is currently captured from UART and needs a matching host collector. Do not silently overwrite previous results.
- For the physical demo, capture both UART output and the evidence directory. A run should be resumable or visibly cancellable; it should never silently begin a 33-minute run on boot.
- Preserve the Task 2g signed-boot policy. The selector must not add an unsigned fallback or weaken required-key enforcement; authenticate the menu itself, require signatures for every option, and audit the full BootROM-to-application chain as part of integration.

## Open decisions and limits

- “Normal operation” needs a concrete SPI workload from the project owner. Until then, the defensible demo label is “J55 loopback / SPI transfer,” not a claimed end-product operating mode.
- The current bare-metal 60-second sustained run auto-starts after boot. The next bare-metal build should start at a menu instead.
- The verified Linux and bare-metal images are currently separate; an SD-card dual-mode boot flow has not been assembled or tested.
- The current spidev buffer is 1 MiB, but the AXI SPI driver's maximum transfer behavior above the shared 65,536-byte benchmark payload has not been validated. The stress runner must probe this safely and stop on first failure.
- A physical instrument must be used to confirm SCK during the final demo if the result claims an actual clock frequency.

## Implementation sequence

1. Finish and capture the currently running bare-metal benchmark; do not reset the board to prototype the launcher during that run.
2. Make the bare-metal runner parameterized and menu-driven; host-test its parsing and bounds.
3. Add a Linux launcher that exposes the same test/configuration vocabulary and writes one run manifest format.
4. Build a separate dual-mode SD image/boot menu while preserving verified images; audit the boot chain and Task 2g signing policy.
5. Validate each mode, cancellation, reboot/return, file/log persistence, and identical PL bitstream on a non-production card before the live demo.

This proposal makes the operator workflow one-stop while keeping the Linux-versus-bare-metal distinction explicit and preserving the same FPGA design across both modes.
