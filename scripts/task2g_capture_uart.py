#!/usr/bin/env python3
"""Capture ZCU102 UART bytes without transmitting or changing board state."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
import sys
import time

try:
    import serial
except ImportError as exc:  # pragma: no cover - environment diagnostic
    raise SystemExit("pyserial is required: python3 -m pip install pyserial") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--port",
        default="/dev/serial/by-id/usb-Silicon_Labs_CP2108_Quad_USB_to_UART_Bridge_Controller_B66A78CB12A648B611E661AF58A7182-if00-port0",
    )
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=60.0)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("results/task2g_card_bootrom_diagnostic_20261017"),
    )
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    raw_path = args.output_dir / f"uart_post_fat_repair_{stamp}.bin"
    text_path = args.output_dir / f"uart_post_fat_repair_{stamp}.txt"

    try:
        with serial.Serial(
            port=None,
            baudrate=args.baud,
            timeout=0.1,
            exclusive=True,
        ) as uart:
            uart.dtr = False
            uart.rts = False
            uart.port = args.port
            uart.open()
            print(
                f"CAPTURE_ACTIVE port={args.port} baud={args.baud} seconds={args.seconds}",
                flush=True,
            )
            deadline = time.monotonic() + args.seconds
            captured = bytearray()
            while time.monotonic() < deadline:
                chunk = uart.read(4096)
                if chunk:
                    captured.extend(chunk)
    except (OSError, serial.SerialException) as exc:
        print(f"UART capture failed: {exc}", file=sys.stderr)
        return 2

    raw_path.write_bytes(captured)
    text_path.write_text(captured.decode("utf-8", errors="backslashreplace"))
    print(f"port={args.port} baud={args.baud} duration_s={args.seconds}")
    print(f"bytes={len(captured)}")
    print(f"raw={raw_path}")
    print(f"text={text_path}")
    print("tail_repr=" + repr(bytes(captured[-512:])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
