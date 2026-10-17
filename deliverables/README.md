# MSU-2 Task 2 evidence deck

`MSU2_Task2_Evidence_Review_20261017_v33.pptx` is the current cumulative Task 2 deck. It covers the Task 2a performance comparison, Task 2b PIO/DMA assessment, Task 2c real-time suitability finding, Task 2d hardening design, Task 2e benchmark and stress-test status, Task 2g A/B updater prototype, the Vivado Enterprise license diagnostic, the Linux-versus-bare-metal comparison, and the one-stop ZCU102 demo work. Slides 15–16 describe the proposed workflow and a new bare-metal repeat run. Slide 17 records the Linux host-tested console and the built bare-metal UART menu. Slide 18 records a signed Linux/standalone FIT selector prototype in U-Boot sandbox and the read-only SD-card audit. The actual fixed U-Boot menu, target boot, physical SPI test, and hardware-rooted trust remain open. Task 2e remains partial pending the payload/clock envelope test. Charts and diagrams are editable PowerPoint objects, and slide notes cite the source reports and data.

## Rebuild

From the repository root on the Morgan workstation, use the installed Codex presentation runtime:

```sh
  MSU2_TASK2_DECK_OUTPUT=deliverables/MSU2_Task2_Evidence_Review_20261017_v33_rebuild.pptx \
  CODEX_PRIMARY_RUNTIME_NODE_MODULES=/home/opentitan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules \
  /home/opentitan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
  scripts/build_task2_evidence_deck.mjs
```

The builder reads the committed comparison CSV and CDMA simulation CSV, exports preview images under `.build/msu2_task2_pptx/previews/`, and runs the presentation package and layout validators before delivering a new PPTX. `CODEX_PRIMARY_RUNTIME_NODE_MODULES` can override the installed runtime module path when needed. The proposed one-stop operator workflow is also described in `docs/design/MSU2_ONE_STOP_DEMO_ARCHITECTURE.md`.

## Slide map

1. Scope and evidence date.
2. Task 2a: Linux and bare-metal effective payload rate by size; crossover is between 16 B and 64 B in the captured run.
3. Task 2b: assessment closure combines the 11-size measured PIO curve, six simulated CDMA-to-SPI internal-loopback points, and the invalid ZDMA-to-PS-SPI result; it is not a physical DMA benchmark.
4. Task 2c: 64 KiB Linux latency standard deviation across CPU-frequency points; no hard-deadline claim.
5. Current status and evidence boundaries for Tasks 2d–2g.
6. Task 2d proposed boot trust, signed FIT, and A/B update/rollback design; implementation remains open.
7. Task 2e Linux benchmark-thread CPU share by payload size; the paired sustained comparison is complete and Task 2e remains partial pending the reliable payload/clock stress test.
8. Task 2g signed inactive-slot update prototype and four host fault-injection tests; U-Boot and target validation remain open.
9. Vivado Enterprise license diagnostic: host-ID visibility caused a false failure inside the sandbox; synthesis succeeds with normal workstation host access.
10. Task 2g ZCU102 Linux execution: four update-control cases pass on the board CPU using target OpenSSL and `/tmp` files; persistent update state and verified boot remain untested.
11. Task 2g signed PetaLinux FIT build and tamper verification; host-side only, not trusted hardware-rooted boot.
12. Task 2g live boot-flow audit; the current generic boot policy can bypass FIT signature enforcement.
13. Matched fixed-trial Linux and bare-metal comparison on the same validated PL image.
14. Paired 60-second sustained Linux and bare-metal application throughput; Task 2e remains partial pending payload/clock stress testing.
15. Proposed one-stop ZCU102 demo workflow; shared SD card and PL image, distinct Linux and bare-metal modes, configurable runs, and saved evidence. Not implemented or board-validated.
16. Bare-metal sustained-run repeatability; all 33 existing-size points passed, with median rates within 0.93% of the previous run. The payload/clock limit remains untested.
17. One-stop console milestone; Linux menu passes host tests and bare-metal UART menu builds against the pinned XSA. Neither was installed or tested on the board. A signed boot-time OS chooser and authenticated boot chain remain open.
18. Signed two-mode FIT selection passes U-Boot sandbox, and the SD-card partition is backed up and audited read-only. The interactive boot menu, target execution, physical SPI, and BootROM-rooted chain remain unvalidated.
