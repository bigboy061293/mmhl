#!/bin/bash
# Build a Raspberry Pi OS Lite (Trixie, arm64) SD-card image with the Mimohl
# HaLow stack preinstalled, using the official pi-gen builder in Docker.
#
# Needs: an x86_64 or arm64 Linux host with Docker, ~25 GB free disk, and
# binfmt/qemu-user-static for arm64 on x86 hosts:
#   sudo apt install docker.io qemu-user-static binfmt-support
#
# Usage:
#   MIMOHL_PASS='a-strong-password' ./pios/build-image.sh
#   (optional) MIMOHL_SSH_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)"
#
# Output: work/pi-gen/deploy/*-mimohl.img.xz  -> flash with Raspberry Pi Imager or dd.
#
# Status: [untested end to end] The install step it runs (install-on-pi.sh) is
# the same one used on a live Pi; the pi-gen wiring follows pi-gen's README.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../versions.env
. "$REPO_DIR/versions.env"

: "${MIMOHL_PASS:?set MIMOHL_PASS to the password for user 'pi'}"
WORK="$REPO_DIR/work"
PIGEN="$WORK/pi-gen"

mkdir -p "$WORK"
if [ ! -d "$PIGEN/.git" ]; then
	git clone -q "$PIGEN_REPO" "$PIGEN"
fi
git -C "$PIGEN" fetch -q --depth 1 origin "$PIGEN_REF"
git -C "$PIGEN" checkout -q --force FETCH_HEAD

# Custom stage lives inside the pi-gen tree so build-docker.sh can see it.
rm -rf "$PIGEN/stage-mimohl"
cp -a "$REPO_DIR/pios/pi-gen/stage-mimohl" "$PIGEN/stage-mimohl"
mkdir -p "$PIGEN/stage-mimohl/00-mimohl/files/mimohl"
# Stage a clean copy of this repo (no git metadata, no build output).
tar -C "$REPO_DIR" --exclude=./work --exclude=./.git -cf - . \
	| tar -C "$PIGEN/stage-mimohl/00-mimohl/files/mimohl" -xf -

# Only export our image, not the plain Lite image from stage2.
touch "$PIGEN/stage2/SKIP_IMAGES"

cat > "$PIGEN/config" <<EOF
IMG_NAME=mimohl
RELEASE=trixie
TARGET_HOSTNAME=mimohl
FIRST_USER_NAME=pi
FIRST_USER_PASS='${MIMOHL_PASS}'
DISABLE_FIRST_BOOT_USER_RENAME=1
ENABLE_SSH=1
PUBKEY_SSH_FIRST_USER='${MIMOHL_SSH_PUBKEY:-}'
LOCALE_DEFAULT=en_US.UTF-8
TIMEZONE_DEFAULT=Etc/UTC
WPA_COUNTRY=US
DEPLOY_COMPRESSION=xz
STAGE_LIST="stage0 stage1 stage2 stage-mimohl"
EOF

cd "$PIGEN"
CONTINUE="${CONTINUE:-0}" ./build-docker.sh
ls -la "$PIGEN/deploy"
