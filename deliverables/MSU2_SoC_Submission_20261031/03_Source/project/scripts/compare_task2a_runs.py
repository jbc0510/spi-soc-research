#!/usr/bin/env python3
"""Validate and compare the paired Task 2a Linux and bare-metal SPI CSVs."""

import argparse
import csv
from pathlib import Path

SIZES = [1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536]
REQUIRED = {
    "payload_bytes", "attempt_count", "timed_success_count", "api_success_count",
    "api_error_count", "timeout_count", "rx_mismatch_count", "avg_ns",
    "stddev_ns", "min_ns", "max_ns",
}


def load(path):
    with Path(path).open(newline="") as stream:
        reader = csv.DictReader(line for line in stream if not line.startswith("#"))
        if not reader.fieldnames or not REQUIRED.issubset(reader.fieldnames):
            raise ValueError(f"{path}: expected benchmark CSV fields are missing")
        rows = {}
        for row in reader:
            size = int(row["payload_bytes"])
            if size in rows:
                raise ValueError(f"{path}: duplicate payload size {size}")
            rows[size] = row
    if list(rows) != SIZES:
        raise ValueError(f"{path}: payload sizes/order do not match the Task 2a contract")
    for size, row in rows.items():
        attempts = int(row["attempt_count"])
        if attempts != 1000 or int(row["timed_success_count"]) != attempts:
            raise ValueError(f"{path}: incomplete timing samples at {size} bytes")
        for field in ("api_success_count", "timed_success_count"):
            if int(row[field]) != attempts:
                raise ValueError(f"{path}: {field} is not 1000 at {size} bytes")
        for field in ("api_error_count", "timeout_count", "rx_mismatch_count"):
            if int(row[field]) != 0:
                raise ValueError(f"{path}: {field} is nonzero at {size} bytes")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--linux", required=True, type=Path)
    parser.add_argument("--baremetal", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    linux, baremetal = load(args.linux), load(args.baremetal)

    fields = [
        "payload_bytes", "trials_each",
        "baremetal_api_successes", "linux_api_successes",
        "baremetal_errors", "linux_errors",
        "baremetal_rx_mismatches", "linux_rx_mismatches",
        "baremetal_mean_ns", "linux_mean_ns", "linux_minus_baremetal_mean_ns",
        "linux_to_baremetal_mean_ratio", "linux_mean_change_percent",
        "baremetal_stddev_ns", "linux_stddev_ns", "linux_to_baremetal_stddev_ratio",
        "baremetal_min_ns", "linux_min_ns", "baremetal_max_ns", "linux_max_ns",
        "baremetal_effective_payload_MB_s", "linux_effective_payload_MB_s",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for size in SIZES:
            bm, lx = baremetal[size], linux[size]
            bm_mean, lx_mean = float(bm["avg_ns"]), float(lx["avg_ns"])
            ratio = lx_mean / bm_mean
            writer.writerow({
                "payload_bytes": size,
                "trials_each": 1000,
                "baremetal_api_successes": int(bm["api_success_count"]),
                "linux_api_successes": int(lx["api_success_count"]),
                "baremetal_errors": int(bm["api_error_count"]),
                "linux_errors": int(lx["api_error_count"]),
                "baremetal_rx_mismatches": int(bm["rx_mismatch_count"]),
                "linux_rx_mismatches": int(lx["rx_mismatch_count"]),
                "baremetal_mean_ns": f"{bm_mean:.3f}",
                "linux_mean_ns": f"{lx_mean:.3f}",
                "linux_minus_baremetal_mean_ns": f"{lx_mean - bm_mean:.3f}",
                "linux_to_baremetal_mean_ratio": f"{ratio:.6f}",
                "linux_mean_change_percent": f"{(ratio - 1.0) * 100.0:.3f}",
                "baremetal_stddev_ns": f"{float(bm['stddev_ns']):.3f}",
                "linux_stddev_ns": f"{float(lx['stddev_ns']):.3f}",
                "linux_to_baremetal_stddev_ratio":
                    f"{float(lx['stddev_ns']) / float(bm['stddev_ns']):.6f}",
                "baremetal_min_ns": f"{float(bm['min_ns']):.3f}",
                "linux_min_ns": f"{float(lx['min_ns']):.3f}",
                "baremetal_max_ns": f"{float(bm['max_ns']):.3f}",
                "linux_max_ns": f"{float(lx['max_ns']):.3f}",
                "baremetal_effective_payload_MB_s": f"{size * 1000.0 / bm_mean:.6f}",
                "linux_effective_payload_MB_s": f"{size * 1000.0 / lx_mean:.6f}",
            })


if __name__ == "__main__":
    main()
