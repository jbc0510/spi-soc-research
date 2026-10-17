import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { FileBlob, PresentationFile } = await import(pathToFileURL(
  '/home/opentitan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs',
).href);
const workspaceDir = '/home/opentitan/msu2-verify/spi-soc-research';
const skillDir = '/home/opentitan/.codex/plugins/cache/openai-primary-runtime/presentations/26.1011.11113/skills/presentations';
const sourcePath = path.join(workspaceDir, 'deliverables/MSU2_Task2_Evidence_Review_20261017_v41.pptx');
const finalPath = path.join(workspaceDir, 'deliverables/MSU2_Task2_Evidence_Review_20261017_v44.pptx');
const stagingDir = path.join(workspaceDir, '.build/msu2_baremetal_menu_slide_v44');
await fs.mkdir(stagingDir, { recursive: true });

const presentation = await PresentationFile.importPptx(await FileBlob.load(sourcePath));
const slide = presentation.slides.add();
slide.background.fill = '#F8FAF9';

function textBox(name, text, x, y, w, h, size, color, bold = false, align = 'left') {
  const shape = slide.shapes.add({ geometry: 'textbox', name,
    position: { left: x, top: y, width: w, height: h },
    fill: 'none', line: { style: 'solid', fill: 'none', width: 0 } });
  shape.text = text;
  shape.text.style = { fontSize: size, typeface: 'Liberation Sans', color, bold,
    alignment: align, verticalAlignment: 'middle' };
  return shape;
}
function line(name, x1, y1, x2, y2, color = '#1B6E78', width = 3) {
  slide.shapes.add({ geometry: 'line', name,
    position: { left: x1, top: y1, width: x2 - x1, height: y2 - y1 },
    line: { style: 'solid', fill: color, width, endArrowType: 'triangle' } });
}

textBox('section-label', 'ONE-STOP PROGRAM  /  BARE-METAL MENU BUILD', 70, 34, 1120, 28, 16, '#1B6E78', true);
textBox('slide-title', 'Bare-metal menu built; mode handoff remains open', 70, 67, 1140, 58, 35, '#17252C', true);
textBox('slide-subtitle', 'Vitis host build complete  ·  existing Linux BOOT.BIN unchanged  ·  no secure-boot claim', 70, 128, 1140, 32, 19, '#50636B');
slide.shapes.add({ geometry: 'rect', name: 'title-rule',
  position: { left: 70, top: 171, width: 1140, height: 2 },
  fill: '#D5DEDE', line: { style: 'solid', fill: 'none', width: 0 } });

textBox('workflow-heading', 'Operator flow', 70, 196, 490, 38, 27, '#1B6E78', true);
textBox('workflow-body',
  '1  Board boots the existing Linux system.\n\n' +
  '2  After login, run one command and select a mode.\n\n' +
  '3  Linux tests stay in the current session. Bare-metal selection must reboot\n' +
  '    into the standalone menu.\n\n' +
  '4  Exiting bare metal must reboot to the existing Linux default.',
  70, 246, 555, 260, 20, '#17252C');

textBox('menu-heading', 'Bare-metal submenu', 700, 196, 490, 34, 25, '#1B6E78', true);
textBox('menu-list', '1  RX integrity / latency: 11 sizes × 1,000 trials\n' +
  '2  Sustained run: select shared sizes, duration and repetitions\n' +
  '3  Baseline: 11 sizes × 60 s × 3 repetitions\n' +
  '4  One-byte smoke: 1 second  ·  q: idle without transfers',
  700, 240, 500, 125, 16, '#17252C');

textBox('build-proof', 'Vitis 2025.1 host build', 700, 390, 420, 34, 25, '#1B6E78', true);
textBox('build-hash', 'ELF SHA-256\n32110227aeb7d18e6bbd79e71dc08779\n16e76326c9625b8f3eee7ba43da4c4f5',
  700, 430, 440, 67, 15, '#17252C', true);
textBox('status-warning', 'BUILD PASS ONLY — this ELF has not run on the ZCU102.\nThe cross-mode reboot/return flow is not implemented yet.\nThis operator menu is not secure boot.',
  700, 530, 500, 74, 15, '#B35400', true);
textBox('footer', 'MSU-2  ·  Task 2 evidence review  ·  17 Oct 2026', 70, 690, 1120, 20, 13, '#50636B');
slide.speakerNotes.text = 'Source: results/MSU2_ONE_STOP_DEMO_PROGRESS_20261017.md and bare_metal/vitis/spi_axi_bm_menu_parity_20261017_final/build_manifest.json. The bare-metal ELF SHA-256 is 32110227aeb7d18e6bbd79e71dc0877916e76326c9625b8f3eee7ba43da4c4f5. Vitis build status is BUILD_PASS_NOT_HARDWARE_VALIDATION. This slide describes the desired workflow, not a validated handoff: the post-login backend selector and reboot return path remain open. No BOOT.BIN was built or changed in this work. This is not secure boot.';

const preview = await presentation.export({ slide, format: 'png', scale: 1 });
await fs.writeFile(path.join(stagingDir, 'slide21.png'), new Uint8Array(await preview.arrayBuffer()));
const candidatePath = path.join(stagingDir, 'candidate.pptx');
await (await PresentationFile.exportPptx(presentation)).save(candidatePath);
const { finalizePresentation } = await import(pathToFileURL(path.join(skillDir, 'container_tools/artifact_tool_utils.mjs')).href);
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
