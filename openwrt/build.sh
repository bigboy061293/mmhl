#!/bin/bash
# Build an OpenWrt SD-card image for Raspberry Pi 4 with the Morse Micro
# MM8108 USB stack, using Morse Micro's OpenWrt fork and their build helper.
#
# Needs a Linux host with the usual OpenWrt build deps
# (https://openwrt.org/docs/guide-developer/build-system/install-buildsystem),
# ~40 GB disk and 1-3 hours for a first build.
#
# Usage: ./openwrt/build.sh [-j N]
# Output: work/openwrt/bin/targets/bcm27xx/bcm2711/*rpi-4*-factory.img.gz
#
# Status: [untested end to end] Board profile follows Morse's own
# ekh-bcm2711-mm8108 board; see docs/research.md for the netifd caveat.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../versions.env
. "$REPO_DIR/versions.env"
JOBS="$(nproc)"
[ "${1:-}" = -j ] && JOBS="$2"

WORK="$REPO_DIR/work"
OWRT="$WORK/openwrt"
mkdir -p "$WORK"
if [ ! -d "$OWRT/.git" ]; then
	git clone -q "$MORSE_OPENWRT_REPO" "$OWRT"
fi
git -C "$OWRT" fetch -q origin "$MORSE_OPENWRT_REF"
git -C "$OWRT" checkout -q --force FETCH_HEAD

# Our board profile, plus Morse's USB board diffconfig (morse_setup.sh
# requires non-target diffconfigs to be symlinks).
BOARD="$OWRT/boards/mimohl-rpi4-usb"
rm -rf "$BOARD"
mkdir -p "$BOARD"
cp "$REPO_DIR/openwrt/board/mimohl-rpi4-usb/target_diffconfig" "$BOARD/"
ln -s ../ekh-bcm2711-mm8108/usb_diffconfig "$BOARD/usb_diffconfig"

cd "$OWRT"
# -i: update/install feeds. Feeds come from the fork's pinned feeds.conf.default.
./scripts/morse_setup.sh -i -b mimohl-rpi4-usb

# Drop our driver patches into the morse_driver package (quilt picks them up).
PATCH_DST="feeds/morse/essentials/morse_driver/patches/mm81x"
mkdir -p "$PATCH_DST"
for p in "$REPO_DIR"/patches/morse_driver/*.patch; do
	cp "$p" "$PATCH_DST/900-mimohl-$(basename "$p")"
done

make defconfig
# Fail early if the overrides did not stick.
grep -q '^CONFIG_MORSE_USB=y' .config
! grep -q '^CONFIG_MORSE_USER_ACCESS=y' .config
make -j"$JOBS" download
make -j"$JOBS"
ls -la bin/targets/bcm27xx/bcm2711/
