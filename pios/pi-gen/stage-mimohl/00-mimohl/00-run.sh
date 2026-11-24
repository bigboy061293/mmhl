#!/bin/bash -e
# Copy this repo (staged by pios/build-image.sh) into the image for the chroot step.
rm -rf "${ROOTFS_DIR}/tmp/mimohl"
cp -a files/mimohl "${ROOTFS_DIR}/tmp/mimohl"
