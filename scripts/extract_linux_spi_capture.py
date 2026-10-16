#!/usr/bin/env python3
"""Extract and validate the latest completed fixed-trial Linux SPI sweep."""

import argparse
import csv
from pathlib import Path

SIZES = [1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536]
REQUIRED = {
    "payload_bytes", "attempt_count", "timed_success_count", "api_success_count",
    "api_error_count", "timeout_count", "rx_mismatch_count", "avg_ns",
    "stddev_ns", "min_ns", "max_ns", "short_return_count", "timer_error_count",
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("output_prefix", type=Path)
    args = parser.parse_args()

    lines = args.capture.read_text(errors="replace").splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith("BENCH_RC=")]
    if not starts:
        raise SystemExit("no BENCH_RC marker found")
    start = starts[-1]
    if lines[start] != "BENCH_RC=0":
        raise SystemExit(f"latest benchmark did not succeed: {lines[start]}")
    end = next((i for i in range(start + 1, len(lines))
                if line_is_complete(lines[i])), None)
    if end is None:
        raise SystemExit("latest benchmark lacks a zero-failure completion marker")
    run_lines = lines[start:end + 1]
    try:
        begin = run_lines.index("---CSV-BEGIN---")
        finish = run_lines.index("---CSV-END---")
    except ValueError as exc:
        raise SystemExit("latest benchmark lacks CSV delimiters") from exc
    csv_lines = [line for line in run_lines[begin + 1:finish]
                 if line and not line.startswith("#")]
    rows = list(csv.DictReader(csv_lines))
    if not rows or not REQUIRED.issubset(rows[0]):
        raise SystemExit("benchmark CSV is missing required fields")
    if [int(row["payload_bytes"]) for row in rows] != SIZES:
        raise SystemExit("payload-size sequence does not match the 11-size contract")
    for row in rows:
        size = int(row["payload_bytes"])
        for field in ("attempt_count", "timed_success_count", "api_success_count"):
            if int(row[field]) != 1000:
                raise SystemExit(f"{field} is not 1000 for {size} bytes")
        for field in ("api_error_count", "timeout_count", "rx_mismatch_count",
                      "short_return_count", "timer_error_count"):
            if int(row[field]) != 0:
                raise SystemExit(f"{field} is nonzero for {size} bytes")

    prefix = args.output_prefix
    prefix.parent.mkdir(parents=True, exist_ok=True)
    prefix.with_suffix(".log").write_text("\n".join(run_lines) + "\n")
    with prefix.with_suffix(".csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"validated {len(rows)} payload sizes and 11000 transfers; zero failures")
    print(prefix.with_suffix(".log"))
    print(prefix.with_suffix(".csv"))


def line_is_complete(line: str) -> bool:
    return line.startswith("# sweep_complete=1 failures=0")


if __name__ == "__main__":
    main()
