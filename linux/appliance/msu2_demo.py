#!/usr/bin/env python3
"""MSU-2 ZCU102 Linux demo console.

One operator entry point for the Linux SPI checks. Each run gets a unique
directory containing the selected configuration, raw output, and a manifest.
Bare-metal is a separate A53 boot mode and is intentionally not represented as
a Linux submenu action.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
PAYLOADS = (1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536)
DEFAULT_DEVICE = "/dev/spidev1.0"


def sha256(path: Path) -> str | None:
    try:
        h = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                h.update(block)
        return h.hexdigest()
    except OSError:
        return None


def read_text(path: str) -> str | None:
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


def system_info(device: str) -> dict:
    return {
        "hostname": platform.node(),
        "kernel": platform.release(),
        "kernel_version": platform.version(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "device": device,
        "device_present": Path(device).exists(),
        "cpuinfo_model": next((line.split(":", 1)[1].strip()
                               for line in (read_text("/proc/cpuinfo") or "").splitlines()
                               if line.lower().startswith("model name")), None),
        "cpu_freq_khz": read_text("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"),
        "spidev_bufsiz": read_text("/sys/module/spidev/parameters/bufsiz"),
        "spi_device_driver": os.path.realpath(f"/sys/class/spidev/{Path(device).name}/device/driver")
                            if Path(f"/sys/class/spidev/{Path(device).name}/device/driver").exists()
                            else None,
        "physical_sck_hz": "NOT_MEASURED_BY_THIS_PROGRAM",
        "pl0_clock_hz": "NOT_READ_BY_THIS_PROGRAM",
        "bitstream_sha256": "NOT_VERIFIED_BY_THIS_PROGRAM",
    }


def parse_list(value: str) -> list[int]:
    try:
        values = [int(item.strip(), 10) for item in value.split(",")]
    except ValueError as exc:
        raise ValueError("payload list must be comma-separated decimal sizes") from exc
    if not values or len(set(values)) != len(values) or any(n not in PAYLOADS for n in values):
        raise ValueError(f"payload sizes must be unique members of {PAYLOADS}")
    return values


class Demo:
    def __init__(self, device=DEFAULT_DEVICE, result_root=None, binaries=None):
        self.device = device
        self.result_root = Path(result_root or os.environ.get(
            "MSU2_DEMO_RESULTS", str(Path.home() / "msu2-demo-results")))
        self.binaries = binaries or {
            "integrity": Path(os.environ.get("MSU2_INTEGRITY_BIN", "/usr/bin/spi_benchmark_v3_rxverify")),
            "sustained": Path(os.environ.get("MSU2_SUSTAINED_BIN", "/usr/bin/spi_sustainable_benchmark")),
        }

    def new_run(self, test: str, config: dict) -> Path:
        self.result_root.mkdir(parents=True, exist_ok=True)
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        base = self.result_root / f"{stamp}_{test}"
        run_dir = base
        suffix = 1
        while run_dir.exists():
            suffix += 1
            run_dir = Path(f"{base}_{suffix:02d}")
        run_dir.mkdir()
        (run_dir / "config.json").write_text(json.dumps(config, indent=2) + "\n")
        return run_dir

    def execute(self, test: str, config: dict, command: list[str]) -> int:
        binary = Path(command[0])
        if not binary.is_file():
            print(f"Missing test program: {binary}\nInstall the demo binaries using linux/appliance/build_demo.sh.", file=sys.stderr)
            return 2
        run_dir = self.new_run(test, config)
        started = dt.datetime.now(dt.timezone.utc)
        started_ns = time.time_ns()
        try:
            completed = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, check=False)
            output = completed.stdout
            code = completed.returncode
        except OSError as exc:
            output = f"launcher_error={exc}\n"
            code = 127
        (run_dir / "raw_output.log").write_text(output)
        manifest = {
            "schema": "msu2-demo-run-v1", "test": test,
            "started_utc": started.isoformat(),
            "finished_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "elapsed_wall_s": (time.time_ns() - started_ns) / 1e9,
            "command": command, "exit_code": code,
            "system": system_info(self.device),
            "program_sha256": sha256(binary),
            "raw_output_sha256": sha256(run_dir / "raw_output.log"),
        }
        (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(output, end="" if output.endswith("\n") or not output else "\n")
        print(f"\nRun evidence: {run_dir}\nResult: {'PASS' if code == 0 else 'FAIL'} (exit {code})")
        return code

    def integrity(self):
        config = {"test": "integrity_latency_sweep", "device": self.device,
                  "payload_bytes": list(PAYLOADS), "trials_per_payload": 1000,
                  "mode": 0, "bits_per_word": 8,
                  "requested_sck_hz": 15623438,
                  "requested_sck_note": "request only; physical SCK is not measured here"}
        return self.execute("integrity", config,
                            [str(self.binaries["integrity"]), self.device, "15623438"])

    def sustained(self, payloads, window, repetitions):
        config = {"test": "sustained_throughput", "device": self.device,
                  "payload_bytes": payloads, "window_seconds": window,
                  "repetitions": repetitions, "mode": 0, "bits_per_word": 8,
                  "requested_sck_hz": 15623438,
                  "requested_sck_note": "request only; fixed ratio-2 PL divider is not changed"}
        # Runner intentionally accepts one point per invocation; preserve every
        # point independently so an error does not erase later evidence.
        overall = 0
        for rep in range(1, repetitions + 1):
            for payload in payloads:
                point = dict(config, payload_bytes=[payload], repetition=rep)
                rc = self.execute("sustained", point,
                                  [str(self.binaries["sustained"]), self.device,
                                   str(payload), str(window), "15623438", str(rep)])
                if rc and not overall:
                    overall = rc
                if rc:
                    print("Stopping the sweep after a failed point to preserve the board state.")
                    return rc
        return overall

    def menu(self):
        while True:
            print("\nMSU-2 ZCU102 SPI demo — Linux mode")
            print("  0) Normal Linux operation (return to the system console)")
            print("  1) J55 loopback integrity + latency sweep (11 payloads × 1,000 trials)")
            print("  2) Sustained throughput (choose payloads, window, repetitions)")
            print("  3) System / interface information")
            print("  4) Bare-metal mode guidance")
            print("  q) Quit")
            choice = input("Select: ").strip().lower()
            if choice in ("0", "q"):
                print("Returning to the normal Linux console. No test runs automatically at boot.")
                return 0
            if choice == "1":
                self.integrity()
            elif choice == "2":
                try:
                    raw = input("Payload bytes [default all shared sizes]: ").strip()
                    payloads = parse_list(raw) if raw else list(PAYLOADS)
                    raw = input("Window seconds per payload [60, range 1..3600]: ").strip()
                    window = int(raw or "60")
                    raw = input("Repetitions [3, range 1..3]: ").strip()
                    reps = int(raw or "3")
                    if not 1 <= window <= 3600 or not 1 <= reps <= 3:
                        raise ValueError("window must be 1..3600 and repetitions 1..3")
                except ValueError as exc:
                    print(f"Invalid settings: {exc}")
                    continue
                duration = len(payloads) * window * reps
                print(f"This run can take up to {duration} seconds ({duration / 60:.1f} minutes).")
                if input("Type RUN to start, or anything else to cancel: ").strip() == "RUN":
                    self.sustained(payloads, window, reps)
            elif choice == "3":
                print(json.dumps(system_info(self.device), indent=2))
                print("SPI topology and physical SCK require external confirmation/instrumentation.")
            elif choice == "4":
                print("Bare-metal is a separate A53 boot image/mode. Reboot into the menu-enabled")
                print("bare-metal build to run those tests; Linux cannot switch OS modes in-process.")
            else:
                print("Choose 0, 1, 2, 3, 4, or q.")


def self_test():
    assert parse_list("1, 8,65536") == [1, 8, 65536]
    for bad in ("", "3", "1,1", "1,x", "0"):
        try:
            parse_list(bad)
        except ValueError:
            continue
        raise AssertionError(f"invalid payload list accepted: {bad!r}")
    with __import__("tempfile").TemporaryDirectory() as td:
        fake = Path(td) / "fake-runner"
        fake.write_text("#!/bin/sh\nprintf 'fake success\\n'\n")
        fake.chmod(0o755)
        demo = Demo(result_root=Path(td) / "runs", binaries={"integrity": fake, "sustained": fake})
        assert demo.execute("selftest", {"test": "selftest"}, [str(fake)]) == 0
        run_dirs = list((Path(td) / "runs").iterdir())
        assert len(run_dirs) == 1
        assert json.loads((run_dirs[0] / "manifest.json").read_text())["exit_code"] == 0
        assert (run_dirs[0] / "raw_output.log").read_text() == "fake success\n"
    print("MSU2 demo host self-test: PASS")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        return 0
    device = os.environ.get("MSU2_SPI_DEVICE", DEFAULT_DEVICE)
    return Demo(device=device).menu()


if __name__ == "__main__":
    raise SystemExit(main())
