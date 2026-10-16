#!/usr/bin/env python3
"""Validate and compare the Task 2e bare-metal UART capture with Linux medians."""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results/task2e_sustainable_runner_20261016"
CAPTURE = RESULTS / "baremetal_reboot_capture_20261016.raw.log"
LINUX = RESULTS / "linux_sustained_medians.csv"
BM_CSV = RESULTS / "baremetal_reboot_metrics_20261016.csv"
COMPARE = RESULTS / "linux_baremetal_rate_comparison_20261016.csv"


def read_capture() -> list[dict[str, str]]:
    text = CAPTURE.read_text(errors="replace")
    match = re.search(r"---CSV-BEGIN---\s*\n(.*?)\n---CSV-END---", text, re.S)
    if not match:
        raise SystemExit("capture has no complete CSV block")
    rows = list(csv.DictReader(match.group(1).splitlines()))
    expected_sizes = [1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536]
    if [int(row["payload_bytes"]) for row in rows] != expected_sizes:
        raise SystemExit("capture payload-size sequence does not match the 11-size sweep")
    for row in rows:
        for field in ("timed_success_count", "api_error_count", "timeout_count", "rx_mismatch_count"):
            if int(row[field]) != (1000 if field == "timed_success_count" else 0):
                raise SystemExit(f"failed-run gate: {field}={row[field]} at {row['payload_bytes']} B")
    if "# sweep_complete=1 failures=0" not in text:
        raise SystemExit("capture does not declare a complete zero-failure sweep")
    return rows


def main() -> None:
    rows = read_capture()
    with BM_CSV.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    with LINUX.open(newline="") as f:
        linux = {int(row["payload_bytes"]): float(row["median_MBps"]) for row in csv.DictReader(f)}

    fields = ["payload_bytes", "baremetal_avg_latency_us", "baremetal_derived_MBps",
              "linux_3x60s_median_MBps", "linux_to_baremetal_rate_ratio",
              "baremetal_verified_transfers", "baremetal_api_errors", "baremetal_timeouts",
              "baremetal_rx_mismatches"]
    with COMPARE.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            n = int(row["payload_bytes"])
            avg_us = float(row["avg_ns"]) / 1000.0
            bm_mbps = n / avg_us  # decimal MB/s; one byte per microsecond equals 1 MB/s
            linux_mbps = linux[n]
            writer.writerow({
                "payload_bytes": n,
                "baremetal_avg_latency_us": f"{avg_us:.6f}",
                "baremetal_derived_MBps": f"{bm_mbps:.9f}",
                "linux_3x60s_median_MBps": f"{linux_mbps:.9f}",
                "linux_to_baremetal_rate_ratio": f"{linux_mbps / bm_mbps:.6f}",
                "baremetal_verified_transfers": row["timed_success_count"],
                "baremetal_api_errors": row["api_error_count"],
                "baremetal_timeouts": row["timeout_count"],
                "baremetal_rx_mismatches": row["rx_mismatch_count"],
            })
    print(f"validated {len(rows)} payload points; 11000 bare-metal transfers; zero failures")
    print(BM_CSV)
    print(COMPARE)


if __name__ == "__main__":
    main()
