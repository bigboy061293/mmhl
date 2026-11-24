#!/bin/bash -e
# Copy this repo (staged by pios/build-image.sh) into the image for the chroot step.
# /var/tmp, not /tmp: pi-gen mounts a fresh tmpfs over /tmp in on_chroot, which hides files staged there.
rm -rf "${ROOTFS_DIR}/var/tmp/mimohl"
cp -a files/mimohl "${ROOTFS_DIR}/var/tmp/mimohl"
