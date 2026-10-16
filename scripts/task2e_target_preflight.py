#!/usr/bin/env python3
"""Read-only UART preflight for Task 2e; never reads AXI SPI registers."""
from datetime import datetime, timezone
from pathlib import Path
import re
import sys
import time

import serial

ROOT = Path(__file__).resolve().parents[1]
PORT = "/dev/serial/by-id/usb-Silicon_Labs_CP2108_Quad_USB_to_UART_Bridge_Controller_B66A78CB12A648B611E661AF58A7182-if00-port0"
OUT = ROOT / "results/task2e_sustainable_runner_20261016/target_preflight.log"
COMMANDS = [
    "uname -a",
    "ldd --version 2>&1",
    "strings /lib/libc.so.6 2>&1 | grep ^GLIBC_ | sort -Vu | tail -5",
    "ls -l /lib/ld-linux-aarch64.so.1 2>&1",
    "cat /etc/os-release",
    "cat /proc/cmdline",
    "cat /sys/class/fpga_manager/fpga0/state 2>&1",
    "sha256sum /lib/firmware/msu2_ratio2_j55_c27bb684.bit.bin 2>&1",
    "ls -l /dev/spidev* 2>&1",
    "find /sys/bus/platform/devices -maxdepth 1 -name '*a0000000*' -print 2>&1",
    "find /sys/bus/spi/devices -maxdepth 3 -print 2>&1 | head -60",
    "cat /proc/interrupts | grep -i spi 2>&1",
    "cat /sys/module/spidev/parameters/bufsiz 2>&1",
    "for f in /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq; do echo $f; cat $f 2>&1; done",
    "cat /sys/kernel/debug/clk/clk_summary 2>&1 | grep -E 'iopll|pl0_ref'",
]


def read_for(port, seconds=0.25):
    end = time.monotonic() + seconds
    chunks = []
    while time.monotonic() < end:
        n = port.in_waiting
        if n:
            chunks.append(port.read(n))
        else:
            time.sleep(0.02)
    return b"".join(chunks)


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    collected = [f"HOST_UTC={datetime.now(timezone.utc).isoformat()}\nPORT={PORT}\n".encode()]
    with serial.Serial(PORT, 115200, timeout=0.1, write_timeout=3, exclusive=True) as ser:
        ser.dtr = False
        ser.rts = False
        collected.append(read_for(ser, 1.0))
        ser.write(b"\r")
        preamble = bytearray()
        deadline = time.monotonic() + 8
        prompt = re.compile(rb"(?:root@newQspi:~#|petalinux@newQspi:~\$|newQspi:~\$)\s*$")
        while time.monotonic() < deadline:
            b = ser.read(1024)
            if b:
                preamble.extend(b)
                if prompt.search(bytes(preamble[-256:])):
                    break
        else:
            collected.append(bytes(preamble))
            OUT.write_bytes(b"".join(collected))
            raise RuntimeError("A Linux shell prompt was not detected; no commands were sent.")
        collected.append(bytes(preamble))

        for index, command in enumerate(COMMANDS):
            marker = f"__MSU2_DONE_{index}__"
            collected.append(f"\nHOST_COMMAND[{index}]={command}\n".encode())
            ser.write(command.encode() + f"; printf '\\n{marker}\\n'\r".encode())
            data = bytearray()
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                part = ser.read(4096)
                if part:
                    data.extend(part)
                    # The marker is echoed as part of the typed input. Require
                    # the shell prompt after it, which appears only after printf ran.
                    if marker.encode() in data and re.search(rb"(?:root@newQspi:~#|petalinux@newQspi:~\$|newQspi:~\$)\s*$", data):
                        break
            collected.append(bytes(data))
            if marker.encode() not in data or not re.search(rb"(?:root@newQspi:~#|petalinux@newQspi:~\$|newQspi:~\$)\s*$", data):
                OUT.write_bytes(b"".join(collected))
                raise RuntimeError(f"Command {index} did not return to the shell prompt within 12 seconds")
    OUT.write_bytes(b"".join(collected))
    print(OUT)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
