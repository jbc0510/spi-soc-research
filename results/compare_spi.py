#!/usr/bin/env python3
"""
compare_spi.py  —  ZCU102 SPI interface comparison (CORRECTED)
================================================================
Replaces the previous version, which silently fell back to synthetic
sample_*() data whenever its expected filenames were missing.  That fallback
is the origin of the bogus "15.625 MHz" curve and the shrinking-ratio story;
it never touched the real board captures.

This version:
  * Parses the ACTUAL schema you capture:  bytes,avg_us,stddev_us
    (and the loopback schema: bytes,trials,avg_us,errors,status)
  * Computes throughput in **Mbps**, never MHz.  Throughput is bits/time,
    not a clock rate.  For single-lane standard SPI (C_SPI_MODE=0) the wire
    carries bytes*8 bits, so Mbps = bytes*8 / avg_us  (1 bit/us == 1 Mbps).
  * Counts full-duplex correctly: len bytes on the wire, NOT tx+rx = 2*len.
  * Separates the two questions the paper conflates:
        - small-payload LATENCY ratio  (clean OS/path-overhead proxy, 1 B)
        - large-payload THROUGHPUT ratio (confounded by per-interface SCK)
  * Reports an "implied minimum SCK" per interface = throughput at the largest
    payload.  You cannot clock SCK slower than this, so it is a hard lower
    bound and the target to confirm on a scope at pin F11.
  * Optionally checks measured times against a stated SCK and FLAGS any row
    that came in below the physical floor (i.e. faster than the wire allows).
  * Runs INTEGRITY CHECKS: flat stddev, and near-identical files that are not
    plausibly independent captures.
  * FAILS LOUDLY if a requested file is missing.  No synthetic fallback. Ever.

Usage:
  ./compare_spi.py [--dir results/] [--sck-axi 6250000] [--sck-ps 50000000]
                   [--no-plot]

Author: Jerry Conway (jbc0510) — corrected analysis pipeline
"""

import argparse
import csv
import os
import statistics
import sys

# Interfaces we expect, mapped to friendly labels.
INTERFACES = {
    "mio":  ("mio_results.csv",  "PS MIO  (spi0)"),
    "emio": ("emio_results.csv", "PS EMIO (spi1)"),
    "axi":  ("axi_results.csv",  "AXI PL  (quad_spi)"),
    "baremetal": ("baremetal_results.csv", "PS BM   (spi1/EL3)"),
}
LOOPBACK = ("loopback_stress_test.csv", "AXI loopback stress")


