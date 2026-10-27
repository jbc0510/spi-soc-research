#!/usr/bin/env python3
"""Assemble the curated MSU-2 SoC simulation/emulation submission package."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import zipfile
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DELIVERABLES = ROOT / "deliverables"
PACKAGE = DELIVERABLES / "MSU2_SoC_Submission_20261031"
ARCHIVE = DELIVERABLES / "MSU2_SoC_Submission_20261031.zip"
RUN_SOURCE_COMMIT = "8fded57"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_file(source: str, destination: str | None = None) -> Path:
    src = ROOT / source
    if not src.is_file():
        raise FileNotFoundError(src)
    rel = Path(destination) if destination else Path(source)
    dst = PACKAGE / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return dst


def copy_tree(source: str, destination: str | None = None,
              *, excluded: set[str] | None = None) -> list[Path]:
    src = ROOT / source
    if not src.is_dir():
        raise FileNotFoundError(src)
    rel = Path(destination) if destination else Path(source)
    dst = PACKAGE / rel
    excluded = excluded or set()
    copied: list[Path] = []
    for item in sorted(src.rglob("*")):
        if not item.is_file() or item.name in excluded:
            continue
        target = dst / item.relative_to(src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)
        copied.append(target)
    return copied


def copy_git_file(commit: str, source: str, destination: str) -> Path:
    result = subprocess.run(
        ["git", "show", f"{commit}:{source}"], cwd=ROOT,
        check=True, stdout=subprocess.PIPE,
    )
    dst = PACKAGE / destination
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(result.stdout)
    return dst


def write_text(relative: str, content: str) -> Path:
    target = PACKAGE / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return target


def main() -> None:
    if PACKAGE.exists() or ARCHIVE.exists():
        raise SystemExit(f"Refusing to overwrite existing output: {PACKAGE} or {ARCHIVE}")
    DELIVERABLES.mkdir(parents=True, exist_ok=True)
    PACKAGE.mkdir()

    head = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True,
        text=True, stdout=subprocess.PIPE,
    ).stdout.strip()
    status = subprocess.run(
        ["git", "status", "--short"], cwd=ROOT, check=True,
        text=True, stdout=subprocess.PIPE,
    ).stdout.strip()

    copied: list[Path] = []

    # Presentation and submission status.
    for source, destination in [
        ("deliverables/MSU2_Task2_Evidence_Review_20261023_v54.pptx",
         "01_Presentation/MSU2_Task2_Evidence_Review_20261023_v54.pptx"),
        ("tmp/ila_trace_capture/SLIDE_GUIDE.md", "01_Presentation/SLIDE_GUIDE.md"),
        ("deliverables/MSU2_SoC_Final_Closeout_20261027.md", "02_Documentation/FINAL_CLOSEOUT_PLAN.md"),
        ("results/MSU2_TASK2_SOW_STATUS_20261016.md", "02_Documentation/SOW_STATUS_20261016.md"),
        ("docs/task2_axi_bm_comparison.md", "02_Documentation/AXI_SPI_COMPARISON_AND_PROVENANCE.md"),
    ]:
        copied.append(copy_file(source, destination))

    # Source snapshots used by the sustained board run, pinned by its manifest.
    for source, destination in [
        ("common/spi_benchmark_contract.h", "03_Source/as_run_2e/common/spi_benchmark_contract.h"),
        ("bare_metal/src/spi_sustainable_benchmark_bare_axi.c", "03_Source/as_run_2e/bare_metal/spi_sustainable_benchmark_bare_axi.c"),
        ("linux/src/spi_sustainable_benchmark.c", "03_Source/as_run_2e/linux/spi_sustainable_benchmark.c"),
        ("scripts/build_spi_axi_bm_ratio2_vitis.py", "03_Source/as_run_2e/scripts/build_spi_axi_bm_ratio2_vitis.py"),
        ("tests/test_sustainable_benchmark_host.py", "03_Source/as_run_2e/tests/test_sustainable_benchmark_host.py"),
    ]:
        copied.append(copy_git_file(RUN_SOURCE_COMMIT, source, destination))
    # The parser was added after the as-run firmware source revision. Preserve
    # its current analysis implementation separately instead of mislabeling it
    # as part of the exact source snapshot used to build the board ELF.
    copied.append(copy_file(
        "scripts/parse_task2e_baremetal_sustained.py",
        "03_Source/analysis/parse_task2e_baremetal_sustained.py",
    ))

    # Current Vivado simulation and block-design sources (the simulation log
    # and source snapshot are both included for direct reviewer inspection).
    for source in [
        "hardware/sim/tb_keyhole.sv",
        "hardware/sim/run_task2b_cdma_loopback.tcl",
        "hardware/sim/sim_keyhole_bd.tcl",
        "hardware/spi_bm_bd_2025p1.tcl",
        "hardware/zcu102_spi_benchmark.xdc",
        "scripts/compare_task2a_runs.py",
    ]:
        copied.append(copy_file(source, f"03_Source/project/{source}"))

    # Linux board operator menu package as exercised on the ZCU102. Includes
    # its own package manifest and SHA256SUMS.
    copied.extend(copy_tree(
        "results/msu2_linux_demo_bundle_20261017_v3",
        "03_Source/linux_board_menu_bundle_v3",
    ))

    # Core simulation, board, timing, sustained, and security evidence.
    for source, destination in [
        ("results/linux_axi_spi_bringup_20261013", "04_Evidence/2a_linux_baremetal_comparison"),
        ("results/linux_axi_spi_revalidation_20261016", "04_Evidence/2a_linux_revalidation"),
        ("results/task2b_cdma_sim_20261014", "04_Evidence/2b_cdma_simulation"),
        ("results/ratio2_j55_board_validation_20260929", "04_Evidence/physical_j55_baseline"),
        ("results/task2e_sustainable_runner_20261016", "04_Evidence/2e_paired_sustained"),
        ("results/task2e_stress_envelope_20261017", "04_Evidence/2e_stress_envelope_status"),
        ("results/task2g_signed_selector_sandbox_20261017", "04_Evidence/2g_signed_fit_host_sandbox"),
        ("results/task2g_live_board_audit_20261015", "04_Evidence/2g_live_board_audit"),
    ]:
        excluded = {"BOOT_AXI_SUSTAINED_20261016.BIN"} if "sustainable_runner" in source else set()
        copied.extend(copy_tree(source, destination, excluded=excluded))

    # Hardware reports/XSA for the hash-identified ratio-2 implementation.
    for name in [
        "build_provenance.txt", "route_status_impl.txt", "timing_summary_impl.txt",
        "utilization_impl.txt", "io_impl.txt", "spi_ratio2_j55_wrapper.xsa",
    ]:
        copied.append(copy_file(
            f"results/ratio2_j55_lvcmos33_20260929/{name}",
            f"04_Evidence/validated_pl_design/{name}",
        ))

    # Bounded assessment reports and raw 2f frequency-sweep capture.
    report_files = [
        "SOW_2B_PIO_DMA_ASSESSMENT_20261014.md",
        "SOW_2B_PHYSICAL_DMA_EXPERIMENT_DESIGN_20261015.md",
        "SOW_2C_REALTIME_SUITABILITY_20261014.md",
        "SOW_2D_SYSTEM_HARDENING_DESIGN_20261014.md",
        "SOW_2D_SYSTEM_HARDENING_GAP_REVIEW_20261014.md",
        "SOW_2F_FREQSWEEP_20260908.md",
        "SOW_2G_AB_UPDATE_PROTOTYPE_20261014.md",
        "SOW_2G_FWENV_20260908.md",
        "SOW_2G_HARDENING_CONTRAST_20261015.md",
        "SOW_2G_PETALINUX_FIT_20261015.md",
        "SOW_2G_RECOVERY_20260909.md",
        "SOW_2G_UBOOT_FIT_SANDBOX_20261015.md",
        "SOW_2G_ZCU102_HARDENING_DEMO_20261015.md",
        "MSU2_ONE_STOP_DEMO_PROGRESS_20261017.md",
        "MSU2_ONE_STOP_LINUX_DEMO_PROGRESS_20261017.md",
        "MSU2_ONE_STOP_SIGNED_SELECTOR_AND_SD_AUDIT_20261017.md",
    ]
    for name in report_files:
        copied.append(copy_file(f"results/{name}", f"04_Evidence/reports/{name}"))
    copied.append(copy_file(
        "docs/environment/zcu102-2_2f_freqsweep_20260908.log",
        "04_Evidence/2f_cpu_frequency_sweep/zcu102-2_2f_freqsweep_20260908.log",
    ))

    # The ILA investigation is a post-cutoff engineering note, not a claimed
    # submission result. Include enough evidence to make that boundary auditable.
    copied.append(copy_file("tmp/ila_trace_capture/TEST_RESULTS.md", "05_Open_Items/ILA_TEST_RESULTS.md"))
    copied.append(copy_file("tmp/ila_trace_capture/README.md", "05_Open_Items/ILA_README.md"))
    copied.append(copy_file(
        "tmp/ila_trace_capture/output_rebuild5_20261027/vivado.log",
        "05_Open_Items/ila_build_20261027/vivado.log",
    ))
    copied.append(copy_file(
        "tmp/ila_trace_capture/output_rebuild5_20261027/vivado.jou",
        "05_Open_Items/ila_build_20261027/vivado.jou",
    ))

    readme = f"""# MSU-2 SoC submission package

