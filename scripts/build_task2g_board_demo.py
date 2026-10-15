#!/usr/bin/env python3
"""Embed the signed test vector and cross-build the ZCU102 Linux demo."""

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "results/task2g_board_contrast_20261015"
BUILD = ROOT / ".build/task2g_board"
SOURCE = ROOT / "linux/appliance/hardening_contrast_board.c"
CC = os.environ.get(
    "AARCH64_GCC",
    "/home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-gcc",
)


def byte_array(name, data):
    values = [f"0x{value:02x}" for value in data]
    lines = [", ".join(values[i:i + 12]) for i in range(0, len(values), 12)]
    return f"static const unsigned char {name}[] = {{\n    " + ",\n    ".join(lines) + "\n};\n"


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    payload = (EVIDENCE / "release_fixture.bin").read_bytes()
    signature = (EVIDENCE / "release_fixture.sig").read_bytes()
    public_key = (EVIDENCE / "test_public.pem").read_text()
    escaped_key = "\\n".join(
        line.replace("\\", "\\\\").replace('"', '\\"')
        for line in public_key.splitlines()
    ) + "\\n"
    header = (
        "#ifndef MSU2_BOARD_TEST_VECTOR_H\n#define MSU2_BOARD_TEST_VECTOR_H\n"
        + byte_array("board_payload", payload)
        + f'static const char board_public_key[] = "{escaped_key}";\n'
        + byte_array("board_signature", signature)
        + "#endif\n"
    )
    header_path = BUILD / "board_test_vector.h"
    header_path.write_text(header)
    output = EVIDENCE / "hardening_contrast_board_aarch64"
    command = [CC, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
               "-D_FORTIFY_SOURCE=2", "-I", str(BUILD), str(SOURCE), "-ldl", "-o", str(output)]
    subprocess.run(command, check=True)
    print(f"built={output}")
    print(f"compiler={CC}")
    print(f"bytes={output.stat().st_size}")


if __name__ == "__main__":
    main()
