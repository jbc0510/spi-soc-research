#!/usr/bin/env python3
"""Extract and audit a legacy U-Boot script for common FIT verification bypasses."""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

LEGACY_IMAGE_MAGIC = 0x27051956
HEADER_SIZE = 64


def extract_legacy_script(data: bytes) -> str:
    if len(data) >= HEADER_SIZE and struct.unpack_from(">I", data)[0] == LEGACY_IMAGE_MAGIC:
        size = struct.unpack_from(">I", data, 12)[0]
        if size > len(data) - HEADER_SIZE:
            raise ValueError("legacy U-Boot image data length exceeds file size")
        payload = data[HEADER_SIZE : HEADER_SIZE + size]
        # U-Boot legacy script images contain a sequence of big-endian script
        # lengths, terminated by zero, followed by the script text.
        if len(payload) >= 8:
            first_length = struct.unpack_from(">I", payload)[0]
            text_start = 4
            while text_start + 4 <= len(payload):
                length = struct.unpack_from(">I", payload, text_start)[0]
                text_start += 4
                if length == 0:
                    break
                text_start += length
            if text_start <= len(payload) and text_start > 4 and first_length > 0:
                data = payload[text_start:]
            else:
                data = payload
        else:
            data = payload
    return data.decode("utf-8", errors="strict").rstrip("\0\n")


def audit_script(script: str) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []
    checks = [
        ("raw-kernel-boot", "booti", "booti command can hand off a kernel outside FIT verification"),
        ("separate-kernel-path", "kernel_name", "separate raw kernel filename is referenced"),
        ("environment-import", "env import", "untrusted environment may redirect boot commands or filenames"),
        ("uenv-command", "uenvcmd", "external uEnv command can execute arbitrary boot policy"),
    ]
    lowered = script.lower()
    for code, token, explanation in checks:
        if token.lower() in lowered:
            findings.append({"code": code, "evidence": token, "description": explanation})
    if "bootm" not in lowered:
        findings.append({"code": "no-fit-boot", "evidence": "bootm absent", "description": "no FIT-capable bootm path was found"})
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    raw = args.input.read_bytes()
    script = extract_legacy_script(raw)
    report = {
        "input": str(args.input),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "script_bytes": len(script.encode("utf-8")),
        "findings": audit_script(script),
        "scope": "lexical audit; does not emulate U-Boot command execution",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