**Deliverable:** Exploring System on Chip Architectures – Simulation and Emulation Results with Code  
**Due date:** 31 October 2026  
**Package prepared:** {date.today().isoformat()}  
**Package status:** Evidence package candidate for final review.

## What this package contains

- The 22-slide evidence review and slide guide.
- Source for the sustained board benchmark pinned to the exact source revision
  named in the run manifest, plus Vivado simulation and block-design scripts.
- The exercised Linux operator-menu bundle, its binaries/overlays, and its
  internal SHA256 manifest.
- Linux/bare-metal fixed-trial results, paired 60-second results, raw serial
  captures, CSVs, build/run manifests, simulation logs, and matching reports.
- The validated ratio-2 PL XSA and implementation reports, plus the board
  validation and J55 loopback records.
- Bounded 2c/2d/2f/2g reports and the current SOW activity status.
- A separate ILA status note and Vivado failure log from 27 October. This is
  explicitly open work and contains no captured ILA trace.

## Main result claims and limits

1. The ZCU102 Linux and bare-metal SPI paths completed the documented
   fixed-trial payload ladder with byte-for-byte RX verification and zero
   transfer errors.
2. The paired sustained comparison completed 33 Linux and 33 bare-metal
   60-second points with zero recorded errors, timeouts, short transfers, or
   mismatches. Task 2e remains partial because the clock/payload stress
   envelope has not been established.
