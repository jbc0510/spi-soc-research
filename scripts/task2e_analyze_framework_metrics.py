#!/usr/bin/env python3
"""Validate paired Task 2 captures and derive Linux benchmark-thread CPU share."""

import argparse
import csv
import re
from pathlib import Path

SIZES = [1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536]


def read_csv(path):
    with Path(path).open(newline="") as stream:
        reader = csv.DictReader(line for line in stream if not line.startswith("#"))
        if not reader.fieldnames:
            raise ValueError(f"{path}: missing CSV header")
        rows = {int(row["payload_bytes"]): row for row in reader}
    if list(rows) != SIZES:
        raise ValueError(f"{path}: payload sizes/order do not match common contract")
    return rows


def read_linux_loop_metrics(path):
    text = Path(path).read_text(errors="replace")
    matches = re.findall(
        r"# loop_metrics payload_bytes=(\d+) cpu_ns=(\d+) wall_ns=(\d+) "
        r"nvcsw=(-?\d+) nivcsw=(-?\d+)", text
    )
    rows = {int(size): (int(cpu), int(wall), int(nvcsw), int(nivcsw))
            for size, cpu, wall, nvcsw, nivcsw in matches}
    if list(rows) != SIZES:
        raise ValueError(f"{path}: expected one loop_metrics record for each contract size")
    if "cpu_scope=whole_trial_loop_including_poison_verification_accounting" not in text:
        raise ValueError(f"{path}: CPU metric scope declaration is missing")
    for size, (cpu, wall, _, _) in rows.items():
        if cpu <= 0 or wall <= 0 or cpu > wall * 1.02:
            raise ValueError(f"{path}: invalid CPU/wall interval at {size} bytes")
    return rows


def validate_contract(name, rows):
    for size, row in rows.items():
        trials = int(row.get("trials_each", row.get("attempt_count", "-1")))
        if trials != 1000:
            raise ValueError(f"{name}: expected 1000 trials at {size} bytes")
        for field in ("baremetal_errors", "linux_errors", "baremetal_rx_mismatches",
                      "linux_rx_mismatches"):
            if field in row and int(row[field]) != 0:
                raise ValueError(f"{name}: {field} is nonzero at {size} bytes")
        for field in ("baremetal_api_successes", "linux_api_successes"):
            if field in row and int(row[field]) != 1000:
                raise ValueError(f"{name}: {field} is not 1000 at {size} bytes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--comparison", required=True, type=Path,
                        help="Output of scripts/compare_task2a_runs.py")
    parser.add_argument("--linux-log", required=True, type=Path,
                        help="Raw Linux capture containing loop_metrics records")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    comparison = read_csv(args.comparison)
    validate_contract("comparison", comparison)
    linux_metrics = read_linux_loop_metrics(args.linux_log)
    fields = [
        "payload_bytes", "trials_each", "baremetal_api_successes", "linux_api_successes",
        "baremetal_errors", "linux_errors", "baremetal_rx_mismatches", "linux_rx_mismatches",
        "baremetal_mean_ns", "linux_mean_ns", "baremetal_stddev_ns", "linux_stddev_ns",
        "baremetal_effective_payload_MB_s", "linux_effective_payload_MB_s",
        "linux_thread_cpu_ns", "linux_loop_wall_ns", "linux_thread_cpu_util_percent",
        "linux_nvcsw", "linux_nivcsw", "baremetal_cpu_utilization", "sustainable_rate_measured",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for size in SIZES:
            row = comparison[size]
            cpu_ns, wall_ns, nvcsw, nivcsw = linux_metrics[size]
            writer.writerow({
                "payload_bytes": size,
                "trials_each": 1000,
                "baremetal_api_successes": row["baremetal_api_successes"],
                "linux_api_successes": row["linux_api_successes"],
                "baremetal_errors": row["baremetal_errors"],
                "linux_errors": row["linux_errors"],
                "baremetal_rx_mismatches": row["baremetal_rx_mismatches"],
                "linux_rx_mismatches": row["linux_rx_mismatches"],
                "baremetal_mean_ns": row["baremetal_mean_ns"],
                "linux_mean_ns": row["linux_mean_ns"],
                "baremetal_stddev_ns": row["baremetal_stddev_ns"],
                "linux_stddev_ns": row["linux_stddev_ns"],
                "baremetal_effective_payload_MB_s": row["baremetal_effective_payload_MB_s"],
                "linux_effective_payload_MB_s": row["linux_effective_payload_MB_s"],
                "linux_thread_cpu_ns": cpu_ns,
                "linux_loop_wall_ns": wall_ns,
                "linux_thread_cpu_util_percent": f"{100.0 * cpu_ns / wall_ns:.3f}",
                "linux_nvcsw": nvcsw,
                "linux_nivcsw": nivcsw,
                "baremetal_cpu_utilization": "not_measured_busy_wait_loop",
                "sustainable_rate_measured": "false",
            })


if __name__ == "__main__":
    main()
