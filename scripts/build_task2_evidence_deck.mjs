import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const root = '/home/opentitan/msu2-verify/spi-soc-research';
const skillDir = '/home/opentitan/.codex/plugins/cache/openai-primary-runtime/presentations/26.1011.11113/skills/presentations';
const nodeModules = process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES ?? '/home/opentitan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const runtimeRequire = createRequire(path.join(nodeModules, '__runtime__.cjs'));
const { Presentation, PresentationFile } = await import(pathToFileURL(runtimeRequire.resolve('@oai/artifact-tool')).href);
const buildDir = path.join(root, '.build/msu2_task2_pptx');
const stagingDir = path.join(buildDir, 'staging');
const previewDir = path.join(buildDir, 'previews');
const finalPath = path.resolve(process.env.MSU2_TASK2_DECK_OUTPUT ?? path.join(root, 'deliverables/MSU2_Task2_Evidence_Review_20261014_v5.pptx'));
const font = 'Liberation Sans';
const { applyPresentationChartFont } = await import(pathToFileURL(path.join(skillDir, 'container_tools/artifact_tool_utils.mjs')).href);
const C = {
  ink: '#17252C', muted: '#50636B', paper: '#F8FAF9', white: '#FFFFFF',
  teal: '#1B6E78', orange: '#C35A2B', blue: '#446B9E', pale: '#DFECEA',
  grid: '#D8E0E1', green: '#247A56', amber: '#A75B1A', red: '#A93F3F',
};

async function readCsv(rel) {
  const raw = await fs.readFile(path.join(root, rel), 'utf8');
  const [headerLine, ...lines] = raw.trim().split(/\r?\n/);
  const headers = headerLine.split(',');
  return lines.map(line => Object.fromEntries(line.split(',').map((v, i) => [headers[i], v])));
}
function box(slide, x, y, w, h, text, style = {}) {
  const s = slide.shapes.add({
    geometry: 'textbox', name: style.name,
    position: { left: x, top: y, width: w, height: h },
    fill: 'none', line: { style: 'solid', fill: 'none', width: 0 },
  });
  s.text = text;
  s.text.style = {
    typeface: font, fontSize: style.size ?? 24, color: style.color ?? C.ink,
    bold: style.bold ?? false, alignment: style.align ?? 'left',
  };
  s.text.insets = 0;
  return s;
}
function baseSlide(p, title, kicker, index) {
  const slide = p.slides.add();
  slide.background.fill = C.paper;
  box(slide, 70, 38, 1120, 25, kicker.toUpperCase(), { size: 15, bold: true, color: C.teal });
  box(slide, 70, 70, 1130, 62, title, { size: 42, bold: true });
  const line = slide.shapes.add({ geometry: 'rect', position: { left: 70, top: 146, width: 1140, height: 2 }, fill: C.grid, line: { style: 'solid', fill: 'none', width: 0 } });
  box(slide, 70, 680, 1120, 18, `MSU-2  ·  Task 2 evidence review  ·  14 Oct 2026                                      ${String(index).padStart(2, '0')}`, { size: 13, color: C.muted });
  return slide;
}
function addLineChart(slide, opts) {
  const chart = slide.charts.add('line', {
    position: opts.position,
    categories: opts.categories,
    series: opts.series,
    hasLegend: opts.hasLegend ?? true,
    legend: { position: 'bottom', overlay: false, textStyle: { fontSize: 16, fill: C.muted } },
    lineOptions: { smooth: false, varyColors: false },
    xAxis: { title: { text: opts.xTitle, textStyle: { fontSize: 16, fill: C.ink } }, textStyle: { fontSize: 14, fill: C.muted }, line: { style: 'solid', fill: C.grid, width: 1 }, majorGridlines: null },
    yAxis: { title: { text: opts.yTitle, textStyle: { fontSize: 16, fill: C.ink } }, min: opts.yMin, max: opts.yMax, majorUnit: opts.yMajor, numberFormatCode: opts.yFormat ?? '0.0', textStyle: { fontSize: 14, fill: C.muted }, line: { style: 'solid', fill: C.grid, width: 1 }, majorGridlines: { style: 'solid', fill: C.grid, width: 1 } },
    chartFill: 'none', chartLine: { style: 'solid', fill: 'none', width: 0 }, plotAreaFill: 'none', plotAreaLine: { style: 'solid', fill: 'none', width: 0 },
  });
  applyPresentationChartFont(chart, { fontFamily: font });
  return chart;
}
function setNotes(slide, lines) { slide.speakerNotes.text = lines.join('\n'); }

