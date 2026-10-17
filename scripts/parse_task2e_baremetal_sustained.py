#!/usr/bin/env python3
"""Validate and summarize the Task 2e bare-metal sustained UART capture."""
from __future__ import annotations

import argparse
import csv
import statistics
from pathlib import Path

PAYLOADS = [1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536]
FIELDS = [
    "repetition", "payload_bytes", "window_s", "attempts", "verified_transfers",
    "verified_bytes", "application_MBps", "cpu_metric_kind", "cpu_metric_pct",
    "thread_cpu_s", "thread_cpu_share_pct", "busy_wait_core_occupancy_pct",
    "max_transfer_us", "api_errors", "mismatches", "first_error_code",
]


def load_capture(path: Path) -> list[dict[str, str]]:
    text = path.read_text(errors="replace")
    if "# sustained_sweep_complete=1" not in text:
        raise SystemExit("capture lacks the sustained_sweep_complete marker")
    rows: list[dict[str, str]] = []
    for line in text.splitlines():
        if line and line[0].isdigit() and "," in line:
            values = line.split(",")
            if len(values) != len(FIELDS):
                raise SystemExit(f"malformed CSV row with {len(values)} fields: {line}")
            rows.append(dict(zip(FIELDS, values)))
    if len(rows) != 33:
        raise SystemExit(f"expected 33 records, found {len(rows)}")
    expected = [(rep, size) for rep in range(1, 4) for size in PAYLOADS]
    actual = [(int(r["repetition"]), int(r["payload_bytes"])) for r in rows]
    if actual != expected:
        raise SystemExit("payload/repetition sequence does not match the required ladder")
    for row in rows:
        if (int(row["api_errors"]) or int(row["mismatches"])
                or int(row["first_error_code"]) or row["attempts"] != row["verified_transfers"]
                or int(row["verified_bytes"]) != int(row["verified_transfers"]) * int(row["payload_bytes"])
                or row["cpu_metric_kind"] != "busy_wait_core_occupancy"
                or float(row["window_s"]) < 60.0):
            raise SystemExit(f"failed point validation: {row}")
    return rows


def write_csv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("linux_medians", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    runs = load_capture(args.capture)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    run_fields = FIELDS + ["raw_log"]
    for row in runs:
        row["raw_log"] = args.capture.name
    write_csv(args.output_dir / "baremetal_sustained_runs_20261016.csv", run_fields, runs)

    medians: list[dict[str, object]] = []
    for size in PAYLOADS:
        points = [r for r in runs if int(r["payload_bytes"]) == size]
        rates = [float(r["application_MBps"]) for r in points]
        medians.append({
            "payload_bytes": size,
            "rep1_MBps": rates[0], "rep2_MBps": rates[1], "rep3_MBps": rates[2],
            "median_MBps": statistics.median(rates),
            "median_busy_wait_core_occupancy_pct": 100.0,
            "median_window_s": statistics.median(float(r["window_s"]) for r in points),
        })
    write_csv(args.output_dir / "baremetal_sustained_medians_20261016.csv", list(medians[0]), medians)

    with args.linux_medians.open(newline="") as f:
        linux = {int(r["payload_bytes"]): r for r in csv.DictReader(f)}
    if set(linux) != set(PAYLOADS):
        raise SystemExit("Linux median file does not have the shared payload set")
    comparison: list[dict[str, object]] = []
    for bm in medians:
        size = int(bm["payload_bytes"])
        linux_rate = float(linux[size]["median_MBps"])
        bm_rate = float(bm["median_MBps"])
        comparison.append({
            "payload_bytes": size,
            "linux_rep1_MBps": linux[size]["rep1_MBps"],
            "linux_rep2_MBps": linux[size]["rep2_MBps"],
            "linux_rep3_MBps": linux[size]["rep3_MBps"],
            "linux_median_MBps": linux_rate,
            "baremetal_rep1_MBps": bm["rep1_MBps"],
            "baremetal_rep2_MBps": bm["rep2_MBps"],
            "baremetal_rep3_MBps": bm["rep3_MBps"],
            "baremetal_median_MBps": bm_rate,
            "baremetal_vs_linux_pct": (bm_rate / linux_rate - 1.0) * 100.0,
            "linux_median_thread_cpu_share_pct": linux[size]["median_thread_cpu_share_pct"],
            "baremetal_busy_wait_core_occupancy_pct": 100.0,
            "errors_all_runs": 0,
            "comparison_limit": "different timer/CPU execution models; not causal OS-only comparison",
        })
    write_csv(args.output_dir / "linux_baremetal_sustained_comparison_20261016.csv", list(comparison[0]), comparison)
    print(f"validated_points={len(runs)} payload_sizes={len(PAYLOADS)} repetitions=3 errors=0 mismatches=0")
    print(f"baremetal_64KiB_median_MBps={medians[-1]['median_MBps']:.6f}")
    print(f"linux_64KiB_median_MBps={float(linux[65536]['median_MBps']):.6f}")


if __name__ == "__main__":
    main()
