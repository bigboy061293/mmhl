#!/bin/bash
# Cross-compile the patched morse driver against a Raspberry Pi kernel tree
# (bcm2711_defconfig, arm64), with the same flags DKMS uses on the Pi.
# Catches API breaks before you flash anything. No Pi needed.
#
# Needs: gcc-aarch64-linux-gnu bc bison flex libssl-dev libelf-dev git
# Usage: tools/test-compile-driver.sh [rpi-6.12.y|rpi-6.18.y|...]   (default rpi-6.12.y)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../versions.env
. "$REPO_DIR/versions.env"
BRANCH="${1:-rpi-6.12.y}"
W="$REPO_DIR/work/compile-test"
K="$W/linux-$BRANCH"
D="$W/morse_driver"
X=(ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)
mkdir -p "$W"

[ -d "$K" ] || git clone -q --depth 1 -b "$BRANCH" "$RPI_LINUX_REPO" "$K"
make -s -C "$K" "${X[@]}" bcm2711_defconfig
make -s -C "$K" "${X[@]}" -j"$(nproc)" modules_prepare

rm -rf "$D"
git init -q "$D"
git -C "$D" fetch -q --depth 1 "$MORSE_DRIVER_REPO" "$MORSE_DRIVER_REF"
git -C "$D" checkout -q FETCH_HEAD
git -C "$D" remote add origin "$MORSE_DRIVER_REPO"
git -C "$D" submodule update -q --init --depth 1
for p in "$REPO_DIR"/patches/morse_driver/*.patch; do patch -d "$D" -p1 --quiet < "$p"; done

# KBUILD_MODPOST_WARN: there is no Module.symvers without a full kernel build,
# so unresolved-symbol warnings from modpost are expected and harmless here.
make -C "$K" "${X[@]}" M="$D" KERNEL_SRC="$K" KBUILD_MODPOST_WARN=1 -j"$(nproc)" \
	CONFIG_WLAN_VENDOR_MORSE=m CONFIG_MORSE_USB=y CONFIG_MORSE_VENDOR_COMMAND=y \
	CONFIG_MORSE_COUNTRY=US DEBUG=n modules 2>&1 | grep -v 'modpost: ".*" \[morse.ko\] undefined' || true
test -f "$D/morse.ko"
strings "$D/morse.ko" | grep -E '^(vermagic|alias=usb)'
echo "OK: morse.ko built for $BRANCH"