const comparison = await readCsv('results/linux_axi_spi_bringup_20261013/linux_vs_baremetal_comparison_20261014.csv');
const cdma = await readCsv('results/task2b_cdma_sim_20261014/cdma_simulated_sweep.csv');
const framework = await readCsv('results/linux_axi_spi_bringup_20261013/task2e_framework_metrics_20261014.csv');
const p = Presentation.create({ slideSize: { width: 1280, height: 720 } });

// 1 — Cover
{
  const s = p.slides.add();
  s.background.fill = C.paper;
  s.shapes.add({ geometry: 'rect', position: { left: 0, top: 0, width: 24, height: 720 }, fill: C.teal, line: { style: 'solid', fill: 'none', width: 0 } });
  box(s, 88, 100, 1080, 34, 'MORGAN STATE UNIVERSITY  /  MSU-2', { size: 18, bold: true, color: C.teal });
  box(s, 88, 195, 1030, 146, 'Task 2: SPI performance,\ndeterminism and secure integration', { size: 54, bold: true });
  box(s, 92, 382, 970, 75, 'Evidence review: completed comparisons, simulation findings, and remaining verification work', { size: 27, color: C.muted });
  box(s, 92, 580, 900, 32, 'ZCU102  ·  AXI Quad SPI  ·  J55 loopback  ·  Evidence through 14 October 2026', { size: 18, color: C.muted });
  setNotes(s, [
    'Scope: Task 2a–2c findings and current status of remaining SOW activities.',
    'Primary source: /home/opentitan/Downloads/MSU-2_SOW_Final (1).docx, revision 2026-02-23.',
  ]);
}

// 2 — Task 2a
{
  const s = baseSlide(p, 'Linux and bare metal cross over by payload size', '2a  /  Performance gap', 2);
  addLineChart(s, {
    position: { left: 56, top: 176, width: 790, height: 435 },
    categories: comparison.map(r => `${Number(r.payload_bytes).toLocaleString('en-US')} B`),
    series: [
      { name: 'Bare metal', values: comparison.map(r => Number(r.baremetal_effective_payload_MB_s)), line: { style: 'solid', fill: C.teal, width: 3 }, marker: { symbol: 'circle', size: 6, fill: C.teal } },
      { name: 'Linux', values: comparison.map(r => Number(r.linux_effective_payload_MB_s)), line: { style: 'solid', fill: C.orange, width: 3 }, marker: { symbol: 'circle', size: 6, fill: C.orange } },
    ], xTitle: 'Payload size', yTitle: 'Effective payload rate (MB/s)', yMin: 0, yMax: 1.7, yMajor: 0.4, yFormat: '0.0',
  });
  box(s, 875, 190, 320, 55, '11,000 transfers per path', { size: 26, bold: true });
  box(s, 875, 252, 320, 66, 'Zero API errors and zero RX mismatches in both captured runs.', { size: 21, color: C.muted });
  box(s, 875, 344, 320, 30, 'Crossover: 16–64 bytes', { size: 24, bold: true, color: C.teal });
  box(s, 875, 387, 320, 112, 'Linux is slower for 1–16 B and faster from 64 B upward in this run. Rates include end-to-end software cost; they are not wire throughput.', { size: 20, color: C.muted });
  box(s, 875, 530, 320, 54, 'Measured paths: SPI ioctl vs XSpi interrupt transfer.', { size: 17, color: C.muted });
  setNotes(s, [
    'Source: results/linux_axi_spi_bringup_20261013/linux_vs_baremetal_comparison_20261014.csv.',
    'Method and limitations: results/linux_axi_spi_bringup_20261013/SOW_2A_FINAL_COMPARISON_20261014.md.',
    'Both paths used the same AXI Quad SPI hardware, J55 external loopback, payload vectors and 1,000 trials per size. Linux used CLOCK_MONOTONIC_RAW; bare metal used XTime_GetTime. No timer cross-calibration was recorded.',
  ]);
}

