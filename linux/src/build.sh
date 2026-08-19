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
# WHAT THIS SCRIPT GUARANTEES, and what it does not. It asserts TWO
# exact literal strings -- the compiler --version first line and the
# .comment of the produced binary -- and it builds to a temp path,
# verifying .comment BEFORE moving over $OUT. It does NOT assert flag
# equivalence with the July builds (see below), and it does NOT verify
# anything about the source beyond its existence.
#
# HISTORY OF THE GATE. The first version matched the bare substring
# 13.3.0 against --version. Ubuntu 13.3.0-6ubuntu2~24.04 contains that
# substring, so the guard would have accepted the wrong toolchain --
# and the two July binaries WERE built by different compilers, both
# reporting 13.3.0 (spi_benchmark_jitter_aarch64 = Xilinx, bare
# "GCC: (GNU) 13.3.0"; spi_benchmark_aarch64 = Ubuntu). Exact
# whole-line matching on both strings is what distinguishes them.
#
# A toolchain upgrade WILL stop this script. That is intended: update
# the two literals deliberately and record why. ALLOW_COMPILER_MISMATCH=1
# overrides both checks, warns loudly, and still prints the resulting
# .comment so an overridden build is never silently unrecorded.
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

# SITE PORTABILITY: XILINX_ROOT is the ONLY site-varying value. The path
# tail below is fixed and MUST stay fixed -- it is what guarantees both
# sites invoke the same 189-byte wrapper script, which supplies
# --sysroot and -mbranch-protection=none. Those flags come from the
# WRAPPER, not from this file. Verify site exports:
#   XILINX_ROOT=/home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1
# Do NOT search $PATH. /usr/bin/aarch64-linux-gnu-gcc is absent on stile
# but PRESENT at 11.4.0 on bxqp8b3-ub22 -- a PATH search would build
# successfully there with different bytes, which is worse than refusing.
# $CC still overrides everything, for a toolchain outside this layout.
XILINX_ROOT="${XILINX_ROOT:-/tools/Xilinx/2025.1}"
CC="${CC:-$XILINX_ROOT/Vitis/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-gcc}"
# Two INDEPENDENT literal strings are asserted, both measured on stile
# 2026-08-17. They are different strings and neither implies the other:
#   --version first line : aarch64-amd-linux-gcc.real (GCC) 13.3.0
#   .comment of $OUT     : GCC: (GNU) 13.3.0
# The Ubuntu cross-compiler reports a different program name AND a
# different parenthetical, so exact whole-line matching discriminates.
# A bare-substring match on 13.3.0 does NOT -- that was the prior bug.
WANT_VERSION_LINE="aarch64-amd-linux-gcc.real (GCC) 13.3.0"
WANT_COMMENT="GCC: (GNU) 13.3.0"

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

# readelf reads $OUT's .comment. A gate that silently skips because its
# tool is missing is worse than no gate, so resolve it or abort.
READELF="$(dirname -- "$CC")/aarch64-linux-gnu-readelf"
if [ ! -x "$READELF" ]; then
    READELF="$(command -v readelf || true)"
fi
if [ -z "$READELF" ] || [ ! -x "$READELF" ]; then
    echo "ERROR: no readelf available; cannot verify .comment." >&2
    exit 1
fi

# Distinguish "compiler failed to run" from "wrong compiler". Both abort,
# but a crash reported as a version mismatch costs a debugging round trip.
if ! VER_RAW="$("$CC" --version 2>&1)"; then
    echo "ERROR: $CC failed to execute. Output:" >&2
    echo "$VER_RAW" >&2
    exit 1
fi
GOT="$(printf %s "$VER_RAW" | head -1)"

# EXACT whole-line comparison, not a glob. A toolchain upgrade SHOULD
# stop this script and force a deliberate update of the literal above.
if [ "$GOT" != "$WANT_VERSION_LINE" ]; then
    echo "ERROR: compiler version line mismatch." >&2
    echo "  want: $WANT_VERSION_LINE" >&2
    echo "  got:  $GOT" >&2
    if [ "${ALLOW_COMPILER_MISMATCH:-0}" = "1" ]; then
        echo "WARNING: ALLOW_COMPILER_MISMATCH=1 -- proceeding anyway." >&2
        echo "WARNING: the artifact will NOT match the committed binary" >&2
        echo "WARNING: provenance. Record the printed .comment below." >&2
    else
        echo "Set ALLOW_COMPILER_MISMATCH=1 to override deliberately." >&2
        exit 1
    fi
fi

[ -f "$SRC" ] || { echo "ERROR: missing $SRC" >&2; exit 1; }

echo "CC:  $CC"
echo "     $GOT"
echo "SRC: $SRC"
echo "OUT: $OUT"
echo

# Build to a temp path and move only after .comment verifies. A gate that
# fires AFTER overwriting the tracked binary is not a gate.
TMP_OUT="$OUT.tmp.$$"
trap 'rm -f "$TMP_OUT"' EXIT INT TERM

set -x
"$CC" -Wall -Wextra -O2 -g -o "$TMP_OUT" "$SRC" -lm
set +x

GOT_COMMENT="$("$READELF" -p .comment "$TMP_OUT" | sed -n "s/.*\(GCC: .*\)$/\1/p" | head -1)"
if [ "$GOT_COMMENT" != "$WANT_COMMENT" ]; then
    echo "ERROR: produced binary .comment mismatch." >&2
    echo "  want: $WANT_COMMENT" >&2
    echo "  got:  $GOT_COMMENT" >&2
    if [ "${ALLOW_COMPILER_MISMATCH:-0}" = "1" ]; then
        echo "WARNING: ALLOW_COMPILER_MISMATCH=1 -- keeping artifact." >&2
    else
        echo "$OUT was NOT modified." >&2
        exit 1
    fi
fi

mv -- "$TMP_OUT" "$OUT"
trap - EXIT INT TERM

# Print unconditionally: pass, override, or drift, the record always says
# what was actually produced.
echo
"$READELF" -p .comment "$OUT"
file "$OUT"
md5sum "$OUT"
