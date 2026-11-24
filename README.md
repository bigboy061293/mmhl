# Mimohl

Several Morse Micro MM8108 Wi-Fi HaLow (802.11ah) USB dongles on one
Raspberry Pi 4, each on its own channel, bandwidth and antenna. The goal is a
resilient 1.5-10 Mbps link: one radio carries traffic, the others stand by,
and the box fails over when a channel gets noisy or jammed.

This repo currently holds the **bring-up build**: a reproducible way to get
four dongles running as `hl0`..`hl3` on Raspberry Pi OS (or OpenWrt).

## Layout

| Path | What |
|---|---|
| `versions.env` | Every upstream source pinned to an exact commit (Morse release `mm8108-2.2.3`) |
| `patches/morse_driver/` | Our driver patch for multi-dongle use |
| `pios/install-on-pi.sh` | Installs the whole stack on a Pi OS Lite 64-bit system (DKMS driver, firmware, morse_cli, hostapd/wpa_supplicant S1G, helpers) |
| `pios/build-image.sh` | Builds a flashable Pi OS image with the above preinstalled (pi-gen in Docker) |
| `pios/rootfs/` | Files installed on the Pi: udev naming helper, per-radio systemd unit, status tool, modprobe options |
| `config/mimohl.conf` | Radio plan: role, country, SSIDs, channel + bandwidth per radio |
| `openwrt/` | Alternative OpenWrt image (Morse Micro's fork, RPi 4 board profile) |
| `tools/test-compile-driver.sh` | Cross-compiles the patched driver against a Pi kernel; no Pi needed |
| `docs/bring-up.md` | Step-by-step bring-up and acceptance checks |
| `docs/research.md` | Sources, multi-instance limits, USB power budget, channel plan; claims tagged verified / code-read / guess |

## Quick start

```bash
# on a Pi 4 with fresh, fully upgraded Pi OS Lite 64-bit
git clone https://github.com/bigboy061293/mmhl && cd mmhl
sudo ./pios/install-on-pi.sh
sudoedit /etc/mimohl/mimohl.conf        # ROLE, PASSPHRASE, channel plan
# plug the four dongles into a powered USB hub
sudo mimohl-map-ports && sudo reboot
sudo mimohl-status
```

## Key findings (details in docs/research.md)

- The vendor driver builds as-is for Pi kernels 6.12 and 6.18 (no kernel rebuild).
- Built with `CONFIG_MORSE_USER_ACCESS`, only the first dongle probes. We build without it.
- A module-wide beacon IRQ mask lets one AP going down stop the others' beacons. Patched.
- Driver module options are shared by all dongles: never set a MAC suffix; BCF comes per dongle from OTP.
- Four dongles at full TX power can exceed the Pi 4's 1.2 A USB budget. Use a powered hub.
