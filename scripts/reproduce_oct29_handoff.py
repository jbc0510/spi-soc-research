#!/usr/bin/env python3
"""Build the preserved Oct 29 candidate or committed final firmware; never deploy."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BSP = ROOT / "results/task2h_boot_handoff_20261029/rebuilt"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cc", default=os.environ.get("CC", "aarch64-none-elf-gcc"))
    ap.add_argument("--variant", choices=("historical", "final"), default="final")
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    out = args.output.resolve()
    if out.is_relative_to(BSP):
        ap.error("Use a separate output directory to preserve recovered evidence")
    out.mkdir(parents=True, exist_ok=True)
    source = (BSP / "spi_sustainable_benchmark_bare_axi.c" if args.variant == "historical"
              else ROOT / "bare_metal/src/spi_sustainable_benchmark_bare_axi.c")
    cmd = [args.cc, "-DSDT", "-O2", "-g3", "-Wall", "-Wextra",
           "-specs=" + str(BSP / "Xilinx.spec"), "-I" + str(BSP / "include"),
           "-I" + str(ROOT / "common"), str(source),
           "-Wl,-T," + str(BSP / "lscript.ld"), "-L" + str(BSP / "lib"),
           "-Wl,--start-group", "-lxilstandalone", "-lxiltimer", "-lxil",
           "-lgcc", "-lc", "-lm", "-Wl,--end-group",
           "-Wl,-Map," + str(out / "app.map"), "-o", str(out / "spi_axi_bm_menu_aarch64.elf")]
    print(shlex.join(cmd), flush=True)
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    (out / "build.log").write_text(result.stdout + result.stderr)
    (out / "command.json").write_text(json.dumps(cmd, indent=2) + "\n")
    if result.returncode:
        raise SystemExit(result.stderr)
    elf = out / "spi_axi_bm_menu_aarch64.elf"
    import struct
    header = elf.read_bytes()[:64]
    if header[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", header, 18)[0] != 183:
        raise SystemExit("Not a little-endian AArch64 ELF64")
    entry = struct.unpack_from("<Q", header, 24)[0]
    if entry != 0x00100940:
        raise SystemExit(f"Unexpected entry: {entry:#x}")
    print("entry=0x00100940 sha256=" + hashlib.sha256(elf.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
