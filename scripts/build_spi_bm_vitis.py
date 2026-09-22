#!/usr/bin/env python3
import hashlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import vitis

SOURCE_MD5 = "ae45f51a3de4dfb0d184302d175cbd0b"
XSA_MD5 = "a698a18521c106272480b8ab260e886a"
FSBL_MD5 = "a31a3b023d380757d9c8255f633d5679"
PMUFW_MD5 = "34e313421653529b4956fb319f76a5d6"
TARGET_ADDRESS = 0x00100000
EXPECTED_ABI_DELTA = 352

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "bare_metal/src/spi_benchmark_bare_zynqmp.c"
XSA = ROOT / "hardware/xsa/spi_benchmark_wrapper.xsa"
WORKSPACE_PARENT = (ROOT / "bare_metal/vitis").resolve()
WORKSPACE = (WORKSPACE_PARENT / "spi_bm_repro_ws").resolve()
APP_SRC = WORKSPACE / "spi_bm_app/src"
ELF = WORKSPACE / "spi_bm_app/build/spi_bm_app.elf"

AMD_BIN = Path(
    os.environ.get(
        "AMD_AARCH64_BIN",
        "/home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1/"
        "gnu/aarch64/lin/aarch64-none/bin",
    )
)
READELF = AMD_BIN / "aarch64-none-elf-readelf"
NM = AMD_BIN / "aarch64-none-elf-nm"


def fail(message):
    raise RuntimeError(message)


def md5(path):
    digest = hashlib.md5()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_md5(path, expected, label):
    if not path.is_file():
        fail(f"{label} missing: {path}")
    actual = md5(path)
    if actual != expected:
        fail(f"{label} MD5 mismatch: expected {expected}, got {actual}")
    print(f"{label} MD5: {actual}")