3. The CDMA-to-AXI-SPI result is a passing six-size internal-loopback
   simulation. It does not claim physical DMA throughput or a PIO/DMA
   crossover.
4. Latency and jitter findings are bounded to the recorded configurations;
   they do not establish hard real-time guarantees or isolate a universal
   Linux-only cost.
5. The presentation's evidence cutoff is 23 October 2026. The 27 October ILA
   investigation is recorded separately as an unsuccessful build attempt.
   The live design has no new ILA bitstream/`.ltx` or captured logic trace.
6. Bare-metal handoff, reliable clock/payload limits, and full secure-boot
   validation remain open. This package does not claim the whole Task 2 or a
   hardware-rooted secure boot chain is complete.

## Suggested review order

1. `01_Presentation/` for the concise results story.
2. `02_Documentation/SOW_STATUS_20261016.md` for activity-level status.
3. `04_Evidence/2a_linux_baremetal_comparison/` and
   `04_Evidence/2e_paired_sustained/` for the main board results.
4. `04_Evidence/2b_cdma_simulation/` for the simulation result.
5. `03_Source/` and the `04_Evidence/` manifests/checksums for code and
   reproducibility.
6. `05_Open_Items/` for unresolved ILA and other boundaries.

## Reproduction pointers

- CDMA simulation: see `04_Evidence/2b_cdma_simulation/README.md` and
  `03_Source/project/hardware/sim/run_task2b_cdma_loopback.tcl`.