// 3 — Task 2b
{
  const s = baseSlide(p, 'CDMA loopback simulation passes six payload sizes', '2b  /  PIO and DMA mechanisms', 3);
  addLineChart(s, {
    position: { left: 56, top: 176, width: 790, height: 435 },
    categories: cdma.map(r => `${r.payload_bytes} B`),
    series: [{ name: 'Simulated effective rate', values: cdma.map(r => Number(r.effective_simulated_MB_per_s)), line: { style: 'solid', fill: C.blue, width: 3 }, marker: { symbol: 'circle', size: 7, fill: C.blue } }],
    hasLegend: false, xTitle: 'Payload size', yTitle: 'Effective simulated rate (MB/s)', yMin: 0, yMax: 0.9, yMajor: 0.2, yFormat: '0.0',
  });
  box(s, 875, 190, 320, 60, '6 / 6 payloads passed', { size: 27, bold: true, color: C.green });
  box(s, 875, 258, 320, 75, '1–256 B; every received byte matched the source pattern.', { size: 21, color: C.muted });
  box(s, 875, 365, 320, 55, 'What this proves', { size: 23, bold: true });
  box(s, 875, 408, 320, 81, 'The AXI CDMA keyhole path can feed the modeled AXI Quad SPI DTR and complete internal-loopback transfers.', { size: 19, color: C.muted });
  box(s, 875, 520, 320, 79, 'Simulation only: no physical DMA, CPU-use measurement, J55 test, or PIO/DMA crossover claim.', { size: 18, bold: true, color: C.amber });
  setNotes(s, [
    'Source: results/task2b_cdma_sim_20261014/cdma_simulated_sweep.csv and results/task2b_cdma_sim_20261014/cdma_loopback_simulate.log.',
    'Reproduction and test limits: results/task2b_cdma_sim_20261014/README.md; source testbench: hardware/sim/tb_keyhole.sv.',
    'Vivado 2025.1 fresh build and XSim run passed with host IPC access. The chart shows model effective rate from the BTT write to TX FIFO empty plus the stated 2 us final-word allowance.',
  ]);
}

// 4 — Task 2c
{
  const s = baseSlide(p, 'Linux timing spread grows as CPU frequency falls', '2c  /  Real-time suitability', 4);
  addLineChart(s, {
    position: { left: 56, top: 176, width: 790, height: 435 },
    categories: ['1,200 MHz', '600 MHz', '400 MHz', '300 MHz'],
    series: [{ name: '64 KiB standard deviation', values: [3.87, 5.17, 8.65, 14.23], line: { style: 'solid', fill: C.orange, width: 3 }, marker: { symbol: 'circle', size: 7, fill: C.orange } }],
    hasLegend: false, xTitle: 'A53 CPU operating point', yTitle: 'Latency standard deviation (µs)', yMin: 0, yMax: 16, yMajor: 4, yFormat: '0',
  });
  box(s, 875, 190, 320, 57, '44,000 timed transfers', { size: 26, bold: true });
  box(s, 875, 255, 320, 65, 'Zero reported transfer errors across the four Linux frequency runs.', { size: 20, color: C.muted });
  box(s, 875, 355, 320, 83, 'At 64 KiB, standard deviation rises 3.7× from 1,200 to 300 MHz.', { size: 22, bold: true, color: C.orange });
  box(s, 875, 455, 320, 126, 'Observed timing is variable and frequency-sensitive. These captures do not define a deadline or establish hard real-time behavior; they do not identify the cause of the spread.', { size: 19, color: C.muted });
  setNotes(s, [
    'Frequency sweep source: results/SOW_2F_FREQSWEEP_20260908.md; raw capture: docs/environment/zcu102-2_2f_freqsweep_20260908.log.',
    'Cross-OS timing source: results/linux_axi_spi_bringup_20261013/SOW_2A_FINAL_COMPARISON_20261014.md.',
    'The 64 KiB standard deviations are 3.87, 5.17, 8.65 and 14.23 us at 1,200, 600, 400 and 300 MHz. The frequency-sweep report records zero errors and ivcsw=0; those results do not attribute a jitter mechanism.',
  ]);
}

