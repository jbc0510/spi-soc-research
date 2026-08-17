#!/bin/sh
# recon_host.sh -- record a workstation's build environment for cross-site
# reproducibility comparison. MSU-2 Task 2, SOW 2.g / bring-up protocol.
#
# PURPOSE: run this IDENTICALLY at LPS (stile) and Morgan (opentitan). The
# comparison is then `diff` of two outputs, not a judgement call.
#
# USAGE:
#   sh tools/recon_host.sh 2>&1 | tee /tmp/recon_host_<SITE>_<HOST>.txt
# then commit the output under docs/environment/.
#
# DESIGN RULES:
#  - POSIX sh only. No bashisms. Nothing assumed installed.
#  - ABSENCE IS A RESULT. Every probe prints either a value or an explicit
#    "ABSENT". A missing line is a bug in this script, not a finding.
#  - No `set -e`. A failed probe must not abort the remaining probes.
#  - Read-only. This script writes nothing outside stdout.
#  - Machine-readable-ish: one KEY: VALUE per line where possible, so a diff
#    of two runs is legible.

say() { printf '%s\n' "$*"; }
kv()  { printf '%-34s %s\n' "$1:" "$2"; }

probe() {
    # probe LABEL COMMAND... -- prints first line of output, or ABSENT
    _label=$1; shift
    if _out=$("$@" 2>/dev/null | head -1) && [ -n "$_out" ]; then
        kv "$_label" "$_out"
    else
        kv "$_label" "ABSENT"
    fi
}

have() {
    # have LABEL PATH -- reports existence and type of a path
    if [ -d "$2" ]; then kv "$1" "DIR $2"
    elif [ -x "$2" ]; then kv "$1" "EXEC $2 ($(wc -c <"$2" 2>/dev/null) bytes)"
    elif [ -f "$2" ]; then kv "$1" "FILE $2"
    else kv "$1" "ABSENT $2"
    fi
}

say "================================================================"
say " MSU-2 HOST RECON"
say "================================================================"
say ""
say "-- OPERATOR MUST FILL IN ------------------------------------------"
kv "SITE" "${MSU_SITE:-UNSET -- rerun with MSU_SITE=LPS or MSU_SITE=MORGAN}"
say "  (if UNSET above, the output is still valid but must be labelled"
say "   by hand before committing)"
say ""

say "-- IDENTITY -------------------------------------------------------"
probe "hostname"            hostname
probe "kernel"              uname -sr
probe "arch"               uname -m
kv    "date_reported"       "$(date 2>/dev/null || echo ABSENT)"
say "  NOTE: verify this against a known-good clock. RTC was unset on"
say "  ZCU102 #1; do not assume a host clock is correct either."
if [ -r /etc/os-release ]; then
    kv "os_release_PRETTY" "$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-UNPARSED}")"
else
    kv "os_release_PRETTY" "ABSENT /etc/os-release"
fi
say ""

say "-- GIT AND REPO STATE ---------------------------------------------"
probe "git_version"         git --version
if [ -d .git ]; then
    kv "repo_cwd"           "$(pwd)"
    kv "branch"             "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo UNKNOWN)"
    kv "head_commit"        "$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
    kv "head_subject"       "$(git log -1 --format=%s 2>/dev/null || echo UNKNOWN)"
    _dirty=$(git status --porcelain 2>/dev/null | wc -l)
    kv "dirty_paths"        "$_dirty"
    if [ "$_dirty" -ne 0 ]; then
        say "  DIRTY -- a recon run from a dirty tree cannot establish"
        say "  reproducibility. Listing:"
        git status --porcelain 2>/dev/null | sed 's/^/    /'
    fi
    kv "remotes"            "$(git remote -v 2>/dev/null | tr '\n' ' ' || echo NONE)"
else
    kv "repo_cwd"           "NOT A GIT REPO -- run this from the repo root"
fi
say ""

say "-- TOOLCHAIN: XILINX ----------------------------------------------"
have  "xilinx_root"         /tools/Xilinx/2025.1
have  "vitis_bin"           /tools/Xilinx/2025.1/Vitis/bin
have  "xsct"                /tools/Xilinx/2025.1/Vitis/bin/xsct
CCX=/tools/Xilinx/2025.1/Vitis/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-gcc
have  "cross_gcc"           "$CCX"
if [ -x "$CCX" ]; then
    kv "cross_gcc_version"  "$("$CCX" --version 2>&1 | head -1)"
    say "  EXPECTED at LPS: aarch64-amd-linux-gcc.real (GCC) 13.3.0"
    say "  build.sh asserts this EXACT whole line."
else
    kv "cross_gcc_version"  "ABSENT -- build.sh will refuse, which is CORRECT"
fi
RDX=/tools/Xilinx/2025.1/Vitis/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-readelf
have  "cross_readelf"       "$RDX"
say "  NOTE: on stile this is a 117-byte WRAPPER SCRIPT, not a binary."
say "  build.sh's .comment gate depends on that shim resolving."
say ""

