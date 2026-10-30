#!/bin/sh
# MSU-2 ZCU102 operator menu for the minimal PetaLinux image.
# This runs after Linux login. It never starts tests automatically at boot.
set -u

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEVICE=${MSU2_SPI_DEVICE:-/dev/spidev1.0}
BIT="$APP_DIR/spi_ratio2_j55_lvcmos33_20260929.bit.bin"
BIT_SHA=c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd
RESULTS=${MSU2_DEMO_RESULTS:-"$APP_DIR/msu2-demo-results"}
OVERLAYS=/sys/kernel/config/device-tree/overlays
DTBO_CLOCK="$APP_DIR/pl0-clock-only.dtbo"
DTBO_RESET="$APP_DIR/pl-reset-release.dtbo"
DTBO_SPI="$APP_DIR/axi-spi-controller.dtbo"
SMOKE="$APP_DIR/linux_spi_smoke_aarch64"
INTEGRITY="$APP_DIR/spi_benchmark_v3_rxverify_aarch64"
SUSTAINED="$APP_DIR/spi_sustainable_benchmark_linux_aarch64"
BM_REQUEST="$APP_DIR/baremetal.once"

die() { echo "ERROR: $*" >&2; return 1; }
need_file() { sudo test -r "$1" || die "Missing or unreadable package file: $1"; }
as_root() { sudo "$@"; }

overlay_applied() {
    [ "$(sudo cat "$OVERLAYS/$1/status" 2>/dev/null)" = applied ]
}

apply_overlay() {
    name=$1
    blob=$2
    need_file "$blob" || return 1
    if overlay_applied "$name"; then
        echo "overlay $name already applied"
        return 0
    fi
    if sudo test -e "$OVERLAYS/$name"; then
        die "Overlay $name exists but is not applied; reboot Linux before retrying"
        return 1
    fi
    sudo mkdir "$OVERLAYS/$name" || return 1
    if ! sudo sh -c 'cat "$1" > "$2"' sh "$blob" "$OVERLAYS/$name/dtbo"; then
        die "Failed to apply overlay $name"
        return 1
    fi
    [ "$(sudo cat "$OVERLAYS/$name/status" 2>/dev/null)" = applied ] || {
        die "Overlay $name did not report applied"
        return 1
    }
    echo "overlay $name applied"
}

hardware_ready() {
    need_file "$BIT" || return 1
    actual=$(sudo sha256sum "$BIT" 2>/dev/null | awk '{print $1}')
    [ "$actual" = "$BIT_SHA" ] || {
        die "Validated bitstream hash mismatch: $actual"
        return 1
    }
    command -v fpgautil >/dev/null 2>&1 || { die "fpgautil is unavailable"; return 1; }
    command -v sudo >/dev/null 2>&1 || { die "sudo is unavailable"; return 1; }
    sudo -v || return 1

    apply_overlay msu2_pl0_clock "$DTBO_CLOCK" || return 1
    rate=$(sudo cat /sys/kernel/debug/clk/pl0_ref/clk_rate 2>/dev/null)
    [ "$rate" = 99990000 ] || { die "PL0 rate is $rate, expected 99990000 Hz"; return 1; }
    enabled=$(sudo cat /sys/kernel/debug/clk/pl0_ref/clk_enable_count 2>/dev/null)
    [ "${enabled:-0}" -ge 1 ] 2>/dev/null || { die "PL0 is not enabled"; return 1; }

    state=$(sudo cat /sys/class/fpga_manager/fpga0/state 2>/dev/null)
    if [ "$state" != operating ]; then
        echo "Loading validated full FPGA image (SHA-256 $BIT_SHA)"
        sudo fpgautil -b "$BIT" -f Full || return 1
        state=$(sudo cat /sys/class/fpga_manager/fpga0/state 2>/dev/null)
    fi
    [ "$state" = operating ] || { die "FPGA Manager state is $state"; return 1; }

    apply_overlay msu2_pl_reset_release "$DTBO_RESET" || return 1
    sudo grep -F 'msu2-pl-resetn0' /sys/kernel/debug/gpio | grep -F 'out hi' >/dev/null || {
        die "PL reset line is not reported output-high"
        return 1
    }

    apply_overlay msu2_axi_spi "$DTBO_SPI" || return 1
    sudo test -e /sys/bus/spi/devices/spi1.0 || { die "AXI SPI child spi1.0 is absent"; return 1; }
    driver=$(sudo readlink -f /sys/bus/spi/devices/spi1.0/driver 2>/dev/null || true)
    if [ "${driver##*/}" != spidev ]; then
        sudo sh -c 'echo spidev > /sys/bus/spi/devices/spi1.0/driver_override && echo spi1.0 > /sys/bus/spi/drivers/spidev/bind' || return 1
    fi
    sudo test -c "$DEVICE" || { die "$DEVICE was not created"; return 1; }
    echo "Hardware ready: FPGA=$state PL0=${rate}Hz reset=out-high device=$DEVICE"
}

