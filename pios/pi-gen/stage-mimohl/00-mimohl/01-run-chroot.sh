#!/bin/bash -e
# Runs inside the arm64 image (under qemu-user on an x86 host: slow but works).
bash /var/tmp/mimohl/pios/install-on-pi.sh
# Keep a copy of the exact sources used, for rebuilds on the Pi.
mkdir -p /opt/mimohl
cp -a /var/tmp/mimohl/. /opt/mimohl/
rm -rf /var/tmp/mimohl
apt-get clean