def run_checked(command, cwd=ROOT, timeout=120):
    try:
        result = subprocess.run(
            [str(item) for item in command],
            cwd=str(cwd),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        fail(f"command timed out after {timeout}s: {' '.join(map(str, command))}")
    if result.returncode != 0:
        print(result.stdout, end="")
        fail(
            f"command failed with status {result.returncode}: "
            f"{' '.join(map(str, command))}"
        )
    return result.stdout


def verify_tools():
    vitis_launcher = shutil.which("vitis")
    if vitis_launcher is None:
        fail("vitis is not available on PATH")

    version = run_checked([vitis_launcher, "--version"], timeout=30)
    if "Vitis v2025.1" not in version:
        fail(f"expected Vitis v2025.1, got:\n{version}")

    for tool in (READELF, NM):
        if not tool.is_file() or not os.access(tool, os.X_OK):
            fail(f"required executable missing: {tool}")

    head = run_checked(["git", "rev-parse", "HEAD"], timeout=30).strip()
    readelf_version = run_checked([READELF, "--version"], timeout=30).splitlines()[0]
    nm_version = run_checked([NM, "--version"], timeout=30).splitlines()[0]

    print(f"Git HEAD: {head}")
    print(version.strip())
    print(f"Vitis launcher: {vitis_launcher}")
    print(f"Vitis Python module: {getattr(vitis, '__file__', 'unknown')}")
    print(f"readelf: {readelf_version}")
    print(f"nm: {nm_version}")


def clean_workspace():
    if WORKSPACE.parent != WORKSPACE_PARENT:
        fail(f"unsafe workspace parent: {WORKSPACE}")
    if WORKSPACE.name != "spi_bm_repro_ws":
        fail(f"unsafe workspace name: {WORKSPACE}")
    if WORKSPACE.is_symlink():
        fail(f"refusing to remove symlink workspace: {WORKSPACE}")
    if WORKSPACE.exists():
        print(f"Removing reproducible workspace: {WORKSPACE}")
        shutil.rmtree(WORKSPACE)
    WORKSPACE_PARENT.mkdir(parents=True, exist_ok=True)


def create_platform_and_app():
    client = vitis.create_client()
    try:
        client.set_workspace(path=str(WORKSPACE))
        client.create_platform_component(
            name="spi_bm_plat",
            hw_design=str(XSA),
            os="standalone",
            cpu="psu_cortexa53_0",
            domain_name="standalone_psu_cortexa53_0",
            no_boot_bsp=True,
            generate_dtb=True,
        )
        platform = client.get_component(name="spi_bm_plat")
        if platform is None:
            fail("Vitis did not return spi_bm_plat")
        result = platform.build()
        if result is False:
            fail("platform.build() returned False")

        xpfm = (
            WORKSPACE
            / "spi_bm_plat/export/spi_bm_plat/spi_bm_plat.xpfm"
        )
        if not xpfm.is_file():
            fail(f"platform build did not produce: {xpfm}")

        client.create_app_component(
            name="spi_bm_app",
            platform=(
                "$COMPONENT_LOCATION/../spi_bm_plat/export/"
                "spi_bm_plat/spi_bm_plat.xpfm"
            ),
            domain="standalone_psu_cortexa53_0",
            template="empty_application",
        )
    finally:
        vitis.dispose()


def install_source():
    if not APP_SRC.is_dir():
        fail(f"generated app source directory missing: {APP_SRC}")
    destination = APP_SRC / SOURCE.name
    shutil.copy2(SOURCE, destination)
    require_md5(destination, SOURCE_MD5, "Copied application source")


def patch_user_config():
    path = APP_SRC / "UserConfig.cmake"
    if not path.is_file():
        fail(f"missing generated UserConfig.cmake: {path}")

    text = path.read_text()
    empty_anchor = "set(USER_COMPILE_SOURCES\n)\n"
    replacement = (
        "set(USER_COMPILE_SOURCES\n"
        "\"spi_benchmark_bare_zynqmp.c\"\n"
        ")\n"
    )

    if text.count(empty_anchor) != 1:
        fail(
            "expected exactly one empty USER_COMPILE_SOURCES block; "
            "generated template differs"
        )
    if "spi_benchmark_bare_zynqmp.c" in text:
        fail("source already appears in generated UserConfig.cmake")

    updated = text.replace(empty_anchor, replacement, 1)
    if updated.count('"spi_benchmark_bare_zynqmp.c"') != 1:
        fail("USER_COMPILE_SOURCES post-patch count is not exactly one")

    path.write_text(updated)
    print("UserConfig.cmake source gate: PASS (exactly once)")


def patch_linker_script():
    path = APP_SRC / "lscript.ld"
    if not path.is_file():
        fail(f"missing generated linker script: {path}")

    lines = path.read_text().splitlines(keepends=True)
    pattern = re.compile(
        r"^(\s*psu_ddr_0_memory_0\s*:\s*ORIGIN\s*=\s*)"
        r"(0x[0-9a-fA-F]+)"
        r"(\s*,\s*LENGTH\s*=\s*)"
        r"(0x[0-9a-fA-F]+)"
        r"(\s*)$"
    )

    matches = []
    for index, line in enumerate(lines):
        body = line.rstrip("\r\n")
        match = pattern.fullmatch(body)
        if match:
            matches.append((index, line, match))

    if len(matches) != 1:
        fail(
            "expected exactly one psu_ddr_0_memory_0 ORIGIN/LENGTH "
            f"declaration, found {len(matches)}"
        )

    index, original_line, match = matches[0]
    if int(match.group(2), 16) != 0:
        fail(f"expected generated DDR ORIGIN 0x0, got {match.group(2)}")

    original_length = match.group(4)
    newline = original_line[len(original_line.rstrip("\r\n")):]
    lines[index] = (
        match.group(1)
        + "0x00100000"
        + match.group(3)
        + original_length
        + match.group(5)
        + newline
    )
    path.write_text("".join(lines))

    updated_line = lines[index].rstrip("\r\n")
    updated_match = pattern.fullmatch(updated_line)
    if updated_match is None:
        fail("linker line no longer matches guarded format")
    if int(updated_match.group(2), 16) != TARGET_ADDRESS:
        fail("linker ORIGIN post-patch verification failed")
    if updated_match.group(4) != original_length:
        fail("linker LENGTH changed unexpectedly")

    print(
        "Linker gate: PASS "
        f"(ORIGIN={updated_match.group(2)}, LENGTH={original_length})"
    )
    print(f"Linker-script MD5: {md5(path)}")


def build_application():
    client = vitis.create_client()
    try:
        client.set_workspace(path=str(WORKSPACE))
        component = client.get_component(name="spi_bm_app")
        if component is None:
            fail("Vitis did not return spi_bm_app")
        result = component.build()
        if result is False:
            fail("spi_bm_app build returned False")
    finally:
        vitis.dispose()

    if not ELF.is_file():
        fail(f"application build did not produce: {ELF}")


def verify_elf():
    header = run_checked([READELF, "-h", ELF], timeout=60)
    entry_match = re.search(
        r"Entry point address:\s*(0x[0-9a-fA-F]+)", header
    )
    if entry_match is None:
        fail("could not parse ELF entry point")
    entry = int(entry_match.group(1), 16)
    if entry != TARGET_ADDRESS:
        fail(f"entry point mismatch: expected 0x100000, got {entry_match.group(1)}")

    program_headers = run_checked([READELF, "-W", "-l", ELF], timeout=60)
    load_addresses = []
    for line in program_headers.splitlines():
        fields = line.split()
        if fields and fields[0] == "LOAD":
            if len(fields) < 4:
                fail(f"unexpected LOAD header format: {line}")
            load_addresses.append((int(fields[2], 16), int(fields[3], 16)))

    if not load_addresses:
        fail("ELF has no LOAD program headers")

    lowest_vaddr = min(address[0] for address in load_addresses)
    lowest_paddr = min(address[1] for address in load_addresses)
    if lowest_vaddr != TARGET_ADDRESS or lowest_paddr != TARGET_ADDRESS:
        fail(
            "lowest LOAD address mismatch: "
            f"vaddr=0x{lowest_vaddr:x}, paddr=0x{lowest_paddr:x}"
        )

    nm_output = run_checked([NM, "-n", ELF], timeout=60)
    wanted = {"results", "g_done", "ok_count", "err_count", "first_status"}
    found = {name: [] for name in wanted}

    for line in nm_output.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[-1] in wanted:
            try:
                address = int(fields[0], 16)
            except ValueError:
                continue
            found[fields[-1]].append(address)

    for name in sorted(wanted):
        if len(found[name]) != 1:
            fail(f"expected one defined {name} symbol, found {len(found[name])}")

    symbols = {name: addresses[0] for name, addresses in found.items()}
    delta = symbols["g_done"] - symbols["results"]
    if delta != EXPECTED_ABI_DELTA:
        fail(
            "legacy results[] ABI changed: "
            f"g_done-results={delta}, expected {EXPECTED_ABI_DELTA}"
        )

    print(f"Entry point: 0x{entry:x}")
    print(f"Lowest LOAD virtual address: 0x{lowest_vaddr:x}")
    print(f"Lowest LOAD physical address: 0x{lowest_paddr:x}")
    for name in ("results", "g_done", "ok_count", "err_count", "first_status"):
        print(f"{name:12s} = 0x{symbols[name]:x}")
    print(f"results -> g_done: {delta} bytes")
    print(f"ELF MD5: {md5(ELF)}")
    print(f"ELF path: {ELF}")
    print("ELF placement/symbol/ABI gates: PASS")


def package_if_requested():
    if os.environ.get("SPI_BM_PACKAGE", "0") != "1":
        print("Packaging skipped (set SPI_BM_PACKAGE=1 to enable).")
        return

    fsbl = ROOT / "sd-images/baremetal/fsbl_good.elf"
    pmufw = ROOT / "sd-images/baremetal/pmufw_good.elf"
    bif = ROOT / "sd-images/baremetal/bm_2e_hardened.bif"
    require_md5(fsbl, FSBL_MD5, "Historical FSBL")
    require_md5(pmufw, PMUFW_MD5, "Historical PMU firmware")

    expected_bif = (
        "the_ROM_image:\n"
        "{\n"
        "  [bootloader, destination_cpu=a53-0] fsbl_good.elf\n"
        "  [pmufw_image] pmufw_good.elf\n"
        "  [destination_cpu=a53-0, exception_level=el-3] "
        "spi_bm_app_2e_hardened.elf\n"
        "}\n"
    )
    if bif.read_text() != expected_bif:
        fail("tracked hardened BIF content differs from the proven structure")

    stage = (WORKSPACE_PARENT / "spi_bm_repro_package").resolve()
    if stage.parent != WORKSPACE_PARENT or stage.name != "spi_bm_repro_package":
        fail(f"unsafe packaging directory: {stage}")
    if stage.is_symlink():
        fail(f"refusing to remove symlink packaging directory: {stage}")
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)

    shutil.copy2(fsbl, stage / fsbl.name)
    shutil.copy2(pmufw, stage / pmufw.name)
    shutil.copy2(bif, stage / bif.name)
    staged_elf = stage / "spi_bm_app_2e_hardened.elf"
    shutil.copy2(ELF, staged_elf)
    if md5(staged_elf) != md5(ELF):
        fail("staged ELF hash mismatch")

    bootgen = shutil.which("bootgen")
    if bootgen is None:
        fail("SPI_BM_PACKAGE=1 but bootgen is unavailable on PATH")

    output = stage / "BOOT_2e_hardened_rebuilt.bin"
    run_checked(
        [
            bootgen,
            "-arch",
            "zynqmp",
            "-image",
            bif.name,
            "-o",
            output.name,
            "-w",
        ],
        cwd=stage,
        timeout=300,
    )
    if not output.is_file():
        fail("Bootgen did not produce the expected output")

    print(f"Packaged BOOT.BIN MD5: {md5(output)}")
    print(f"Packaged BOOT.BIN path: {output}")
    print("Historical tracked artifacts were not overwritten.")


def main():
    os.chdir(ROOT)
    print(f"Repository root: {ROOT}")
    require_md5(SOURCE, SOURCE_MD5, "Tracked source")
    require_md5(XSA, XSA_MD5, "Tracked XSA")
    verify_tools()
    clean_workspace()
    create_platform_and_app()
    install_source()
    patch_user_config()
    patch_linker_script()
    build_application()
    verify_elf()
    package_if_requested()
    print("Reproducible Vitis build automation: PASS")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"FATAL: {error}", file=sys.stderr)
        sys.exit(1)
