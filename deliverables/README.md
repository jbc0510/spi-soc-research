# MSU-2 Task 2 evidence deck

`MSU2_Task2_Evidence_Review_20261015_v15.pptx` is the current cumulative Task 2 deck. It covers the Task 2a performance comparison, Task 2b PIO/DMA assessment, Task 2c real-time suitability finding, the Task 2d hardening design, Task 2e benchmark-thread CPU analysis, the Task 2g A/B updater prototype, the Vivado Enterprise license diagnostic, and the baseline-versus-hardened update demo executed on ZCU102 Linux. The deck identifies remaining target boot-chain integration and validation gaps. The four charts and process figures are editable PowerPoint objects, and slide notes cite the source reports and data.

## Rebuild

From the repository root on the Morgan workstation, use the installed Codex presentation runtime:

```sh
MSU2_TASK2_DECK_OUTPUT=deliverables/MSU2_Task2_Evidence_Review_20261015_rebuild.pptx \
  /home/opentitan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
  scripts/build_task2_evidence_deck.mjs
```

The builder reads the committed comparison CSV and CDMA simulation CSV, exports preview images under `.build/msu2_task2_pptx/previews/`, and runs the presentation package and layout validators before delivering a new PPTX. `CODEX_PRIMARY_RUNTIME_NODE_MODULES` can override the installed runtime module path when needed.

## Slide map

1. Scope and evidence date.
2. Task 2a: Linux and bare-metal effective payload rate by size; crossover is between 16 B and 64 B in the captured run.
3. Task 2b: assessment closure combines the 11-size measured PIO curve, six simulated CDMA-to-SPI internal-loopback points, and the invalid ZDMA-to-PS-SPI result; it is not a physical DMA benchmark.
4. Task 2c: 64 KiB Linux latency standard deviation across CPU-frequency points; no hard-deadline claim.
5. Current status and evidence boundaries for Tasks 2d–2g.
6. Task 2d proposed boot trust, signed FIT, and A/B update/rollback design; implementation remains open.
7. Task 2e Linux benchmark-thread CPU share by payload size; bare-metal CPU-use and sustained-throughput tests remain open.
8. Task 2g signed inactive-slot update prototype and four host fault-injection tests; U-Boot and target validation remain open.
9. Vivado Enterprise license diagnostic: host-ID visibility caused a false failure inside the sandbox; synthesis succeeds with normal workstation host access.
10. Task 2g ZCU102 Linux execution: four update-control cases pass on the board CPU using target OpenSSL and `/tmp` files; persistent update state and verified boot remain untested.
