# Mimohl

A resilient Wi-Fi HaLow (802.11ah) link built from four Morse Micro MM8108
USB dongles on one Raspberry Pi 4.

The name says "MIMO", but this is not MIMO in the throughput sense. The four
radios are not bonded. Each one sits on its own channel, at its own
bandwidth, with its own antenna, and only one carries traffic at a time. The
others stay associated and watch their channels. When the active channel gets
jammed or noisy, traffic moves to the healthiest standby.

**Goal:** keep a usable link of roughly 1.5 to 10 Mbps when parts of the
902 to 928 MHz band are jammed or crowded. Peak throughput is not a goal.

## At a glance

| Item | Choice |
|---|---|
| Host | Raspberry Pi 4 (Raspberry Pi OS for bring-up, OpenWrt later) |
| Radios | 4 × MM8108 USB dongles, one antenna each, named `hl0`..`hl3` by USB port |
| Channels (default, US) | `hl0` 8 MHz @ 924, `hl1` 4 MHz @ 914, `hl2` 2 MHz @ 907, `hl3` 1 MHz @ 902.5 MHz |
| Link mode | One AP/STA pair per channel, all four kept associated |
| Overlay | One WireGuard tunnel; the sender picks the link by setting the peer endpoint |
| Far end | Listens on all four links and replies on whichever one it last heard from |
| Failover input | Per-link probe loss, RTT, peer RSSI, noise floor, MCS and retries |

The design is in [docs/design.md](docs/design.md): RF plan, driver stack,
link and overlay architecture, failover logic, test plan, risks and open
questions. Anything marked **⚠ Guess** there is unverified.

## Status

The repo holds the design and the **bring-up build**: a reproducible way to
get four dongles running as `hl0`..`hl3` on Raspberry Pi OS (or OpenWrt).
The failover daemon is not in `main` yet. Nothing has been tested on hardware.

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
| `docs/design.md` | Resilient link design: RF plan, architecture, failover logic, test plan |
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

## Legal note

Testing failover means creating interference on purpose. Do that only
conducted (cables, attenuators, splitters) or inside a shielded enclosure.
Radiating a jammer is illegal in most countries, including in the US ISM band.
