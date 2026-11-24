#!/bin/bash
# Install the Morse Micro MM8108 USB stack on Raspberry Pi OS (64-bit, Bookworm or Trixie).
#
# Runs either on a live Pi 4 or inside the pi-gen chroot (pios/build-image.sh).
# Everything is pinned in versions.env, so re-running gives the same result.
#
# Installs:
#   morse.ko (DKMS, rebuilt automatically on kernel upgrades), patched for multi-dongle use
#   /lib/firmware/morse/  chip firmware + all public board config files (BCFs)
#   /usr/local/bin/morse_cli
#   /usr/local/sbin/{hostapd,hostapd_cli,wpa_supplicant,wpa_cli}_s1g
#   Mimohl helpers, systemd units, udev/NetworkManager/modprobe config
#
# Usage: sudo ./pios/install-on-pi.sh [--keep-onboard-wifi] [--no-apt]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../versions.env
. "$REPO_DIR/versions.env"

KEEP_ONBOARD_WIFI=0
DO_APT=1
for a in "$@"; do
	case "$a" in
		--keep-onboard-wifi) KEEP_ONBOARD_WIFI=1 ;;
		--no-apt) DO_APT=0 ;;
		*) echo "unknown option $a" >&2; exit 2 ;;
	esac
done

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

SRC=/usr/src/mimohl-src
DRV_VER="${MORSE_RELEASE#mm8108-}-mimohl"     # e.g. 2.2.3-mimohl
JOBS="$(nproc)"

log() { echo "==> $*"; }

fetch() { # fetch <dir> <repo> <ref>   shallow fetch of an exact commit or branch
	local dir=$1 repo=$2 ref=$3
	if [ ! -d "$dir/.git" ]; then
		git init -q "$dir"
		git -C "$dir" remote add origin "$repo"
	fi
	git -C "$dir" fetch -q --depth 1 origin "$ref"
	git -C "$dir" checkout -q --force FETCH_HEAD
	git -C "$dir" clean -qfdx
}

# ---------------------------------------------------------------- packages
if [ "$DO_APT" = 1 ]; then
	log "Installing build dependencies"
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -q
	# linux-headers-rpi-v8 = headers for the Pi 4 64-bit kernel on Bookworm/Trixie.
	apt-get install -y -q --no-install-recommends \
		git ca-certificates build-essential bc bison flex dkms \
		linux-headers-rpi-v8 \
		libnl-3-dev libnl-genl-3-dev libnl-route-3-dev libusb-1.0-0-dev \
		libssl-dev pkg-config iw usbutils
fi

mkdir -p "$SRC"

# ---------------------------------------------------------------- driver (DKMS)
log "Fetching morse_driver $MORSE_RELEASE"
fetch "$SRC/morse_driver" "$MORSE_DRIVER_REPO" "$MORSE_DRIVER_REF"
# mmrc (rate control) is a submodule with a relative URL; the build fails without it.
git -C "$SRC/morse_driver" submodule update -q --init --depth 1

DKMS_SRC="/usr/src/morse-$DRV_VER"
log "Preparing $DKMS_SRC"
if dkms status -m morse -v "$DRV_VER" 2>/dev/null | grep -q .; then
	dkms remove -m morse -v "$DRV_VER" --all || true
fi
rm -rf "$DKMS_SRC"
cp -a "$SRC/morse_driver" "$DKMS_SRC"
rm -rf "$DKMS_SRC/.git"
for p in "$REPO_DIR"/patches/morse_driver/*.patch; do
	[ -e "$p" ] || continue
	log "  applying $(basename "$p")"
	patch -d "$DKMS_SRC" -p1 --forward --quiet < "$p"
done
sed "s/@VERSION@/$DRV_VER/" "$REPO_DIR/pios/dkms/dkms.conf" > "$DKMS_SRC/dkms.conf"

dkms add -m morse -v "$DRV_VER"
# Build for every kernel that has headers installed. In a pi-gen chroot
# `uname -r` is the build host's kernel, so never rely on it.
built=0
for b in /lib/modules/*/build; do
	[ -e "$b/Makefile" ] || continue
	kver="$(basename "$(dirname "$b")")"
	case "$kver" in *v8*|*rpi*) ;; *) continue ;; esac
	log "  dkms build for $kver"
	dkms build -m morse -v "$DRV_VER" -k "$kver"
	dkms install -m morse -v "$DRV_VER" -k "$kver" --force
	built=$((built + 1))
