# Bring-up: four MM8108 dongles on one Raspberry Pi 4

Target: Pi 4 running Raspberry Pi OS Lite 64-bit, four MM8108 USB dongles,
each its own interface (`hl0`..`hl3`) on its own channel and bandwidth.
Build twice (one box `ROLE=ap`, the far end `ROLE=sta`) or bring up one box
first against a single known-good HaLow AP/STA.

Background and the reasons behind each step are in [research.md](research.md).

## 0. Hardware

- Pi 4 on its own 5 V 3 A supply.
- **Powered USB 2.0 hub** (5 V, 3 A or more) for the dongles. Four dongles
  straight on the Pi can exceed its 1.2 A USB limit at full TX power.
- One antenna per dongle. Label the hub ports 0-3; the names follow the ports.
- Keep antennas apart (tens of cm). The four radios are on separate channels,
  but strong near-field coupling can still desense the listening radios.

## 1. Get the software on the Pi

Option A, fastest for a first test (on a fresh Pi OS Lite 64-bit):

```bash
sudo apt update && sudo apt full-upgrade -y && sudo reboot   # headers must match the running kernel
git clone https://github.com/bigboy061293/mmhl && cd mmhl
sudo ./pios/install-on-pi.sh            # ~20-30 min on a Pi 4 (hostapd build dominates)
```

Option B, a ready image built on a PC (Docker, ~1-2 h):

```bash
MIMOHL_PASS='pick-one' ./pios/build-image.sh
# flash work/pi-gen/deploy/*-mimohl.img.xz with Raspberry Pi Imager
```

Either way you get: DKMS `morse` driver (rebuilt on kernel updates),
firmware + BCFs in `/lib/firmware/morse`, `morse_cli`, `hostapd_s1g`,
`wpa_supplicant_s1g`, and the `mimohl-*` helpers. Onboard Wi-Fi is disabled
in `config.txt` (pass `--keep-onboard-wifi` to keep it).

## 2. One dongle first

Plug in **one** dongle, then:

```bash
lsusb -d 325b:                 # expect 325b:8100
sudo modprobe morse
dmesg | grep -iE 'morse|bcf'   # firmware loaded, BCF name, MAC source, no errors
iw dev                         # a new wlanX / phyX
```

Check in `dmesg`:
- `mm8108b2-rl.bin` loaded.
- Which BCF loaded (`bcf_boardtype_XXXX.bin`). If it failed to find one, the
  dongle has no board id in OTP: set `options morse bcf=<file>` in
  `/etc/modprobe.d/morse.conf` (every dongle must then be the same model).
- Whether the MAC came from OTP or is random.

## 3. All four

Plug in the other three (through the powered hub), then:

```bash
sudo mimohl-map-ports --show   # 4 rows, all 480Mb/s
sudo mimohl-map-ports          # writes /etc/udev/rules.d/70-mimohl-halow.rules
sudo reboot
```

If fewer than four interfaces appear: `dmesg | grep -i morse` for probe
errors. "class_create failed" or "uaccess" errors mean the driver was built
with `CONFIG_MORSE_USER_ACCESS`. Rebuild with this repo's `dkms.conf`.

## 4. Configure and start the radios

Edit `/etc/mimohl/mimohl.conf`: set `ROLE` (ap or sta), `PASSPHRASE`, and
the channel plan if needed. Both ends must have the same `COUNTRY`,
`SSID_BASE`, `PASSPHRASE` and plan.

Radios start automatically when their interface appears
(`mimohl-radio@hlN.service`, started from udev). They refuse to start while
`PASSPHRASE` is still the default, so do this edit before the reboot in
step 3 or restart them after. After an edit:

```bash
sudo systemctl restart 'mimohl-radio@hl*'
sudo mimohl-status
journalctl -u mimohl-radio@hl0 -f
```

## 5. Acceptance checks

| # | Check | Pass |
|---|---|---|
| 1 | `mimohl-status` shows hl0..hl3 present, service active | all four |
| 2 | Each radio on its planned channel (`iw dev hlN info`, `hostapd_cli_s1g ... status`) | matches plan |
| 3 | Far end associates on every radio | 4 links |
| 4 | `iperf3` over each link in turn | >= 1.5 Mbps on the 1 MHz radio, more on wider ones |
| 5 | All four links pushing traffic at once for 10 min, then `vcgencmd get_throttled` | `throttled=0x0`, no USB resets in `dmesg` |
| 6 | Stop `mimohl-radio@hl0` (an AP); other three keep beaconing | far end stays associated on hl1-hl3 (exercises the beacon patch) |
| 7 | Unplug one dongle, replug | it comes back with the same name and service restarts |
| 8 | Reboot | same names, same channels |

Per-radio noise floor for the failover logic: `iw dev hlN survey dump`
(channel in use) and `morse_cli -i hlN stats`.

## 6. OpenWrt instead (optional)

`./openwrt/build.sh` builds an RPi 4 image from Morse Micro's OpenWrt fork
with the same driver, patch and flags. Configure radios with UCI/LuCI.
**Every `wifi-device` section must have identical module-level options**
(country, bcf, firmware type), otherwise netifd reloads the module and drops
the other radios (research.md section 3.4). Pi OS is the simpler bring-up
platform; OpenWrt is worth it later if you want LuCI and netifd.

## Not covered yet

- IP addressing and the failover controller that picks the active radio.
  That is the next piece of work.
- Real-hardware results: every [code-read] and [guess] item in research.md
  still needs confirming.