def die(msg):
    print(f"\nERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def load_simple(fp):
    """Parse bytes,avg_us,stddev_us. Returns {bytes: {'avg_us','std_us'}}."""
    out = {}
    with open(fp, newline="") as f:
        for row in csv.DictReader(f):
            try:
                b = int(row["bytes"])
                out[b] = {
                    "avg_us": float(row["avg_us"]),
                    "std_us": float(row.get("stddev_us", "nan")),
                }
            except (ValueError, KeyError):
                continue
    if not out:
        die(f"{fp} parsed to zero rows — wrong schema? expected bytes,avg_us,stddev_us")
    return out


def load_loopback(fp):
    """Parse bytes,trials,avg_us,errors,status."""
    out = {}
    with open(fp, newline="") as f:
        for row in csv.DictReader(f):
            try:
                b = int(row["bytes"])
                out[b] = {
                    "avg_us": float(row["avg_us"]),
                    "trials": int(row.get("trials", 0)),
                    "errors": int(row.get("errors", 0)),
                    "status": row.get("status", ""),
                }
            except (ValueError, KeyError):
                continue
    return out


def mbps(nbytes, avg_us):
    """Single-lane full-duplex throughput. bytes*8 bits / avg_us == Mbps."""
    if avg_us <= 0:
        return 0.0
    return (nbytes * 8.0) / avg_us


def floor_us(nbytes, sck_hz):
    """Physical minimum time for nbytes single-lane at sck_hz, zero overhead."""
    if not sck_hz:
        return None
    return (nbytes * 8.0) / sck_hz * 1e6


def print_table(data, sck):
    sizes = sorted({s for d in data.values() for s in d})
    labels = {k: INTERFACES[k][1] for k in data}

    print("\n" + "=" * 92)
    print("  ZCU102 SPI — measured latency (us) and throughput (Mbps), single-lane full-duplex")
    print("=" * 92)
    hdr = f"{'bytes':>8} |"
    for k in data:
        hdr += f" {labels[k][:14]:>14} |"
    print(hdr + "   PS/AXI thru")
    print("-" * 92)

    for s in sizes:
        line = f"{s:>8} |"
        thr = {}
        for k in data:
            row = data[k].get(s)
            if row:
                t = mbps(s, row["avg_us"])
                thr[k] = t
                line += f" {row['avg_us']:>8.1f}/{t:>5.1f} |"
            else:
                line += f" {'--':>14} |"
        # PS/AXI throughput ratio (use emio if present, else mio)
        ps = thr.get("emio", thr.get("mio"))
        ax = thr.get("axi")
        if ps and ax and ps > 0:
            line += f"   {ax / ps:>6.1f}x"
        print(line)

    print("\n(cells are  avg_us / Mbps)")

    # Implied minimum SCK per interface = throughput at largest payload.
    big = sizes[-1]
    print(f"\nImplied minimum SCK (lower bound, = throughput at {big} B, zero-overhead):")
    for k in data:
        row = data[k].get(big)
        if row:
            implied = mbps(big, row["avg_us"])  # Mbps == MHz-equivalent single lane
            print(f"  {labels[k]:<20}  >= {implied:6.2f} MHz   "
                  f"(scope F11 to confirm actual SCK)")

    # Physical-floor check against stated SCK.
    if sck:
        print("\nPhysical-floor check (measured time vs minimum possible at stated SCK):")
        for k in data:
            ref = sck.get(k)
            if not ref:
                continue
            for s in sizes:
                row = data[k].get(s)
                if not row:
                    continue
                fl = floor_us(s, ref)
                if fl and row["avg_us"] < fl:
                    pct = row["avg_us"] / fl * 100
                    print(f"  !! {labels[k]} @ {s} B: measured {row['avg_us']:.1f} us "
                          f"< floor {fl:.1f} us ({pct:.0f}% of floor) — "
                          f"IMPOSSIBLE at {ref/1e6:.3f} MHz; SCK must be higher "
                          f"or timing under-captures.")


def headline(data):
    print("\n" + "=" * 92)
    print("  HEADLINE METRICS (report these two separately — they answer different questions)")
    print("=" * 92)

    # 1) Small-payload latency ratio: cleanest OS/path-overhead proxy.
    small = 1
    ax = data.get("axi", {}).get(small)
    for ps_key in ("emio", "mio"):
        ps = data.get(ps_key, {}).get(small)
        if ps and ax and ax["avg_us"] > 0:
            r = ps["avg_us"] / ax["avg_us"]
            print(f"  [OS overhead, {small} B latency]  {INTERFACES[ps_key][1]} "
                  f"{ps['avg_us']:.2f} us  vs  AXI {ax['avg_us']:.2f} us  ->  {r:.2f}x")
    print("    ^ wire time negligible at 1 B, so this isolates software/path cost.")

    # 2) Large-payload throughput ratio: confounded by per-interface SCK.
    sizes = sorted({s for d in data.values() for s in d})
    big = sizes[-1]
    axb = data.get("axi", {}).get(big)
    for ps_key in ("emio", "mio"):
        psb = data.get(ps_key, {}).get(big)
        if psb and axb:
            tps, tax = mbps(big, psb["avg_us"]), mbps(big, axb["avg_us"])
            if tps > 0:
                print(f"  [throughput, {big} B]  {INTERFACES[ps_key][1]} {tps:.2f} Mbps "
                      f"vs AXI {tax:.2f} Mbps  ->  {tax/tps:.2f}x")
    print("    ^ depends on each interface's actual SCK; NOT a controlled-clock result")
    print("      until per-interface rates are confirmed (clean-harness readback + scope).")


def integrity_checks(data):
    print("\n" + "=" * 92)
    print("  INTEGRITY CHECKS")
    print("=" * 92)
    flags = 0

    # Flat stddev within a file.
    for k, d in data.items():
        stds = [r["std_us"] for r in d.values() if r["std_us"] == r["std_us"]]  # drop nan
        if len(stds) >= 3 and len(set(round(x, 6) for x in stds)) == 1:
            print(f"  !! {INTERFACES[k][1]}: stddev is a NOT-MEASURED sentinel ({stds[0]}) across all "
                  f"payloads — this column was NEVER MEASURED.")
            print(f"     Linux PS SPI1 jitter is STRUCTURALLY UNOBTAINABLE: ATF/TrustZone")
            print(f"     denies APU access to Node 36/domain12 (-EACCES, six attempts).")
            print(f"     DO NOT attempt to fill this column, and DO NOT copy stddev from")
            print(f"     another path — that was done once (see commit 0dc3d8f) and the")
            print(f"     donor capture was a different controller at a 14x different clock.")
            flags += 1

    # Near-identical files (not plausibly independent).
    keys = list(data)
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, b = data[keys[i]], data[keys[j]]
            common = sorted(set(a) & set(b))
            if len(common) < 3:
                continue
            rels = []
            for s in common:
                va, vb = a[s]["avg_us"], b[s]["avg_us"]
                if va > 0:
                    rels.append(abs(va - vb) / va)
            if rels and max(rels) < 0.005:  # within 0.5% everywhere
                print(f"  !! {INTERFACES[keys[i]][1]} and {INTERFACES[keys[j]][1]}: "
                      f"avg_us match within 0.5% at every payload — two independent "
                      f"controllers do not do this. Re-capture both.")
                flags += 1

    if flags == 0:
        print("  No integrity flags raised.")
    else:
        print(f"\n  {flags} flag(s) raised. Do not publish flagged rows without re-capture.")


def make_plot(data, outdir):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import matplotlib.ticker as ticker
    except ImportError:
        print("\n(matplotlib not available — skipping plot)")
        return

    sizes = sorted({s for d in data.values() for s in d})
    colors = {"mio": "#2ca02c", "emio": "#1f77b4", "axi": "#d62728"}

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))
    fig.suptitle("ZCU102 SPI — measured (single-lane full-duplex)",
                 fontweight="bold")

    for k, d in data.items():
        xs = [s for s in sizes if s in d]
        lat = [d[s]["avg_us"] for s in xs]
        thr = [mbps(s, d[s]["avg_us"]) for s in xs]
        ax1.plot(xs, lat, "o-", color=colors.get(k), label=INTERFACES[k][1])
        ax2.plot(xs, thr, "o-", color=colors.get(k), label=INTERFACES[k][1])

    ax1.set(xscale="log", yscale="log", xlabel="Payload (bytes)",
            ylabel="Avg latency (us)", title="Latency")
    ax2.set(xscale="log", xlabel="Payload (bytes)",
            ylabel="Throughput (Mbps)", title="Throughput (Mbps, NOT MHz)")
    for a in (ax1, ax2):
        a.grid(True, alpha=0.3)
        a.legend(fontsize=8)
        a.xaxis.set_major_formatter(ticker.FuncFormatter(lambda x, p: str(int(x))))

    plt.tight_layout()
    out = os.path.join(outdir, "spi_benchmark_comparison_corrected.png")
    plt.savefig(out, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"\nPlot saved: {out}")