// 5 — Remaining scope
{
  const s = baseSlide(p, 'Remaining Task 2 work and evidence boundary', 'Status  /  14 October 2026', 5);
  const rows = [
    ['2d  System hardening', 'Design complete', 'Verified boot and signed update implementation remain open.'],
    ['2e  Benchmark framework', 'Partial', 'Paired contract and CPU analysis exist; bare-metal CPU measurement and sustained-throughput test remain open.'],
    ['2f  OS tuning', 'Partial', 'CPU-frequency axis measured; preemption-model and physical DMA driver comparisons remain open.'],
    ['2g  Minimal appliance', 'Partial', 'A/B updater prototype passes host fault tests; U-Boot integration and target secure boot/recovery remain open.'],
  ];
  const colors = [C.red, C.amber, C.amber, C.amber];
  let y = 190;
  for (let i = 0; i < rows.length; i++) {
    const [label, state, detail] = rows[i];
    s.shapes.add({ geometry: 'rect', position: { left: 72, top: y + 4, width: 8, height: 74 }, fill: colors[i], line: { style: 'solid', fill: 'none', width: 0 } });
    box(s, 100, y, 340, 32, label, { size: 23, bold: true });
    box(s, 100, y + 39, 290, 27, state, { size: 18, bold: true, color: colors[i] });
    box(s, 445, y + 3, 735, 70, detail, { size: 20, color: C.muted });
    y += 112;
  }
  box(s, 72, 638, 1120, 27, 'Status labels follow the SOW activity wording; partial evidence is not presented as criterion closure.', { size: 16, color: C.muted });
  setNotes(s, [
    'SOW source: /home/opentitan/Downloads/MSU-2_SOW_Final (1).docx, revision 2026-02-23.',
    '2d/2e audit basis: results/SOW_2E_HARDENED_BOARD_VALIDATION_20260922.md and results/linux_axi_spi_bringup_20261013/SOW_2A_FINAL_COMPARISON_20261014.md.',
    '2f source: results/SOW_2F_FREQSWEEP_20260908.md. 2g sources: results/SOW_2G_RECOVERY_20260909.md and results/SOW_2G_FWENV_20260908.md.',
    'Historical file labels do not exactly mirror the SOW’s unlettered activity list. This slide maps 2d–2g by the SOW’s wording and sequence.',
  ]);
}