done
[ "$built" -gt 0 ] || { echo "no Pi kernel headers found under /lib/modules/*/build" >&2; exit 1; }

# ---------------------------------------------------------------- firmware + BCFs
log "Installing firmware and board config files"
fetch "$SRC/morse-firmware" "$MORSE_FIRMWARE_REPO" "$MORSE_FIRMWARE_REF"
install -d /lib/firmware/morse
install -m 0644 "$SRC"/morse-firmware/firmware/mm8108*.bin /lib/firmware/morse/
# The driver picks bcf_boardtype_<id>.bin from the board id in chip OTP,
# or the file named by the bcf= module parameter. Install all public BCFs flat.
find "$SRC/morse-firmware/bcf" -name '*.bin' -exec install -m 0644 {} /lib/firmware/morse/ \;

# ---------------------------------------------------------------- morse_cli
log "Building morse_cli"
fetch "$SRC/morse_cli" "$MORSE_CLI_REPO" "$MORSE_CLI_REF"
make -C "$SRC/morse_cli" -j"$JOBS" CONFIG_MORSE_TRANS_NL80211=1 morse_cli
install -m 0755 "$SRC/morse_cli/morse_cli" /usr/local/bin/morse_cli

# ---------------------------------------------------------------- hostapd / wpa_supplicant (S1G)
log "Building hostapd_s1g and wpa_supplicant_s1g"
fetch "$SRC/hostap" "$MORSE_HOSTAP_REPO" "$MORSE_HOSTAP_REF"
# Upstream Makefiles add -Werror, which trips on newer GCC/OpenSSL 3 deprecations.
# Overriding EXTRA_CFLAGS drops it (verified with GCC 13 + OpenSSL 3).
HOSTAP_CFLAGS="-Wno-unused-parameter -Wno-deprecated-declarations"
for d in hostapd wpa_supplicant; do
	cp "$SRC/hostap/$d/defconfig" "$SRC/hostap/$d/.config"
	make -C "$SRC/hostap/$d" -j"$JOBS" EXTRA_CFLAGS="$HOSTAP_CFLAGS"
done
install -m 0755 "$SRC"/hostap/hostapd/hostapd_s1g "$SRC"/hostap/hostapd/hostapd_cli_s1g /usr/local/sbin/
install -m 0755 "$SRC"/hostap/wpa_supplicant/wpa_supplicant_s1g "$SRC"/hostap/wpa_supplicant/wpa_cli_s1g \
	"$SRC"/hostap/wpa_supplicant/wpa_passphrase_s1g /usr/local/sbin/

# ---------------------------------------------------------------- Mimohl config
log "Installing Mimohl config and helpers"
cp -r "$REPO_DIR"/pios/rootfs/. /
chmod 0755 /usr/local/sbin/mimohl-*
install -d /etc/mimohl
[ -e /etc/mimohl/mimohl.conf ] || install -m 0600 "$REPO_DIR/config/mimohl.conf" /etc/mimohl/mimohl.conf

# Country code for the driver comes from mimohl.conf.
# shellcheck disable=SC1091
. /etc/mimohl/mimohl.conf
sed -i "s/country=[A-Z][A-Z]/country=${COUNTRY}/" /etc/modprobe.d/morse.conf

# Onboard Broadcom Wi-Fi off, so it never takes wlan0 and never shares the
# radio plan's names. (Pi OS Bookworm+ keeps config.txt in /boot/firmware.)
CFG=/boot/firmware/config.txt; [ -e "$CFG" ] || CFG=/boot/config.txt
if [ "$KEEP_ONBOARD_WIFI" = 0 ] && [ -e "$CFG" ] && ! grep -q '^dtoverlay=disable-wifi' "$CFG"; then
	log "Disabling onboard Wi-Fi in $CFG"
	printf '\n# Mimohl: HaLow dongles only\ndtoverlay=disable-wifi\n' >> "$CFG"
fi

systemctl daemon-reload 2>/dev/null || true
# Radios start from udev (SYSTEMD_WANTS in the rules mimohl-map-ports writes).

log "Done. Next: plug in the four dongles, run 'sudo mimohl-map-ports', reboot,"
log "then check with 'sudo mimohl-status'. See docs/bring-up.md."
