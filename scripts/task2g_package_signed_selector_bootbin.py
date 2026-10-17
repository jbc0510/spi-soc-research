#!/usr/bin/env python3
"""Package the signed-selector ZynqMP BOOT.BIN with Bootgen-safe inputs.

The PL source must be an original Xilinx .bit file. Do not pass the
byte-swapped .bit.bin used by Linux FPGA-manager flows: Bootgen may then emit
an incorrect PL load address and an overlapping PS address range.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def run(args: list[str], *, cwd: Path | None = None) -> str:
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(args)}\n{result.stdout}")
    return result.stdout


def parse_pl_header(report: str) -> tuple[str, str]:
    start = re.search(r"PARTITION HEADER TABLE \([^\n]*\.bit\.0\)", report)
    if not start:
        raise RuntimeError("Bootgen readback did not contain the expected PL .bit partition")
    next_header = re.search(r"\n\s*PARTITION HEADER TABLE \(", report[start.end():])
    end = start.end() + next_header.start() if next_header else len(report)
    section = report[start.end():end]
    load = re.search(r"load_addr_lo \(0x18\)\s*:\s*(0x[0-9a-fA-F]+)", section)
    length = re.search(r"unencrypted_length \(0x04\)\s*:\s*(0x[0-9a-fA-F]+)", section)
    if not load or not length or "dest_device [PL]" not in section:
        raise RuntimeError("Bootgen readback PL destination/load/length fields were incomplete")
    return load.group(1).lower(), length.group(1).lower()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootgen", required=True, type=Path)
    parser.add_argument("--fsbl", required=True, type=Path)
    parser.add_argument("--pmufw", required=True, type=Path)
    parser.add_argument("--bit", required=True, type=Path,
                        help="Original Xilinx .bit file, not the Linux .bit.bin form")
    parser.add_argument("--bl31", required=True, type=Path)
    parser.add_argument("--system-dtb", required=True, type=Path)
    parser.add_argument("--uboot", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--bit-bin-reference", type=Path,
                        help="Optional word-byte-swapped .bit.bin to verify equivalence")
    args = parser.parse_args()

    paths = [args.bootgen, args.fsbl, args.pmufw, args.bit, args.bl31,
             args.system_dtb, args.uboot]
    for path in paths:
        if not path.is_file():
            parser.error(f"input file does not exist: {path}")
        if any(char.isspace() for char in str(path.resolve())):
            parser.error(f"Bootgen BIF paths cannot contain whitespace: {path}")
    if args.bit.suffix != ".bit":
        parser.error("--bit must name the original Xilinx .bit file (not .bit.bin)")
    if args.bit_bin_reference and not args.bit_bin_reference.is_file():
        parser.error(f"bitstream reference does not exist: {args.bit_bin_reference}")

    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    bif = out / "bootgen-signed-selector.bif"
    candidate = out / "BOOT_SIGNED_SELECTOR.bin"
    build_log = out / "bootgen_package_build.log"
    read_log = out / "bootgen_read_candidate.log"
    summary_path = out / "bootgen_package_summary.json"

    bif.write_text(
        "the_ROM_image:\n{\n"
        f"  [bootloader, destination_cpu=a53-0] {args.fsbl.resolve()}\n"
        f"  [destination_cpu=pmu] {args.pmufw.resolve()}\n"
        f"  [destination_device=pl] {args.bit.resolve()}\n"
        f"  [destination_cpu=a53-0, exception_level=el-3, trustzone] {args.bl31.resolve()}\n"
        f"  [destination_cpu=a53-0, load=0x100000] {args.system_dtb.resolve()}\n"
        f"  [destination_cpu=a53-0, exception_level=el-2] {args.uboot.resolve()}\n"
        "}\n",
        encoding="utf-8",
    )
    build_output = run([str(args.bootgen.resolve()), "-arch", "zynqmp", "-image",
                        str(bif), "-o", str(candidate), "-w"])
    build_log.write_text(build_output, encoding="utf-8")
    if "overlapped with partition" in build_output.lower():
        raise RuntimeError("Bootgen reported an overlapping partition range; refusing candidate")

    read_output = run([str(args.bootgen.resolve()), "-arch", "zynqmp", "-read",
                       str(candidate)])
    read_log.write_text(read_output, encoding="utf-8")
    pl_load, pl_length_words = parse_pl_header(read_output)
    if pl_load != "0xffffffff":
        raise RuntimeError(f"unexpected PL load address {pl_load}; expected 0xffffffff")

    bit_size = args.bit.stat().st_size
    expected_words = (bit_size - bit_payload_offset(args.bit)) // 4
    if int(pl_length_words, 16) != expected_words:
        raise RuntimeError(
            f"PL partition length {pl_length_words} does not match .bit payload word count {hex(expected_words)}"
        )

    result = {
        "candidate": str(candidate),
        "candidate_sha256": sha256(candidate),
        "bif": str(bif),
        "bit_source": str(args.bit.resolve()),
        "bit_sha256": sha256(args.bit),
        "bit_size_bytes": bit_size,
        "pl_partition_load_address": pl_load,
        "pl_partition_length_words": pl_length_words,
        "bootgen_overlap_warning": False,
        "pmufw_bif_form": "destination_cpu=pmu",
    }
    if args.bit_bin_reference:
        result["bit_bin_reference"] = str(args.bit_bin_reference.resolve())
        result["bit_bin_reference_sha256"] = sha256(args.bit_bin_reference)
        result["word_byte_swapped_payload_match"] = compare_bit_payloads(
            args.bit, args.bit_bin_reference
        )
        if not result["word_byte_swapped_payload_match"]:
            raise RuntimeError(".bit payload does not match the supplied .bit.bin reference")
    summary_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0


def bit_payload_offset(path: Path) -> int:
    data = path.read_bytes()
    if len(data) < 16 or int.from_bytes(data[:2], "big") != 9:
        raise RuntimeError(f"not a recognized Xilinx .bit file: {path}")
    offset = 2 + int.from_bytes(data[:2], "big")
    if data[offset:offset + 2] != b"\0\1":
        raise RuntimeError(f"invalid Xilinx .bit field marker: {path}")
    offset += 2
    for tag in b"abcd":
        if offset + 3 > len(data) or data[offset] != tag:
            raise RuntimeError(f"invalid Xilinx .bit metadata field {chr(tag)}")
        offset += 3 + int.from_bytes(data[offset + 1:offset + 3], "big")
    if offset + 5 > len(data) or data[offset] != ord("e"):
        raise RuntimeError("missing Xilinx .bit payload marker")
    payload_size = int.from_bytes(data[offset + 1:offset + 5], "big")
    offset += 5
    if offset + payload_size != len(data) or payload_size % 4:
        raise RuntimeError("Xilinx .bit payload size is invalid or not word-aligned")
    return offset


def compare_bit_payloads(bit_path: Path, bit_bin_path: Path) -> bool:
    data = bit_path.read_bytes()
    offset = bit_payload_offset(bit_path)
    payload = data[offset:]
    expected = b"".join(payload[i:i + 4][::-1] for i in range(0, len(payload), 4))
    return expected == bit_bin_path.read_bytes()


if __name__ == "__main__":
    raise SystemExit(main())
