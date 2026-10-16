#!/usr/bin/env python3
"""Isolated Vitis 2025.1 AXI build. No boot packaging or historical writes.

Run with system Python. A separate Vitis worker and its process group have a
hard wall-clock limit. An existing workspace is refused, never removed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
XSA = ROOT / "results/ratio2_j55_lvcmos33_20260929/spi_ratio2_j55_wrapper.xsa"
DEFAULT_SOURCE = ROOT / "bare_metal/src/spi_benchmark_bare_axi.c"
SOURCE = DEFAULT_SOURCE
CONTRACT = ROOT / "common/spi_benchmark_contract.h"
XSA_SHA256 = "e8b4626edb5949bc8adb14ae259802cdd24b16ea3f02daf0dd8fdbeb1cc0e7d7"
BIT_SHA256 = "90f93479dd47c505b8f9e4fe6f4f18e853f8923d081f4b2037401ed3cb46994a"
PLATFORM = "spi_axi_bm_plat"
APP = "spi_axi_bm_app"
DOMAIN = "standalone_psu_cortexa53_0"
ENTRY = 0x100000


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args, cwd=ROOT):
    env = dict(os.environ)
    env.setdefault("XILINX_VITIS_DATA_DIR", str(ROOT / ".build/vitis_cli_config"))
    Path(env["XILINX_VITIS_DATA_DIR"]).mkdir(parents=True, exist_ok=True)
    return subprocess.check_output([str(x) for x in args], cwd=cwd,
                                   env=env, text=True, stderr=subprocess.STDOUT, timeout=90)


def inspect_xsa():
    require(sha(XSA) == XSA_SHA256, "Pinned XSA SHA-256 mismatch")
    with zipfile.ZipFile(XSA) as archive:
        require(hashlib.sha256(archive.read("spi_ratio2_j55_wrapper.bit")).hexdigest()
                == BIT_SHA256, "Embedded bitstream hash mismatch")
        root = ET.fromstring(archive.read("spi_benchmark.hwh"))
    modules = [m for m in root.iter("MODULE")
               if m.get("INSTANCE") == "axi_quad_spi_0"]
    require(len(modules) == 1, "Expected exactly one axi_quad_spi_0")
    require(modules[0].get("VLNV") == "xilinx.com:ip:axi_quad_spi:3.2",
            "Unexpected AXI Quad SPI IP")
    params = {p.get("NAME"): p.get("VALUE")
              for p in modules[0].find("PARAMETERS")}
    expected = {"C_BASEADDR": 0xA0000000, "C_HIGHADDR": 0xA000FFFF,
                "C_SPI_MODE": 0, "C_NUM_TRANSFER_BITS": 8, "C_NUM_SS_BITS": 1,
                "C_FIFO_DEPTH": 256, "C_SCK_RATIO": 2,
                "C_TYPE_OF_AXI4_INTERFACE": 0, "C_XIP_MODE": 0,
                "Master_mode": 1, "FIFO_INCLUDED": 1}
    for key, value in expected.items():
        require(key in params and int(params[key], 0) == value,
                f"Missing/unexpected XSA parameter {key}")
    return params


def replace_once(path, before, after):
    data = path.read_text()
    require(data.count(before) == 1, f"Generated template mismatch: {path}: {before!r}")
    path.write_text(data.replace(before, after, 1))


def worker():
    import vitis  # available only under the Vitis launcher
    source = Path(os.environ.get("SPI_AXI_SOURCE", str(SOURCE))).resolve()
    ws = Path(os.environ["SPI_AXI_WORKSPACE"]).resolve()
    client = vitis.create_client()
    try:
        client.set_workspace(path=str(ws))
        client.create_platform_component(name=PLATFORM, hw_design=str(XSA),
                                        os="standalone", cpu="psu_cortexa53_0",
                                        domain_name=DOMAIN, no_boot_bsp=True,
                                        generate_dtb=True)
        require(client.get_component(name=PLATFORM).build() is not False,
                "Platform build failed")
        bsp = ws / PLATFORM / "psu_cortexa53_0" / DOMAIN / "bsp"
        meta = (bsp / "bsp.yaml").read_text()
        require(re.search(r"axi_quad_spi_0:\s+driver: spi\s", meta) is not None,
                "Generated BSP does not bind axi_quad_spi_0 to spi")
        xp = (bsp / "include/xparameters.h").read_text()
        for name, value in {"BASEADDR": 0xA0000000, "HIGHADDR": 0xA000FFFF,
                            "BITS_PER_WORD": 8, "NUM_SS_BITS": 1,
                            "SPI_MODE": 0, "FIFO_SIZE": 256,
                            "SLAVEONLY": 0, "AXI_INTERFACE": 0}.items():
            match = re.search(r"^#define XPAR_XSPI_0_" + name + r"\s+(\S+)", xp, re.M)
            require(match is not None and int(match[1], 0) == value,
                    f"Missing/unexpected generated XSpi {name}")
        spi_driver = bsp / "libsrc/spi/src"
        for name in ("xspi.c", "xspi.h", "xspi_g.c", "xspi_sinit.c"):
            require((spi_driver / name).is_file(), f"Missing XSpi driver file {name}")
        require("0xa0000000" in (spi_driver / "xspi_g.c").read_text().lower(),
                "XSpi config table lacks target base")

        irq = re.search(r"^#define XPAR_FABRIC_XSPI_0_INTR\s+(\S+)", xp, re.M)
        require(irq is not None and int(irq[1], 0) == 89,
                "Missing/unexpected AXI Quad SPI interrupt ID")
        gic_base = re.search(r"^#define XPAR_XSCUGIC_0_BASEADDR\s+(\S+)", xp, re.M)
        require(gic_base is not None and int(gic_base[1], 0) == 0xF9010000,
                "Missing/unexpected GIC distributor base")

        gic_driver = bsp / "libsrc/scugic/src"
        for name in ("xscugic.c", "xscugic.h", "xscugic_intr.c", "xscugic_sinit.c"):
            require((gic_driver / name).is_file(), f"Missing XScuGic driver file {name}")
        client.create_app_component(name=APP,
                                    platform=str(ws / PLATFORM / "export" / PLATFORM /
                                                 (PLATFORM + ".xpfm")),
                                    domain=DOMAIN, template="empty_application")
        src = ws / APP / "src"
        shutil.copy2(source, src / source.name)
        shutil.copy2(CONTRACT, src / CONTRACT.name)
        uc = src / "UserConfig.cmake"
        replace_once(uc, "set(USER_COMPILE_SOURCES\n)\n",
                     f'set(USER_COMPILE_SOURCES\n"{source.name}"\n)\n')
        replace_once(uc, "set(USER_LINK_LIBRARIES\n)", "set(USER_LINK_LIBRARIES\nm\n)")
        replace_once(uc, "set(USER_COMPILE_OPTIMIZATION_LEVEL -O0)",
                     "set(USER_COMPILE_OPTIMIZATION_LEVEL -O2)")
        ld = src / "lscript.ld"
        data = ld.read_text()
        pattern = r"(psu_ddr_0_memory_0\s*:\s*ORIGIN\s*=\s*)(0x[0-9a-fA-F]+)(\s*,\s*LENGTH\s*=\s*)(0x[0-9a-fA-F]+)"
        matches = list(re.finditer(pattern, data))
        require(len(matches) == 1, "Expected one DDR linker region")
        match = matches[0]
        require(int(match[2], 16) == 0 and int(match[4], 16) > ENTRY,
                "Unexpected generated DDR range")
        # Move origin while preserving the original region's upper bound.
        data = re.sub(pattern, lambda m: m[1] + hex(ENTRY) + m[3] +
                      hex(int(m[4], 16) - ENTRY), data)
        ld.write_text(data)
        require(client.get_component(name=APP).build() is not False,
                "Application build failed")
        files = [bsp / "bsp.yaml", bsp / "include/xparameters.h", uc, ld,
                 src / source.name, src / CONTRACT.name]
        files += list(spi_driver.glob("*.c")) + list(spi_driver.glob("*.h"))
        files += list(gic_driver.glob("*.c")) + list(gic_driver.glob("*.h"))
        (ws / "generated_hashes.json").write_text(json.dumps(
            {str(p.relative_to(ws)): sha(p) for p in files}, indent=2) + "\n")
    finally:
        vitis.dispose()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument("--workspace-name", default="spi_axi_bm_ws")
    parser.add_argument("--source", default=str(DEFAULT_SOURCE.relative_to(ROOT)),
                        help="application C source relative to the repository root")
    args = parser.parse_args()
    require(1 <= args.timeout_seconds <= 300, "Build limit must be 1..300 seconds")
    require(re.fullmatch(r"spi_axi_bm_[A-Za-z0-9_]+", args.workspace_name),
            "Workspace name must start spi_axi_bm_ and contain only letters/digits/underscore")
    global SOURCE
    SOURCE = (ROOT / args.source).resolve()
    require(SOURCE.is_relative_to(ROOT) and SOURCE.is_file(),
            "Application source must be an existing repository file")
    ws = ROOT / "bare_metal/vitis" / args.workspace_name
    require(not ws.exists() and not ws.is_symlink(), "Workspace exists; refusing to overwrite it")
    params = inspect_xsa()
    launcher = shutil.which("vitis")
    require(launcher is not None, "vitis unavailable on PATH")
    version = command([launcher, "--version"])
    require("Vitis v2025.1" in version, "Vitis 2025.1 required")
    bindir = Path(os.environ.get("AMD_AARCH64_BIN",
        "/home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1/gnu/aarch64/lin/aarch64-none/bin"))
    readelf, nm = bindir / "aarch64-none-elf-readelf", bindir / "aarch64-none-elf-nm"
    for tool in (readelf, nm):
        require(tool.is_file(), f"Missing tool: {tool}")
    manifest = {"validation": "BUILD_ONLY_NOT_HARDWARE", "common_pair": "RECONCILED_TO_RATIO2_J55_LVCMOS33_VALIDATED_HARDWARE",
                "git_head": command(["git", "rev-parse", "HEAD"]).strip(),
                "git_status": command(["git", "--no-optional-locks", "status", "--short"]),
                "vitis_version": version, "xsa_sha256": sha(XSA),
                "embedded_bit_sha256": BIT_SHA256, "source_sha256": sha(SOURCE),
                "contract_sha256": sha(CONTRACT), "build_script_sha256": sha(Path(__file__)),
                "xsa_parameters": params,
                "transfer_mode": ("XSpi interrupt mode with bounded software deadline"
                                  if SOURCE.name == "spi_benchmark_bare_axi.c" else
                                  "XSpi interrupt mode with bounded deadline; stop on first sustained-point error"),
                "transfer_timeout_ms": 2000,
                "timeout_recovery": ("XSpi_Reset then reconfigure/restart"
                                     if SOURCE.name == "spi_benchmark_bare_axi.c" else
                                     "Stop the sustained run without retry"),
                "hardware_timeout_validation": "NOT_PERFORMED",
                "timeout_seconds": args.timeout_seconds, "packaging": "NOT_IMPLEMENTED"}
    ws.mkdir(parents=True)
    (ws / "input_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    # Vitis requires a new/empty workspace; keep logs/configuration outside it.
    env = dict(os.environ, SPI_AXI_BUILD_WORKER="1", SPI_AXI_SOURCE=str(SOURCE),
               SPI_AXI_WORKSPACE=str(ws / "workspace"),
               XILINX_VITIS_DATA_DIR=str(ws / "vitis_config"))
    started = time.monotonic()
    with (ws / "build.log").open("w") as log:
        proc = subprocess.Popen([launcher, "-s", str(Path(__file__).resolve())],
                                cwd=ws, env=env, stdout=log, stderr=subprocess.STDOUT,
                                start_new_session=True)
        try:
            rc = proc.wait(timeout=args.timeout_seconds)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            raise RuntimeError(f"Hard build timeout; inspect {ws / 'build.log'}")
    require(rc == 0, f"Vitis failed ({rc}); inspect {ws / 'build.log'}")
    elf = ws / "workspace" / APP / "build" / (APP + ".elf")
    require(elf.is_file(), f"Missing application ELF; inspect {ws / 'build.log'} (launcher can return 0 on failure)")
    header = command([readelf, "-h", elf])
    entry = re.search(r"Entry point address:\s*(0x[0-9a-fA-F]+)", header)
    require(entry is not None and int(entry[1], 16) == ENTRY, "Unexpected ELF entry")
    require("AArch64" in header, "Expected AArch64 ELF")
    loads = [line.split() for line in command([readelf, "-W", "-l", elf]).splitlines()
             if line.strip().startswith("LOAD ")]
    require(loads and min(int(line[2], 16) for line in loads) == ENTRY and
            min(int(line[3], 16) for line in loads) == ENTRY, "Unexpected ELF LOAD placement")
    symbols = command([nm, "-n", elf])
    required_symbols = (("main", "axi_results", "axi_done")
                        if SOURCE.name == "spi_benchmark_bare_axi.c" else ("main",))
    required_symbols += (
                 "XSpi_Transfer", "XSpi_CfgInitialize", "XSpi_InterruptHandler",
                 "XScuGic_Connect", "XScuGic_InterruptHandler")
    if SOURCE.name == "spi_benchmark_bare_axi.c":
        required_symbols += ("XSpi_Reset",)
    for name in required_symbols:
        require(re.search(r"^[0-9a-fA-F]+\s+[A-Za-z]\s+" + name + r"$", symbols, re.M),
                f"Missing ELF symbol {name}")
    manifest.update(elf_sha256=sha(elf), elapsed_seconds=time.monotonic() - started,
                    elf_header=header, symbols=symbols,
                    compiler_comment=command([readelf, "-p", ".comment", elf]),
                    result="BUILD_PASS_NOT_HARDWARE_VALIDATION")
    (ws / "build_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"BUILD PASS ONLY: {elf}\nSHA-256: {sha(elf)}\nManifest: {ws / 'build_manifest.json'}")
    print("No boot image packaged. XSA reconciled to validated ratio-2 J55 LVCMOS33 hardware.")


if __name__ == "__main__":
    try:
        if os.environ.get("SPI_AXI_BUILD_WORKER") == "1":
            worker()
        else:
            main()
    except Exception as error:
        print(f"FATAL: {error}", file=sys.stderr)
        sys.exit(1)
