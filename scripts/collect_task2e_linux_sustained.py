#!/usr/bin/env python3
"""Validate Task 2e Linux UART point logs and emit a reproducible CSV."""
import csv
import hashlib
import json
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results/task2e_sustainable_runner_20261016"
PAYLOADS = (1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536)
RUNS = RESULTS / "linux_sustained_runs.csv"
MEDIANS = RESULTS / "linux_sustained_medians.csv"
MANIFEST = RESULTS / "linux_sustained_manifest.json"
FIELDS = (
    "repetition,payload_bytes,window_s,attempts,verified_transfers,verified_bytes,"
    "application_MBps,cpu_metric_kind,cpu_metric_pct,thread_cpu_s,thread_cpu_share_pct,"
    "busy_wait_core_occupancy_pct,max_transfer_us,api_errors,mismatches,first_error_code"
).split(",")


def cpu_stat(lines, marker):
    active = False
    for line in lines:
        if line.strip() == marker:
            active = True
        elif active and line.startswith("cpu  "):
            return [int(x) for x in line.split()[1:]]
    raise ValueError(f"Missing aggregate CPU counters after {marker}")


def parse_point(rep, payload):
    path = RESULTS / f"linux_sustained_point_{payload}B_rep{rep}_serial.log"
    text = path.read_text(errors="replace").replace("\r", "")
    if "__RUN_RC:0" not in text or "__DONE__" not in text:
        raise ValueError(f"{path.name}: missing successful completion marker")
    if "physical_sck_hz=NOT_MEASURED" not in text:
        raise ValueError(f"{path.name}: unexpected runner metadata")
    if "speed_requested_hz=49995000 speed_readback_hz=49995000" not in text:
        raise ValueError(f"{path.name}: speed configuration mismatch")
    pattern = re.compile(r"^" + str(rep) + r"," + str(payload) + r",[^,\r\n]+(?:,[^,\r\n]+){13}$", re.M)
    matches = pattern.findall(text)
    if len(matches) != 1:
        raise ValueError(f"{path.name}: expected one CSV result row, found {len(matches)}")
    values = dict(zip(FIELDS, matches[0].split(",")))
    if (int(values["attempts"]) != int(values["verified_transfers"])
            or int(values["verified_bytes"]) != int(values["verified_transfers"]) * payload
            or any(int(values[k]) != 0 for k in ("api_errors", "mismatches", "first_error_code"))
            or float(values["window_s"]) < 59.4):
        raise ValueError(f"{path.name}: integrity or duration validation failed")
    before = cpu_stat(text.splitlines(), "__STAT_BEFORE__")
    after = cpu_stat(text.splitlines(), "__STAT_AFTER__")
    delta = [b - a for a, b in zip(before, after)]
    total = sum(delta)
    idle = delta[3] + (delta[4] if len(delta) > 4 else 0)
    values["system_cpu_utilization_pct"] = f"{100.0 * (total - idle) / total:.6f}"
    values["system_cpu_delta_ticks"] = str(total)
    values["system_idle_iowait_delta_ticks"] = str(idle)
    values["raw_log"] = path.name
    return values


def main():
    points = [parse_point(rep, payload) for rep in range(1, 4) for payload in PAYLOADS]
    fields = FIELDS + ["system_cpu_utilization_pct", "system_cpu_delta_ticks",
                       "system_idle_iowait_delta_ticks", "raw_log"]
    with RUNS.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(points)
    with MEDIANS.open("w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["payload_bytes", "rep1_MBps", "rep2_MBps", "rep3_MBps",
                         "median_MBps", "median_thread_cpu_share_pct",
                         "median_system_cpu_utilization_pct"])
        for payload in PAYLOADS:
            rows = [x for x in points if int(x["payload_bytes"]) == payload]
            rates = [float(x["application_MBps"]) for x in rows]
            cpu = [float(x["thread_cpu_share_pct"]) for x in rows]
            sys_cpu = [float(x["system_cpu_utilization_pct"]) for x in rows]
            writer.writerow([payload, *[f"{x:.9f}" for x in rates],
                             f"{statistics.median(rates):.9f}",
                             f"{statistics.median(cpu):.6f}",
                             f"{statistics.median(sys_cpu):.6f}"])
    artifacts = [RUNS, MEDIANS, RESULTS / "linux_sustained_serial_raw.tar.gz"]
    artifacts += sorted(RESULTS.glob("linux_sustained_point_*_serial.log"))
    manifest = {
        "experiment": "MSU-2 Task 2e Linux sustained AXI Quad SPI loopback",
        "target": "ZCU102 newQspi; Linux 6.12.10-xilinx-g0a0f70e531c7; PetaLinux 2025.1",
        "controller": "/dev/spidev1.0; AXI Quad SPI at 0xA0000000; J55 external MOSI-to-MISO loopback",
        "fpga_bitstream_sha256": "c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd",
        "fpga_manager_state_before_each_point": "operating",
        "spi_mode": 0,
        "bits_per_word": 8,
        "requested_and_readback_speed_hz": 49995000,
        "physical_sck_hz": "approximately 51000000; measured 2026-09-29 on J55 pin 4 for this exact bitstream and ratio-2 configuration; not remeasured in this run set",
        "pl0_hz": 99990000,
        "cpu_operating_point": "userspace governor, 1200000 kHz read before the sustained set; not sampled per point",
        "payload_bytes": list(PAYLOADS),
        "window_seconds_per_point": 60,
        "repetitions": 3,
        "timer": "CLOCK_MONOTONIC_RAW; benchmark thread CPU CLOCK_THREAD_CPUTIME_ID",
        "point_count": len(points),
        "passed_points": sum(int(x["api_errors"]) == 0 and int(x["mismatches"]) == 0 for x in points),
        "run_order": "All Linux repetitions were collected before a new bare-metal sustained run; order does not alternate backends.",
        "results_csv": RUNS.name,
        "median_csv": MEDIANS.name,
        "raw_uart_archive": "linux_sustained_serial_raw.tar.gz",
        "artifacts_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in artifacts},
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Validated {len(points)} Linux points; wrote {RUNS}, {MEDIANS}, and {MANIFEST}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