- Fixed-trial analysis: see
  `04_Evidence/2a_linux_baremetal_comparison/SOW_2A_FINAL_COMPARISON_20261014.md`
  and `03_Source/project/scripts/compare_task2a_runs.py`.
- Paired sustained report includes the parser command and exact hardware,
  software, source, image, and clock identity. The precise as-run source
  snapshot is under `03_Source/as_run_2e/`.
- The original combined development `BOOT_AXI_SUSTAINED_20261016.BIN` is
  deliberately not included. Its SHA-256 and component details remain in the
  paired run manifest and checksum records; the individual as-run application
  ELF, Linux executable, source, bitstream, and XSA evidence are included.

## Integrity

`SHA256SUMS` covers every file in this package except `SHA256SUMS` itself.
Verify from this directory with `sha256sum -c SHA256SUMS`. Result folders also
retain their original manifests/checksum files. Those original checksums are
preserved as received and are not replaced by the package-level manifest.
"""
    write_text("README.md", readme)

    provenance = f"""# Package provenance

- Repository root: `{ROOT}`
- Repository HEAD at package time: `{head}`
- Sustained-run source revision: `{RUN_SOURCE_COMMIT}` (the source file SHA-256
  values match `baremetal_input_manifest.json` and
  `baremetal_build_manifest.json` in the paired sustained evidence folder).
- Working tree at package time was not clean. The package uses the pinned Git
  source snapshot for the as-run sustained benchmark and copies run evidence
  without modifying it. Current-working-tree changes are not silently folded
  into the as-run source snapshot.
- Files copied to the package: {len(copied)} before package README/provenance and
  checksum records.
- The package is a curated evidence snapshot; generated project files,
  temporary caches, and the combined development boot image are excluded.
"""
    write_text("PROVENANCE.md", provenance)

    # Add a compact top-level package inventory.
    inventory = [
        "# Package inventory",
        "",
        "Paths are relative to this directory. See README.md for reading order and claim boundaries.",
        "",
    ]
    for path in sorted(p for p in PACKAGE.rglob("*") if p.is_file()):
        inventory.append(f"- `{path.relative_to(PACKAGE).as_posix()}` ({path.stat().st_size} bytes)")
    write_text("INVENTORY.md", "\n".join(inventory) + "\n")

    # Package-level checksums use stable relative paths and include every file
    # except the checksum list itself.
    files = sorted(p for p in PACKAGE.rglob("*") if p.is_file() and p != PACKAGE / "SHA256SUMS")
    sums = "".join(f"{sha256(path)}  {path.relative_to(PACKAGE).as_posix()}\n" for path in files)
    write_text("SHA256SUMS", sums)

    # Zip the directory tree with paths rooted at the package name.
    with zipfile.ZipFile(ARCHIVE, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in sorted(p for p in PACKAGE.rglob("*") if p.is_file()):
            zf.write(path, Path(PACKAGE.name) / path.relative_to(PACKAGE))

    print(f"PACKAGE_DIR={PACKAGE}")
    print(f"PACKAGE_ZIP={ARCHIVE}")
    print(f"FILES={len(files) + 1}")
    print(f"ZIP_BYTES={ARCHIVE.stat().st_size}")
    print(f"REPOSITORY_HEAD={head}")
    print(f"RUN_SOURCE_COMMIT={RUN_SOURCE_COMMIT}")
    print(f"WORKTREE_DIRTY={bool(status)}")


if __name__ == "__main__":
    main()
