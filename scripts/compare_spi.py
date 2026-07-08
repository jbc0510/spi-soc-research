#!/usr/bin/env python3
"""
compare_spi.py - Phase 6 Analysis: Compare MIO, EMIO, and AXI SPI Linux benchmark results
MSU-2, PI Dr. Kevin Kornegay
"""

import csv
import os
import sys

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np
except ImportError:
    print("ERROR: matplotlib and numpy required. Install with: pip3 install matplotlib numpy")
    sys.exit(1)

RESULTS_DIR = os.path.join(os.path.dirname(__file__), '..', 'results')
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'results')

def load_csv(filename):
    path = os.path.join(RESULTS_DIR, filename)
    data = {'bytes': [], 'avg_us': [], 'stddev_us': []}
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            data['bytes'].append(int(row['bytes']))
            data['avg_us'].append(float(row['avg_us']))
            data['stddev_us'].append(float(row['stddev_us']))
    return data

def main():
    mio  = load_csv('mio_results.csv')
    emio = load_csv('emio_results.csv')
    axi  = load_csv('axi_results.csv')

    sizes = mio['bytes']

    # ── Print comparison table ──────────────────────────────────────────────
    print("\nPhase 6 Linux SPI Benchmark Comparison")
    print("=" * 85)
    print(f"{'Bytes':>8}  {'MIO Avg':>12}  {'EMIO Avg':>12}  {'AXI Avg':>12}  {'Speedup (MIO/AXI)':>18}")
    print("-" * 85)
    for i, sz in enumerate(sizes):
        speedup = mio['avg_us'][i] / axi['avg_us'][i]
        print(f"{sz:>8}  {mio['avg_us'][i]:>11.2f}µ  {emio['avg_us'][i]:>11.2f}µ  {axi['avg_us'][i]:>11.2f}µ  {speedup:>17.1f}x")
    print("=" * 85)

    # ── Plot 1: Latency vs Payload (log-log) ────────────────────────────────
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.loglog(sizes, mio['avg_us'],  'b-o', label='PS SPI0 (MIO)',  linewidth=2, markersize=6)
    ax.loglog(sizes, emio['avg_us'], 'g-s', label='PS SPI1 (EMIO)', linewidth=2, markersize=6)
    ax.loglog(sizes, axi['avg_us'],  'r-^', label='AXI Quad SPI',   linewidth=2, markersize=6)
    ax.set_xlabel('Payload Size (bytes)', fontsize=13)
    ax.set_ylabel('Latency (µs)', fontsize=13)
    ax.set_title('ZCU102 SPI Linux Latency vs Payload Size\n(1 MHz clock, 1000 trials)', fontsize=14)
    ax.legend(fontsize=12)
    ax.grid(True, which='both', alpha=0.3)
    ax.set_xticks(sizes)
    ax.set_xticklabels([str(s) for s in sizes], rotation=45)
    plt.tight_layout()
    out1 = os.path.join(OUTPUT_DIR, 'latency_comparison.png')
    plt.savefig(out1, dpi=150)
    print(f"\nSaved: {out1}")
    plt.close()

    # ── Plot 2: AXI Speedup over MIO ────────────────────────────────────────
    speedups = [mio['avg_us'][i] / axi['avg_us'][i] for i in range(len(sizes))]
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.semilogx(sizes, speedups, 'r-o', linewidth=2, markersize=8)
    ax.axhline(y=1, color='gray', linestyle='--', alpha=0.5)
    ax.set_xlabel('Payload Size (bytes)', fontsize=13)
    ax.set_ylabel('Speedup (MIO latency / AXI latency)', fontsize=13)
    ax.set_title('AXI Quad SPI Speedup vs PS SPI (MIO)\n(Linux spidev, 1 MHz)', fontsize=14)
    ax.set_xticks(sizes)
    ax.set_xticklabels([str(s) for s in sizes], rotation=45)
    ax.grid(True, which='both', alpha=0.3)
    for i, (sz, sp) in enumerate(zip(sizes, speedups)):
        ax.annotate(f'{sp:.1f}x', (sz, sp), textcoords='offset points', xytext=(0, 8), ha='center', fontsize=9)
    plt.tight_layout()
    out2 = os.path.join(OUTPUT_DIR, 'axi_speedup.png')
    plt.savefig(out2, dpi=150)
    print(f"Saved: {out2}")
    plt.close()

    # ── Plot 3: OS Overhead (actual vs theoretical) ─────────────────────────
    # Theoretical: bytes * 8 bits / (1e6 Hz) * 1e6 µs/s = bytes * 8 µs
    theoretical = [sz * 8 for sz in sizes]
    mio_overhead  = [mio['avg_us'][i]  - theoretical[i] for i in range(len(sizes))]
    axi_overhead  = [axi['avg_us'][i]  - theoretical[i] for i in range(len(sizes))]
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.semilogx(sizes, mio_overhead, 'b-o', label='PS SPI (MIO) overhead', linewidth=2)
    ax.semilogx(sizes, axi_overhead, 'r-^', label='AXI SPI overhead',      linewidth=2)
    ax.set_xlabel('Payload Size (bytes)', fontsize=13)
    ax.set_ylabel('OS/Driver Overhead (µs)', fontsize=13)
    ax.set_title('Linux SPI Driver Overhead vs Theoretical Transfer Time\n(1 MHz clock)', fontsize=14)
    ax.legend(fontsize=12)
    ax.grid(True, which='both', alpha=0.3)
    ax.set_xticks(sizes)
    ax.set_xticklabels([str(s) for s in sizes], rotation=45)
    plt.tight_layout()
    out3 = os.path.join(OUTPUT_DIR, 'os_overhead.png')
    plt.savefig(out3, dpi=150)
    print(f"Saved: {out3}")
    plt.close()

    print("\nDone.")

if __name__ == '__main__':
    main()