new_run_dir() {
    label=$1
    mkdir -p "$RESULTS" || return 1
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    run="$RESULTS/${stamp}_${label}"
    suffix=1
    while [ -e "$run" ]; do
        run="$RESULTS/${stamp}_${label}_$(printf '%02d' "$suffix")"
        suffix=$((suffix + 1))
    done
    mkdir "$run" || return 1
    {
        echo "schema=msu2-demo-run-v1"
        echo "test=$label"
        echo "started_utc=$stamp"
        echo "hostname=$(hostname 2>/dev/null || echo UNKNOWN)"
        echo "kernel=$(uname -a 2>/dev/null || echo UNKNOWN)"
        echo "device=$DEVICE"
        echo "cpu0_scaling_cur_freq_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo UNKNOWN)"
        echo "pl0_clock_hz=$(sudo cat /sys/kernel/debug/clk/pl0_ref/clk_rate 2>/dev/null || echo UNKNOWN)"
        echo "bitstream_file_sha256=$BIT_SHA"
        echo "bitstream_identity=source_file_hash_only_no_FPGA_readback"
        echo "physical_sck_hz=NOT_MEASURED_BY_PROGRAM"
        echo "topology=UNVERIFIED_BY_PROGRAM"
    } > "$run/manifest.txt"
}

record_test() {
    label=$1
    shift
    new_run_dir "$label" || return 1
    log="$run/raw_output.log"
    echo "Running: $*"
    {
        echo "command=$*"
        echo "program_sha256=$(sudo sha256sum "$1" 2>/dev/null | awk '{print $1}' || echo UNKNOWN)"
    } >> "$run/manifest.txt"
    sudo "$@" > "$log" 2>&1
    rc=$?
    cat "$log"
    {
        echo "finished_utc=$(date -u +%Y%m%dT%H%M%SZ)"
        echo "raw_output_sha256=$(sha256sum "$log" 2>/dev/null | awk '{print $1}' || echo UNKNOWN)"
        echo "exit_code=$rc"
        echo "result=$([ "$rc" -eq 0 ] && echo PASS || echo FAIL)"
    } >> "$run/manifest.txt"
    echo "Evidence: $run"
    return "$rc"
}

info() {
    echo "Hostname: $(hostname 2>/dev/null || echo UNKNOWN)"
    echo "Kernel: $(uname -a)"
    echo "CPU0 kHz: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo UNKNOWN)"
    echo "FPGA state: $(sudo cat /sys/class/fpga_manager/fpga0/state 2>/dev/null || echo UNKNOWN)"
    echo "PL0 Hz: $(sudo cat /sys/kernel/debug/clk/pl0_ref/clk_rate 2>/dev/null || echo UNKNOWN)"
    echo "SPI device: $DEVICE ($([ -c "$DEVICE" ] && echo present || echo absent))"
    echo "Bitstream file SHA-256: $BIT_SHA (source artifact; no FPGA readback)"
    echo "Physical SCK: not measured by this program"
}

valid_payload() {
    case "$1" in 1|8|16|64|128|256|512|1024|4096|16384|65536) return 0 ;; *) return 1 ;; esac
}

sustained_menu() {
    printf 'Payload bytes (comma-separated shared sizes; blank=all): '
    IFS= read -r payloads || return
    [ -n "$payloads" ] || payloads='1,8,16,64,128,256,512,1024,4096,16384,65536'
    payloads=$(printf '%s' "$payloads" | tr -d '[:space:]')
    oldifs=$IFS
    IFS=,
    set -- $payloads
    IFS=$oldifs
    [ "$#" -gt 0 ] || { echo 'Invalid payload list'; return; }
    for p do
        valid_payload "$p" || { echo "Invalid payload size: $p"; return; }
    done
    printf 'Seconds per payload (1..3600, default 60): '
    IFS= read -r window || return
    window=${window:-60}
    case "$window" in *[!0-9]*|'') echo 'Invalid duration'; return ;; esac
    [ "$window" -ge 1 ] && [ "$window" -le 3600 ] || { echo 'Duration must be 1..3600'; return; }
    printf 'Repetitions (1..3, default 3): '
    IFS= read -r reps || return
    reps=${reps:-3}
    case "$reps" in 1|2|3) ;; *) echo 'Repetitions must be 1..3'; return ;; esac
    count=$#
    duration=$((count * window * reps))
    echo "Maximum run time: $duration seconds. Each point gets a separate log."
    printf 'Type RUN to start: '
    IFS= read -r confirm || return
    [ "$confirm" = RUN ] || { echo 'Cancelled'; return; }
    rep=1
    while [ "$rep" -le "$reps" ]; do
        for p do
            record_test "sustained_${p}B_rep${rep}" "$SUSTAINED" "$DEVICE" "$p" "$window" 15623438 "$rep" || {
                echo 'Stopping after first failed point.'
                return 1
            }
        done
        rep=$((rep + 1))
    done
}

