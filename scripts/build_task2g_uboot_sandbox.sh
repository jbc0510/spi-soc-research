#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 UBOOT_SOURCE_DIR BUILD_DIR" >&2
  exit 2
fi

source_dir=$(realpath "$1")
build_dir=$(realpath -m "$2")
jobs=${JOBS:-4}

make -C "$source_dir" O="$build_dir" sandbox_defconfig
"$source_dir/scripts/config" --file "$build_dir/.config" \
  -e FIT -e FIT_SIGNATURE -e RSA -d LEGACY_IMAGE_FORMAT \
  -d TOOLS_MKEFICAPSULE -d EFI_CAPSULE_AUTHENTICATE
make -C "$source_dir" O="$build_dir" olddefconfig NO_PYTHON=1
make -C "$source_dir" O="$build_dir" -j"$jobs" NO_PYTHON=1 \
  u-boot tools/mkimage tools/fit_check_sign arch/sandbox/dts/test.dtb

grep -q '^CONFIG_FIT_SIGNATURE=y$' "$build_dir/.config"
grep -q '^CONFIG_RSA=y$' "$build_dir/.config"
test -x "$build_dir/u-boot"
test -x "$build_dir/tools/mkimage"
test -x "$build_dir/tools/fit_check_sign"
