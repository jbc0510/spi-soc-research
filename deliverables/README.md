# MSU-2 Task 2 evidence deck

`MSU2_Task2_Evidence_Review_20261014_v5.pptx` is the cumulative Task 2 deck. It covers the Task 2a performance comparison, simulation-only Task 2b CDMA evidence, Task 2c real-time suitability finding, the Task 2d hardening design, Task 2e benchmark-thread CPU analysis, and the host-only Task 2g A/B updater prototype. The deck identifies remaining target integration and validation gaps. The four charts are editable PowerPoint line charts, the boot/update figures are editable diagrams, and slide notes cite the source reports and data.

## Rebuild

From the repository root on the Morgan workstation, use the installed Codex presentation runtime:

```sh
MSU2_TASK2_DECK_OUTPUT=deliverables/MSU2_Task2_Evidence_Review_20261014_rebuild.pptx \
  /home/opentitan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
  scripts/build_task2_evidence_deck.mjs
```

The builder reads the committed comparison CSV and CDMA simulation CSV, exports preview images under `.build/msu2_task2_pptx/previews/`, and runs the presentation package and layout validators before delivering a new PPTX. `CODEX_PRIMARY_RUNTIME_NODE_MODULES` can override the installed runtime module path when needed.

## Slide map

1. Scope and evidence date.
2. Task 2a: Linux and bare-metal effective payload rate by size; crossover is between 16 B and 64 B in the captured run.
3. Task 2b: six simulated CDMA-to-SPI internal-loopback points; not a physical DMA benchmark.
4. Task 2c: 64 KiB Linux latency standard deviation across CPU-frequency points; no hard-deadline claim.
5. Current status and evidence boundaries for Tasks 2d–2g.
6. Task 2d proposed boot trust, signed FIT, and A/B update/rollback design; implementation remains open.
7. Task 2e Linux benchmark-thread CPU share by payload size; bare-metal CPU-use and sustained-throughput tests remain open.
8. Task 2g signed inactive-slot update prototype and four host fault-injection tests; U-Boot and target validation remain open.