def write_csv(data, sck, outpath):
    """Emit one chart-ready row per payload: per-interface avg_us + Mbps,
    PS/AXI ratio, implied SCK, and a floor-violation flag. Excel/Sheets ready."""
    sizes = sorted({s for d in data.values() for s in d})
    keys = [k for k in ("mio", "emio", "axi") if k in data]

    header = ["bytes"]
    for k in keys:
        header += [f"{k}_avg_us", f"{k}_Mbps"]
    header += ["ps_avg_us", "axi_avg_us", "ps_over_axi_throughput",
               "axi_implied_sck_MHz", "axi_below_floor"]

    with open(outpath, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        for s in sizes:
            row = [s]
            for k in keys:
                r = data[k].get(s)
                if r:
                    row += [f"{r['avg_us']:.2f}", f"{mbps(s, r['avg_us']):.3f}"]
                else:
                    row += ["", ""]
            ps = data.get("emio", data.get("mio", {})).get(s)
            ax = data.get("axi", {}).get(s)
            ps_us = f"{ps['avg_us']:.2f}" if ps else ""
            ax_us = f"{ax['avg_us']:.2f}" if ax else ""
            ratio = ""
            if ps and ax and mbps(s, ps["avg_us"]) > 0:
                ratio = f"{mbps(s, ax['avg_us']) / mbps(s, ps['avg_us']):.2f}"
            implied = f"{mbps(s, ax['avg_us']):.3f}" if ax else ""  # Mbps == single-lane MHz
            below = ""
            if ax and sck.get("axi"):
                fl = floor_us(s, sck["axi"])
                below = "YES" if (fl and ax["avg_us"] < fl) else "no"
            row += [ps_us, ax_us, ratio, implied, below]
            w.writerow(row)
    print(f"\nCSV written: {outpath}")


def main():
    ap = argparse.ArgumentParser(description="ZCU102 SPI comparison (corrected)")
    ap.add_argument("--dir", default=".", help="directory holding *_results.csv")
    ap.add_argument("--sck-axi", type=float, default=None,
                    help="stated AXI SCK in Hz for the physical-floor check (e.g. 6250000)")
    ap.add_argument("--sck-ps", type=float, default=None,
                    help="stated PS SCK in Hz for the physical-floor check")
    ap.add_argument("--no-plot", action="store_true")
    ap.add_argument("--csv-out", default="comparison_corrected.csv",
                    help="chart-ready CSV output filename (in --dir)")
    args = ap.parse_args()

    d = os.path.abspath(args.dir)
    data = {}
    missing = []
    for key, (fname, _label) in INTERFACES.items():
        fp = os.path.join(d, fname)
        if os.path.exists(fp):
            data[key] = load_simple(fp)
        else:
            missing.append(fname)

    if not data:
        die(f"no interface CSVs found in {d}. Looked for: "
            f"{', '.join(f for f, _ in INTERFACES.values())}")
    if missing:
        print(f"WARNING: missing (skipped, NOT substituted): {', '.join(missing)}",
              file=sys.stderr)

    sck = {}
    if args.sck_axi:
        sck["axi"] = args.sck_axi
    if args.sck_ps:
        sck["mio"] = sck["emio"] = sck["baremetal"] = args.sck_ps

    print_table(data, sck)
    headline(data)
    integrity_checks(data)
    write_csv(data, sck, os.path.join(d, args.csv_out))

    # Loopback report (separate — it's a sanity/corroboration run, not a comparison arm)
    lb_fp = os.path.join(d, LOOPBACK[0])
    if os.path.exists(lb_fp):
        lb = load_loopback(lb_fp)
        errs = sum(r["errors"] for r in lb.values())
        print("\n" + "=" * 92)
        print(f"  {LOOPBACK[1]}: {len(lb)} sizes up to {max(lb)} B, "
              f"total errors = {errs}, all status = "
              f"{'PASS' if all(r['status']=='PASS' for r in lb.values()) else 'MIXED'}")
        print("=" * 92)

    if not args.no_plot:
        make_plot(data, d)

    print("\nDone. Mbps is throughput; MHz is clock — they are not interchangeable.")


if __name__ == "__main__":
    main()