say "-- TOOLCHAIN: HOST ------------------------------------------------"
probe "host_gcc"            gcc --version
say "  NOTE: Ubuntu host gcc reports 13.3.0 too. build.sh must REJECT it."
probe "host_readelf"        readelf --version
probe "host_objdump"        objdump --version
probe "python3"             python3 --version
probe "make"                make --version
probe "dtc"                 dtc --version
say "  dtc is REQUIRED for Step 1.1 (decompiling spi_pl_dma.dtbo)."
probe "mkimage"             mkimage -V
say "  mkimage is REQUIRED for SOW 2.g V1 (signing image.ub)."
probe "openssl"             openssl version
say "  openssl is REQUIRED for 2.g V1 keypair generation."
probe "md5sum"              md5sum --version
probe "unzip"               unzip -v
say "  unzip is REQUIRED for Step 1.2 (.hwh extraction from the .xsa)."
say ""

say "-- PETALINUX ------------------------------------------------------"
have  "petalinux_project"   "$HOME/zcu102-spidev"
have  "petalinux_config"    "$HOME/zcu102-spidev/project-spec/configs/config"
UBC="$HOME/zcu102-spidev/build/tmp/work/zynqmp_generic_xczu9eg-amd-linux/u-boot-xlnx/2025.01-xilinx-v2025.1+git/build/.config"
have  "uboot_dotconfig"     "$UBC"
if [ -r "$UBC" ]; then
    say "  U-Boot symbols relevant to SOW 2.g (expected values from LPS in"
    say "  Section F of the continuation prompt):"
    for S in CONFIG_FIT CONFIG_FIT_SIGNATURE CONFIG_RSA \
             CONFIG_LEGACY_IMAGE_FORMAT CONFIG_ENV_IS_IN_FAT \
             CONFIG_SYS_REDUNDAND_ENVIRONMENT CONFIG_BOOTCOUNT_LIMIT \
             CONFIG_WDT CONFIG_WATCHDOG CONFIG_WATCHDOG_TIMEOUT_MSECS; do
        _l=$(grep -E "^${S}=|^# ${S} is not set" "$UBC" 2>/dev/null | head -1)
        [ -n "$_l" ] || _l="(symbol not present in .config)"
        printf '    %-38s %s\n' "$S" "$_l"
    done
fi
say ""

say "-- TRACKED ARTIFACT HASHES ----------------------------------------"
say "  Expected (from commit f7b73ee):"
say "    8b4be15e270dad88db03fc95a7731ab3  linux/src/spi_benchmark_v2.c"
say "    ff194b3828edc13d06ba26ef816c8616  linux/src/spi_benchmark_v2_aarch64"
say "    221d58effa7e4bdf3fecbb6f9bf88d98  linux/src/build.sh"
say "  Measured here:"
for F in linux/src/spi_benchmark_v2.c \
         linux/src/spi_benchmark_v2_aarch64 \
         linux/src/build.sh \
         sd-images/spi_benchmark_wrapper.bit.bin \
         sd-images/spi_pl_dma.dtbo \
         sd-images/boot.scr \
         sd-images/image.ub \
         hardware/xsa/spi_benchmark_wrapper.xsa; do
    if [ -r "$F" ]; then
        printf '    %s\n' "$(md5sum "$F" 2>/dev/null)"
    else
        printf '    ABSENT                            %s\n' "$F"
    fi
done
say ""

say "-- BUILD ARTIFACT FINGERPRINT (if the binary is present) ----------"
B=linux/src/spi_benchmark_v2_aarch64
if [ -r "$B" ]; then
    if command -v readelf >/dev/null 2>&1; then
        kv "comment" "$(readelf -p .comment "$B" 2>/dev/null | sed -n 's/.*\(GCC: .*\)$/\1/p' | head -1)"
        say "  EXPECTED: GCC: (GNU) 13.3.0"
        readelf -WS "$B" 2>/dev/null | grep -E '\.text|\.rodata' | sed 's/^/    /'
        say "  EXPECTED .text 0xed8 @ 0xf40 ; .rodata 0xd7c @ 0x1e30"
        kv "strtol_symbol" "$(readelf -W --dyn-syms "$B" 2>/dev/null | grep -o '__isoc23_strtol@GLIBC_[0-9.]*' | head -1)"
        say "  EXPECTED: __isoc23_strtol@GLIBC_2.38"
    else
        kv "comment" "SKIPPED -- no readelf"
    fi
    probe "file_type"        file "$B"
else
    kv "binary" "ABSENT $B"
fi
say ""

say "-- BOARD ACCESS ---------------------------------------------------"
have  "ttyUSB0"             /dev/ttyUSB0
have  "ttyUSB1"             /dev/ttyUSB1
probe "serial_tool_picocom" picocom --help
probe "serial_tool_minicom" minicom -v
probe "serial_tool_screen"  screen -v
if [ -r /proc/partitions ]; then
    say "  block devices (look for an SD reader):"
    sed 's/^/    /' /proc/partitions
else
    kv "partitions" "ABSENT /proc/partitions"
fi
say ""

say "================================================================"
say " END. Commit this output under docs/environment/ with the SITE"
say " label filled in. Then diff LPS against MORGAN."
say "================================================================"
