#!/bin/sh
# Regenerate the aarch64 Linux SPI benchmark binary.
#
# WHY THIS EXISTS: no build script had ever existed for the Linux harness.
# The committed aarch64 binaries (spi_benchmark_aarch64,
# spi_benchmark_jitter_aarch64, both Jul 8 2026) have no recorded way to
# regenerate them. That gap is what this closes. Note also that
# `make build-linux` delegates to linux/, which contains no Makefile --
# that target has never worked.
#
# WHY BINARIES ARE TRACKED IN GIT: GitHub is the ONLY transfer path from
# stile (build/analysis) to jeremiahc (board UART, SD card). There is no
# SCP between the machines. Do not "clean up" the committed binaries --
# they are the transfer mechanism, not build litter.
#
# -lm IS REQUIRED, MEASURED NOT ASSUMED. Without it the link fails:
#   spi_benchmark_v2.c:217: undefined reference to `sqrt'
# __builtin_sqrt emits a libm call on this toolchain at -O2; it does not
# fold to an fsqrt instruction, and -fno-math-errno does not change that.
# Verified on stile 2026-08-14, GCC 13.3.0.
# CONSEQUENCE: libm.so.6 in DT_NEEDED is a property of THE CODE, not of
# the optimisation level, and says NOTHING about how the July binary was
# built. Do not read it as evidence of anything.
#
# NOT A REPRODUCTION OF THE JULY BUILD -- but not for the reason this
# header used to give. It claimed the July flags "were never recorded
# and cannot be recovered." They ARE recorded, at
# linux/JITTER_CAPTURE_RESUME.md:32-33:
#     aarch64-linux-gnu-gcc -O2 -Wall -Wextra \
#       -o spi_benchmark_jitter_aarch64 linux/src/spi_benchmark_jitter.c -lm
# Same flags as below minus -g. That file independently documents the
# -lm requirement. Commit fc52555 carries the same false statement and
# is SUPERSEDED on this point.
#
# THE RECORD MAY BE ABRIDGED, and that is the accurate claim. Two
# discrepancies: it shows no -g, yet the July binary carries debug
# info; and it names a bare aarch64-linux-gnu-gcc, which does not
# exist on stile (no /usr/bin/aarch64-linux-gnu-gcc, not on PATH --
# checked 2026-08-17). So the recorded line was not run as written on
# this host. Flag equivalence is still NOT claimed. What is matched is
# the observable property set: GCC 13.3.0, dynamically linked, debug
# info retained, not stripped, same DT_NEEDED.
#
# WHY -O2: so the trial loop is not unoptimised on the measured path.
# The loop body is get_time_us(); ioctl(); get_time_us(), and at -O0 the
# timing calls themselves carry avoidable overhead inside the interval
# being measured.
set -eu

CC="${CC:-/tools/Xilinx/2025.1/Vitis/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-gcc}"
WANT_GCC_VER="13.3.0"

SRC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SRC="$SRC_DIR/spi_benchmark_v2.c"
OUT="$SRC_DIR/spi_benchmark_v2_aarch64"

# /usr/bin/aarch64-linux-gnu-gcc DOES NOT EXIST on stile -- binutils are
# installed, the compiler is not. Check the file, not just $PATH.
if [ ! -x "$CC" ]; then
    echo "ERROR: compiler not found or not executable:" >&2
    echo "  $CC" >&2
    echo "Set CC to an aarch64 cross-compiler and re-run." >&2
    exit 1
fi

# ABORT, not warn. Building with whatever happens to be on PATH is how
# unrecorded state accumulates -- the exact gap this script closes.
GOT="$("$CC" --version 2>&1 | head -1)"
case "$GOT" in
    *"$WANT_GCC_VER"*) ;;
    *)
        echo "ERROR: compiler version mismatch." >&2
        echo "  want: $WANT_GCC_VER" >&2
        echo "  got:  $GOT" >&2
        echo "The committed binary's .comment records GCC $WANT_GCC_VER." >&2
        exit 1
        ;;
esac

[ -f "$SRC" ] || { echo "ERROR: missing $SRC" >&2; exit 1; }

echo "CC:  $CC"
echo "     $GOT"
echo "SRC: $SRC"
echo "OUT: $OUT"
echo

set -x
"$CC" -Wall -Wextra -O2 -g -o "$OUT" "$SRC" -lm
set +x

echo
file "$OUT"
md5sum "$OUT"
