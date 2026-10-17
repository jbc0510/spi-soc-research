import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const { FileBlob, PresentationFile } = await import(pathToFileURL(
  '/home/opentitan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs',
).href);

const workspaceDir = '/home/opentitan/msu2-verify/spi-soc-research';
const skillDir = '/home/opentitan/.codex/plugins/cache/openai-primary-runtime/presentations/26.1011.11113/skills/presentations';
const sourcePath = path.join(workspaceDir, 'deliverables/MSU2_Task2_Evidence_Review_20261017_v38.pptx');
const finalPath = path.join(workspaceDir, 'deliverables/MSU2_Task2_Evidence_Review_20261017_v41.pptx');
const stagingDir = path.join(workspaceDir, '.build/msu2_demo_slide_v41');
await fs.mkdir(stagingDir, { recursive: true });

const presentation = await PresentationFile.importPptx(await FileBlob.load(sourcePath));
const slide = presentation.slides.add();
slide.background.fill = '#F8FAF9';

function textBox(name, text, x, y, w, h, size, color, bold = false) {
  const shape = slide.shapes.add({
    geometry: 'textbox', name,
    position: { left: x, top: y, width: w, height: h },
    fill: 'none', line: { style: 'solid', fill: 'none', width: 0 },
  });
  shape.text = text;
  shape.text.style = { fontSize: size, typeface: 'Liberation Sans', color, bold, alignment: 'left', verticalAlignment: 'middle' };
  return shape;
}

textBox('section-label', 'ONE-STOP PROGRAM  /  LIVE ZCU102 VALIDATION', 70, 34, 1120, 28, 16, '#1B6E78', true);
textBox('slide-title', 'Linux demo menu validated on the board', 70, 67, 1140, 58, 39, '#17252C', true);
textBox('slide-subtitle', 'PetaLinux 2025.1  ·  AXI Quad SPI  ·  J55 external loopback', 70, 128, 1140, 32, 21, '#50636B');
slide.shapes.add({
  geometry: 'rect', name: 'title-rule',
  position: { left: 70, top: 171, width: 1140, height: 2 },
  fill: '#D5DEDE', line: { style: 'solid', fill: 'none', width: 0 },
});

textBox('workflow-heading', 'Operator-selected workflow', 70, 190, 500, 34, 26, '#1B6E78', true);
textBox('workflow-body',
  '1  Bring up the hash-checked PL image, clock, reset and SPI device\n\n' +
  '2  Smoke test: TX 0xA5 → RX 0xA5\n\n' +
  '3  Integrity sweep: 11 sizes × 1,000 trials; zero errors or mismatches\n\n' +
  '4  Select payload sizes, duration and repetitions for sustained runs\n\n' +
  '5  Show system details; q returns to the normal Linux shell',
  70, 232, 500, 350, 21, '#17252C');

textBox('chart-heading', 'Sustained application throughput', 635, 190, 555, 34, 26, '#1B6E78', true);
textBox('chart-units', '10 s per payload  ·  one repetition  ·  15.62 MHz requested', 635, 225, 555, 24, 16, '#50636B');
const chart = slide.charts.add('bar', {
  position: { left: 635, top: 255, width: 555, height: 286 },
  categories: ['256 B', '4 KiB', '64 KiB'],
  series: [{ name: 'MB/s', values: [1.333354759, 1.483778849, 1.495183984], fill: '#1B6E78' }],
  barOptions: { direction: 'column', grouping: 'clustered', gapWidth: 90 },
  hasLegend: false,
  xAxis: { textStyle: { fill: '#17252C', fontSize: 17 }, line: { style: 'solid', fill: '#D5DEDE', width: 1 } },
  yAxis: { min: 0, max: 1.6, majorUnit: 0.4, numberFormatCode: '0.0', textStyle: { fill: '#50636B', fontSize: 15 }, majorGridlines: { style: 'solid', fill: '#D5DEDE', width: 1 } },
  dataLabels: { showValue: true, position: 'outEnd', numberFormatCode: '0.00', textStyle: { fill: '#17252C', fontSize: 16, bold: true } },
});
chart.title = 'Application MB/s';

textBox('pass-summary', '55,937 transfers verified  ·  0 API errors  ·  0 RX mismatches', 635, 552, 575, 34, 19, '#16834A', true);
textBox('measurement-boundary',
  'Physical SCK was not measured; the requested SPI rate is not a pin measurement. ' +
  'The run is a 30-second menu demonstration, not the full repeated comparison. ' +
  'Raw run logs remain on the SD card pending host-side archival. Target-generated ' +
  'folder timestamps reflect its incorrect 2025 clock.',
  70, 616, 1140, 54, 15, '#B35400');
textBox('footer', 'MSU-2  ·  Task 2 evidence review  ·  17 Oct 2026', 70, 687, 1120, 20, 13, '#50636B');
slide.speakerNotes.text = 'Evidence source: live ZCU102 serial-console output supplied during the 17 October 2026 lab session. Raw target directories: 20250108T182507Z_smoke; 20250108T182533Z_integrity; 20250108T182942Z_sustained_256B_rep1; 20250108T182952Z_sustained_4096B_rep1; 20250108T183002Z_sustained_65536B_rep1. The board clock generated 2025 timestamps. Physical SCK was explicitly reported NOT_MEASURED.';

const preview = await presentation.export({ slide, format: 'png', scale: 1 });
await fs.writeFile(path.join(stagingDir, 'slide20.png'), new Uint8Array(await preview.arrayBuffer()));
const candidatePath = path.join(stagingDir, 'candidate.pptx');
await (await PresentationFile.exportPptx(presentation)).save(candidatePath);

const { finalizePresentation } = await import(pathToFileURL(path.join(skillDir, 'container_tools/artifact_tool_utils.mjs')).href);
await fs.mkdir(path.dirname(finalPath), { recursive: true });
const result = await finalizePresentation({
  workspaceDir, candidatePath, finalPath,
  pythonExecutable: '/usr/bin/python3',
  integrityValidatorPath: path.join(skillDir, 'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath: path.join(skillDir, 'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs: ['--expected-slide-size-emu', '12192000,6858000', '--validate-heading-fit'],
  requiredNativeChartOwnerSlides: [2, 3, 4, 7, 13, 14, 16, 20],
  nativeChartTargetApplication: 'powerpoint',
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, 'validation.json'),
});
console.log(JSON.stringify({ finalPath, slideCount: presentation.slides.items.length, result }, null, 2));
