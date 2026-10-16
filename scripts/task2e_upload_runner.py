#!/usr/bin/env python3
"""Upload the Task 2e Linux runner to volatile target /tmp over UART."""
import base64
import hashlib
from pathlib import Path
import re
import sys
import time

import serial

ROOT = Path(__file__).resolve().parents[1]
PORT = "/dev/serial/by-id/usb-Silicon_Labs_CP2108_Quad_USB_to_UART_Bridge_Controller_B66A78CB12A648B611E661AF58A7182-if00-port0"
BINARY = ROOT / "results/task2e_sustainable_runner_20261016/spi_sustainable_benchmark_linux_aarch64"
OUT = ROOT / "results/task2e_sustainable_runner_20261016/target_upload.log"
DEST = "/tmp/spi_sustainable_benchmark_linux_aarch64"
ROOT_PROMPT = rb"root@newQspi:~#\s*$"


def read_until(ser, pattern, timeout=15):
    data = bytearray()
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        part = ser.read(4096)
        if part:
            data.extend(part)
            if re.search(pattern, data):
                return bytes(data)
    raise TimeoutError(bytes(data[-10000:]).decode("utf-8", "replace"))


def main():
    blob = BINARY.read_bytes()
    digest = hashlib.sha256(blob).hexdigest()
    encoded = base64.b64encode(blob).decode("ascii")
    chunks = [encoded[i:i + 76] for i in range(0, len(encoded), 76)]
    transcript = [f"binary={BINARY}\nbytes={len(blob)}\nsha256={digest}\n".encode()]
    with serial.Serial(PORT, 115200, timeout=0.15, write_timeout=30, exclusive=True) as ser:
        ser.dtr = False
        ser.rts = False
        ser.write(b"\r")
        data = read_until(ser, rb"(?:root@newQspi:~#|petalinux@newQspi:~\$|newQspi:~\$)\s*$")
        transcript.append(data)
        if not re.search(ROOT_PROMPT, data):
            raise PermissionError("Target shell is not root; refusing to attempt privileged access or upload")
        # The marker proves the receiver is running before file bytes are sent.
        ser.write(f"stty -echo; echo __UPLOAD_READY__; base64 -d > {DEST}\r".encode())
        transcript.append(read_until(ser, rb"__UPLOAD_READY__\r?\n", timeout=8))
        for line in chunks:
            ser.write(line.encode() + b"\r")
            time.sleep(0.001)
        ser.write(b"\x04")
        transcript.append(read_until(ser, ROOT_PROMPT, timeout=20))
        ser.write(b"stty echo; chmod 755 " + DEST.encode() + b"; sha256sum " + DEST.encode() + b"; " + DEST.encode() + b" 2>&1 | head -2; printf '\\n__UPLOAD_VERIFY_DONE__\\n'\r")
        transcript.append(read_until(ser, rb"__UPLOAD_VERIFY_DONE__.*root@newQspi:~#\s*$", timeout=20))
    OUT.write_bytes(b"".join(transcript))
    print(f"{OUT}\nexpected_sha256={digest}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