if [ "${1:-}" = --self-test ]; then
    for p in 1 8 16 64 128 256 512 1024 4096 16384 65536; do
        valid_payload "$p" || exit 1
    done
    for p in 0 3 2MiB xyz ''; do
        if valid_payload "$p"; then
            echo "self-test failed: accepted invalid payload $p" >&2
            exit 1
        fi
    done
    echo 'MSU2 minimal Linux menu self-test: PASS'
    exit 0
fi

linux_menu() {
while :; do
    cat <<'MENU'

MSU-2 ZCU102 demo — Linux mode
  0) Return to normal Linux shell
  1) Bring up validated AXI SPI hardware
  2) One-byte J55 loopback smoke test
  3) RX integrity and latency sweep (11 sizes × 1,000 trials)
  4) Sustained throughput (choose sizes, duration, repetitions)
  5) System and interface information
  q) Quit to Linux shell
MENU
    printf 'Select: '
    IFS= read -r choice || exit 0
    case "$choice" in
        0|q|Q)
            echo 'Returning to the petalinux Linux shell.'
            if [ "$(id -u)" -eq 0 ] && id petalinux >/dev/null 2>&1; then exec su - petalinux; fi
            exit 0
            ;;
        1) hardware_ready ;;
        2) hardware_ready && record_test smoke "$SMOKE" "$DEVICE" ;;
        3) hardware_ready && record_test integrity "$INTEGRITY" "$DEVICE" 15623438 ;;
        4) hardware_ready && sustained_menu ;;
        5) info ;;
        *) echo 'Choose 0, 1, 2, 3, 4, 5, or q.' ;;
    esac
done
}

request_baremetal() {
    scope=
    for candidate in \
        /sys/devices/platform/firmware:zynqmp-firmware/shutdown_scope \
        /sys/firmware/zynqmp/shutdown_scope; do
        if [ -e "$candidate" ]; then scope=$candidate; break; fi
    done
    if [ -z "$scope" ]; then
        scope=$(find /sys -type f -name shutdown_scope -print 2>/dev/null | head -n 1)
    fi
    [ -n "$scope" ] && [ -e "$scope" ] || {
        die 'PS-only reset control is unavailable (checked ZynqMP firmware sysfs paths)'
        return 1
    }
    echo "ZynqMP reboot scope control: $scope"
    echo "This will reboot the A53 into the bare-metal test menu and preserve the PL image."
    printf 'Type REBOOT to continue: '
    IFS= read -r confirm || return 1
    [ "$confirm" = REBOOT ] || { echo 'Cancelled'; return 0; }
    hardware_ready || return 1
    sudo touch "$BM_REQUEST" || return 1
    sudo sync
    if ! sudo sh -c 'echo ps_only > "$1"' sh "$scope"; then
        sudo rm -f "$BM_REQUEST"
        die 'Could not select the ZynqMP PS-only reset scope'
        return 1
    fi
    echo 'One-shot bare-metal request armed; rebooting now.'
    sudo reboot
    sudo sh -c 'echo system > "$1"' sh "$scope" 2>/dev/null || true
    sudo rm -f "$BM_REQUEST"
    die 'Reboot command returned; cleared the one-shot request'
    return 1
}

while :; do
    cat <<'TOP_MENU'

MSU-2 ZCU102 operator mode
  1) Linux SPI test menu
  2) Reboot into bare-metal SPI test menu
  q) Return to the normal Linux shell
TOP_MENU
    printf 'Select mode: '
    IFS= read -r mode || exit 0
    case "$mode" in
        1) linux_menu ;;
        2) request_baremetal ;;
        q|Q)
            echo 'Returning to the normal Linux shell.'
            if [ "$(id -u)" -eq 0 ] && id petalinux >/dev/null 2>&1; then exec su - petalinux; fi
            exit 0
            ;;
        *) echo 'Choose 1, 2, or q.' ;;
    esac
done
