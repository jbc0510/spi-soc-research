#!/usr/bin/env python3
"""Compare a Xilinx .bit payload with the word-byte-swapped .bit.bin form."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def extract_payload(bit: bytes) -> bytes:
    if len(bit) < 16 or int.from_bytes(bit[:2], "big") != 9:
        raise ValueError("not a recognized Xilinx .bit header")
    offset = 2 + int.from_bytes(bit[:2], "big")
    if bit[offset : offset + 2] != b"\0\1":
        raise ValueError("missing Xilinx .bit field marker")
    offset += 2
    for tag in b"abcd":
        if offset + 3 > len(bit) or bit[offset] != tag:
            raise ValueError(f"missing Xilinx .bit metadata field {chr(tag)}")
        size = int.from_bytes(bit[offset + 1 : offset + 3], "big")
        offset += 3 + size
    if offset + 5 > len(bit) or bit[offset] != ord("e"):
        raise ValueError("missing Xilinx .bit payload field")
    size = int.from_bytes(bit[offset + 1 : offset + 5], "big")
    offset += 5
    payload = bit[offset : offset + size]
    if len(payload) != size or offset + size != len(bit):
        raise ValueError("Xilinx .bit payload length does not match file")
    if size % 4:
        raise ValueError("Xilinx .bit payload length is not 32-bit word aligned")
    return payload


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def reverse_word_bytes(payload: bytes) -> bytes:
    if len(payload) % 4:
        raise ValueError("payload length is not 32-bit word aligned")
    return b"".join(payload[i : i + 4][::-1] for i in range(0, len(payload), 4))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bit", required=True, type=Path)
    parser.add_argument("--bit-bin", required=True, type=Path)
    args = parser.parse_args()
    bit = args.bit.read_bytes()
    bit_bin = args.bit_bin.read_bytes()
    payload = extract_payload(bit)
    wordswapped = reverse_word_bytes(payload)
    result = {
        "bit_file": str(args.bit),
        "bit_sha256": sha(bit),
        "payload_bytes": len(payload),
        "payload_sha256": sha(payload),
        "bit_bin_file": str(args.bit_bin),
        "bit_bin_bytes": len(bit_bin),
        "bit_bin_sha256": sha(bit_bin),
        "word_bytes_reversed_payload_matches_bit_bin": wordswapped == bit_bin,
        "claim_boundary": "Compares two local artifact encodings; target identity is supported separately by the captured board dmesg filename and firmware-file hash.",
    }
    print(json.dumps(result, indent=2))
    return 0 if wordswapped == bit_bin else 1


if __name__ == "__main__":
    raise SystemExit(main())