// 6 — Task 2d hardening design
{
  const s = baseSlide(p, 'Proposed boot trust and rollback architecture', '2d  /  System hardening design', 6);
  const bootNodes = [
    ['Immutable key', 'Approved PPK hash\nheld by device'],
    ['BootROM + FSBL', 'Authenticate first-stage\nboot code'],
    ['BOOT.BIN', 'Verify PMUFW, PL,\nATF and U-Boot'],
    ['Signed FIT', 'Verify kernel, DTB\nand root filesystem'],
    ['Read-only OS', 'Run only the\nauthenticated release'],
  ];
  const updateNodes = [
    ['Stage inactive slot', 'Keep confirmed\nslot untouched'],
    ['Verify release', 'Check signature,\ndigest and image'],
    ['Trial boot', 'Bounded attempt\ncount and logs'],
    ['Health check', 'Linux start + SPI\nloopback smoke test'],
    ['Confirm / rollback', 'Mark good or return\nto prior slot'],
  ];
  const nodeW = 196;
  const gap = 32;
  const startX = 62;
  const addNode = (x, y, title, detail, accent) => {
    const shape = s.shapes.add({ geometry: 'rect', position: { left: x, top: y, width: nodeW, height: 106 }, fill: C.white, line: { style: 'solid', fill: accent, width: 2 } });
    shape.text = `${title}\n${detail}`;
    shape.text.style = { typeface: font, fontSize: 18, color: C.ink, alignment: 'center' };
    shape.text.insets = { left: 8, right: 8, top: 9, bottom: 8 };
  };
  const addFlow = (nodes, y, accent) => {
    nodes.forEach((n, i) => {
      const x = startX + i * (nodeW + gap);
      addNode(x, y, n[0], n[1], accent);
      if (i < nodes.length - 1) {
        s.shapes.add({ geometry: 'rightArrow', position: { left: x + nodeW + 3, top: y + 42, width: gap - 6, height: 22 }, fill: accent, line: { style: 'solid', fill: accent, width: 1 } });
      }
    });
  };
  box(s, 62, 174, 1135, 26, 'BOOT AUTHENTICATION', { size: 17, bold: true, color: C.teal });
  addFlow(bootNodes, 208, C.teal);
  box(s, 62, 350, 1135, 26, 'UPDATE TRANSACTION AND AUTOMATIC ROLLBACK', { size: 17, bold: true, color: C.blue });
  addFlow(updateNodes, 384, C.blue);
  box(s, 62, 528, 1135, 70, 'Design only: no signed boot image or A/B update is deployed. Development boot-header authentication is not fielded eFUSE-rooted trust. No eFUSE was programmed.', { size: 20, bold: true, color: C.amber });
  setNotes(s, [
    'Design source: results/SOW_2D_SYSTEM_HARDENING_DESIGN_20261014.md.',
    'Existing U-Boot environment fallback evidence and limitations: results/SOW_2G_RECOVERY_20260909.md.',
    'AMD Zynq UltraScale+ MPSoC Software Developer Guide, Boot Time Security: https://docs.amd.com/r/en-US/ug1137-zynq-ultrascale-mpsoc-swdev/Boot-Time-Security.',
    'AMD Embedded Design Tutorial, Enabling Boot Header Authentication: https://docs.amd.com/r/en-US/ug1209-embedded-design-tutorial/Enabling-Boot-Header-Authentication. Boot-header authentication omits the eFUSE key-hash and revocation checks; it is a development mechanism, not the fielded trust anchor.',
  ]);
}

// 7 — Task 2e framework metrics
{
  const s = baseSlide(p, 'Linux thread CPU share declines as payload grows', '2e  /  Comparative framework status', 7);
  addLineChart(s, {
    position: { left: 56, top: 176, width: 790, height: 435 },
    categories: framework.map(r => `${Number(r.payload_bytes).toLocaleString('en-US')} B`),
    series: [{ name: 'Linux benchmark thread', values: framework.map(r => Number(r.linux_thread_cpu_util_percent)), line: { style: 'solid', fill: C.blue, width: 3 }, marker: { symbol: 'circle', size: 6, fill: C.blue } }],
    hasLegend: false, xTitle: 'Payload size', yTitle: 'Thread CPU time / loop wall time (%)', yMin: 0, yMax: 80, yMajor: 20, yFormat: '0',
  });
  box(s, 875, 190, 320, 56, '11,000 paired transfers', { size: 25, bold: true });
  box(s, 875, 255, 320, 72, 'Zero transfer errors and RX mismatches in both recorded runs.', { size: 20, color: C.muted });
  box(s, 875, 354, 320, 83, 'Linux thread CPU share: 67.9% at 1 B → 1.5% at 64 KiB.', { size: 22, bold: true, color: C.blue });
  box(s, 875, 456, 320, 141, 'Scope: benchmark thread over the 1,000-transfer loop. Bare-metal CPU use was not instrumented, and this fixed ladder does not establish maximum sustainable throughput.', { size: 18, color: C.muted });
  setNotes(s, [
    'Source CSV: results/linux_axi_spi_bringup_20261013/task2e_framework_metrics_20261014.csv.',
    'Derived from raw Linux CLOCK_THREAD_CPUTIME_ID and CLOCK_MONOTONIC_RAW loop totals in results/linux_axi_spi_bringup_20261013/linux_benchmark_20261014.log.',
    'Framework status and scope: results/SOW_2E_BENCHMARK_FRAMEWORK_STATUS_20261014.md. The utilization percentage is per benchmark thread normalized to one CPU core, not total system CPU utilization.',
  ]);
}

// 8 — Task 2g update prototype
{
  const s = baseSlide(p, 'A/B update prototype preserves the confirmed slot', '2g  /  Minimal stack and robust update', 8);
  const stages = [
    ['Authenticate', 'RSA/SHA-256\nsignature'],
    ['Write inactive', 'Chunked write\n+ fsync'],
    ['Readback check', 'Digest + signature\nre-verified'],
    ['Trial boot', 'Two bounded\nattempts'],
    ['Confirm / rollback', 'Health result selects\nnew or known-good'],
  ];
  const nodeW = 196, gap = 32, startX = 62, y = 250;
  stages.forEach(([title, detail], i) => {
    const x = startX + i * (nodeW + gap);
    const node = s.shapes.add({ geometry: 'rect', position: { left: x, top: y, width: nodeW, height: 112 }, fill: C.white, line: { style: 'solid', fill: C.blue, width: 2 } });
    node.text = `${title}\n${detail}`;
    node.text.style = { typeface: font, fontSize: 18, color: C.ink, alignment: 'center' };
    node.text.insets = { left: 8, right: 8, top: 10, bottom: 8 };
    if (i < stages.length - 1) s.shapes.add({ geometry: 'rightArrow', position: { left: x + nodeW + 3, top: y + 45, width: gap - 6, height: 22 }, fill: C.blue, line: { style: 'solid', fill: C.blue, width: 1 } });
  });
  box(s, 72, 180, 1060, 44, '4 / 4 HOST FAULT-INJECTION TESTS PASSED', { size: 26, bold: true, color: C.green });
  box(s, 72, 416, 530, 95, 'Confirmed slot A stayed selected after invalid signatures, interrupted writes, boot-limit expiry, and an explicit failed health check.', { size: 20, color: C.muted });
  box(s, 650, 416, 530, 105, 'Prototype boundary: host files and JSON control state. No U-Boot, SD-card, signed target image, hardware trust anchor, or ZCU102 power-loss test.', { size: 20, bold: true, color: C.amber });
  box(s, 72, 566, 1120, 46, 'Task 2g remains partial until target integration, boot authentication, and recovery fault tests pass.', { size: 21, bold: true, color: C.ink });
  setNotes(s, [
    'Report: results/SOW_2G_AB_UPDATE_PROTOTYPE_20261014.md.',
    'Prototype: linux/appliance/ab_update_prototype.py. Tests: tests/test_task2g_ab_update.py.',
    'Existing on-target U-Boot environment fallback evidence: results/SOW_2G_RECOVERY_20260909.md; it is a single-copy CRC fallback, not image/rootfs update recovery.',
    'All four host tests passed on 2026-10-14. The diagram depicts reference logic, not an installed or hardware-rooted boot chain.',
  ]);
}

await fs.mkdir(stagingDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });
await fs.mkdir(path.dirname(finalPath), { recursive: true });
for (const [i, slide] of p.slides.items.entries()) {
  const blob = await p.export({ slide, format: 'png', scale: 1 });
  await fs.writeFile(path.join(previewDir, `slide-${String(i + 1).padStart(2, '0')}.png`), new Uint8Array(await blob.arrayBuffer()));
}
const draftPath = path.join(stagingDir, 'candidate.pptx');
await (await PresentationFile.exportPptx(p)).save(draftPath);
const { finalizePresentation } = await import(pathToFileURL(path.join(skillDir, 'container_tools/artifact_tool_utils.mjs')).href);
const result = await finalizePresentation({
  workspaceDir: root,
  candidatePath: draftPath,
  finalPath,
  pythonExecutable: '/home/opentitan/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3.12',
  integrityValidatorPath: path.join(skillDir, 'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath: path.join(skillDir, 'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs: ['--expected-slide-size-emu', '12192000,6858000', '--validate-heading-fit'],
  requiredNativeChartOwnerSlides: [2, 3, 4, 7],
  materializeLiteralChartWorkbooks: true,
  nativeChartTargetApplication: 'powerpoint',
  fontPolicy: { basis: 'design', families: [font] },
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, 'validation_v5.json'),
});
console.log(JSON.stringify({ finalPath, slides: p.slides.items.length, result }, null, 2));
