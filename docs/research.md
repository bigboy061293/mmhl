# Research notes: MM8108 USB x4 on a Raspberry Pi 4

Snapshot taken 2026-11-24 against Morse Micro release **mm8108-2.2.3**.
Each claim is tagged:

- **[verified]** checked by building, running or reading the exact source
- **[code-read]** read in the source, not yet seen on hardware
- **[guess]** inference or a number from a third party; confirm on hardware

## 1. Public sources

| What | Where | Notes |
|---|---|---|
| Driver (`morse.ko`) | github.com/MorseMicro/morse_driver, tag `mm8108-2.2.3` | GPL. SDIO, SPI and **USB** buses in one module. Needs the `mmrc-submodule` submodule or it will not build. [verified] |
| Firmware + BCFs | github.com/MorseMicro/morse-firmware, tag `mm8108-2.2.3` | `mm8108b2-rl.bin` (default), `-tlm` and `-flm` variants. BCFs for Morse, AzureWave, Quectel, Netprisma modules. [verified] |
| `morse_cli` | github.com/MorseMicro/morse_cli | Talks to the driver over nl80211 vendor commands, takes `-i <ifname>`, so it works per dongle. Does not use `/dev/morse_io`. [verified: builds; code-read: transport] |
| hostapd / wpa_supplicant with S1G | github.com/MorseMicro/hostap, tag `mm8108-2.2.3` | Builds `hostapd_s1g`, `wpa_supplicant_s1g` and CLIs. Needs `-Werror` dropped on GCC 13 + OpenSSL 3. [verified on x86] |
| OpenWrt fork | github.com/MorseMicro/openwrt (`3.3-dev`), feed github.com/MorseMicro/morse-feed | Has a Raspberry Pi 4 + MM8108 board profile (`boards/ekh-bcm2711-mm8108`). [verified: files exist] |
| Upstream driver `mm81x` | mainline Linux since 7.3, `drivers/net/wireless/morsemicro/mm81x` (USB + SDIO) | Native S1G in mac80211. Not enabled in the Pi's `bcm2711_defconfig`. Userspace S1G support upstream is still thin, so it is not the bring-up choice. [verified: file present in rpi-7.3.y/7.4.y] |

USB ID of MM8108 dongles: **325b:8100** (`alias=usb:v325Bp8100…` in the built module). [verified]

## 2. Does it build for the Pi 4 kernel?

Cross-compiled the patched driver with the exact DKMS flags against Raspberry Pi
kernels, `bcm2711_defconfig`, arm64:

- `rpi-6.12.y` (6.12.119): builds clean, `-Werror` on. [verified]
- `rpi-6.18.y` (6.18.65): builds clean. [verified]
- The DKMS `dkms.conf` in `pios/dkms/` was run through `dkms build` against the
  6.18 tree. [verified]

The driver supports stock mac80211/cfg80211 (it translates S1G to 11n
internally), so **no kernel rebuild or custom mac80211 is needed on Pi OS**,
only kernel headers. [verified by build; runtime on hardware still to do]

Rerun any time with `tools/test-compile-driver.sh rpi-6.12.y`.

## 3. Multi-instance (four dongles, one module)

One `morse.ko` drives every dongle; each gets its own `struct morse`, wiphy
and netdev. Things that are **not** per-dongle:

1. **`CONFIG_MORSE_USER_ACCESS` breaks dongles 2..4.** [code-read, high confidence]
   `usb.c` probe calls `uaccess_init()` per device, which does
   `class_create("morse")` and creates `/dev/morse_io` with a fixed name, and
   keeps the result in one global pointer. The second probe's `class_create`
   fails with -EEXIST and the probe unwinds, so that dongle never gets a netdev.
   Unplugging any dongle also frees the shared global.
   **Fix used here:** build without `CONFIG_MORSE_USER_ACCESS` (nothing we use
   needs it). Morse's OpenWrt `boards/common` turns it on, so our OpenWrt board
   forces it off.
2. **Beacon IRQ mask was module-wide.** [code-read]
   `beacon.c` kept `beacon_irqs_enabled` as one static bitmask indexed by vif
   id. Every dongle's first AP interface is vif 0, so taking one AP down masks
   beacon IRQs on all the others (their beacons stop). Matters because the Pi
   may run AP on all four. **Fixed** by
   `patches/morse_driver/0001-beacon-per-chip-irq-mask.patch` (moves the mask
   into `struct morse`). Applies cleanly on top of Morse's own OpenWrt patches.
   [verified: builds, applies]
3. **Module parameters are global.** [code-read]
   `country`, `bcf`, `serial`, `macaddr_octet`/`macaddr_suffix`, `thin_lmac`,
   `enable_ps` and the rest apply to all four dongles. Consequences:
   - All four radios must use the same country. Fine for us.
   - **Do not set `macaddr_suffix` or `macaddr_octet`**: any dongle without a
     MAC in OTP would get the same MAC. Without them, such dongles get a
     random MAC per boot, so name interfaces by USB port, not MAC (that is what
     `mimohl-map-ports` does).
   - BCF selection: with `bcf=` empty the driver loads
     `bcf_boardtype_<id>.bin` using the board id in each chip's OTP, which is
     per-dongle. If a dongle has no board id in OTP, the only knob is the
     global `bcf=`, so **all four dongles must then be the same module**.
     [code-read; check `dmesg | grep -i bcf` on first boot]
4. **OpenWrt netifd reloads the module.** [code-read]
   `netifd-morse` rewrites `/etc/modules.d/morse` from each radio's UCI options
   and does `rmmod morse` if they changed. With four `wifi-device` sections
   whose module-level options differ (bcf, thin_lmac, country...), bringing up
   one radio reloads the module and drops the other three. All four sections
   must carry identical module-level options. The Pi OS path does not use
   netifd and avoids this.
5. Per-device and fine: debugfs (under each phy), LEDs, rate control, firmware
   load, watchdog, `morse_cli -i`. hostapd_s1g sets S1G channel parameters per
   interface via vendor commands. [code-read]

**Limit on count:** nothing in the driver caps the number of USB dongles
once (1) is avoided. `MORSE_NUM_OF_UACCESS_DEVICES = 4` only applies to the
disabled user-access feature. [code-read]

## 4. USB power budget

| Source | Figure |
|---|---|
| Morse MM8108-MF15457 datasheet | VBAT 3.0-3.6 V; TX up to 281 mA on VBAT_TX (MCS10, 1 MHz, 100 % duty); RX 20-34 mA; interface is USB 2.0 High-Speed |
| Vantron VT-USB-AH-8108 (press) | ~325 mA at 3.3 V transmitting at 26 dBm |
| ALFA AHUA8108 spec page | 135-140 mA max TX at 3.3 V (25 dBm), RX 81-101 mA, 5 V USB supply |
| Raspberry Pi 4 | **1.2 A total** shared by all four USB ports |

Estimate per dongle at 5 V [guess]: if the dongle uses an LDO from 5 V, its 5 V
current equals its 3.3 V current, so ~350 mA worst case at full TX power plus
USB PHY overhead. With a buck converter, ~250 mA. Four dongles transmitting
at once: **1.0-1.6 A**, which can exceed the Pi's 1.2 A and brown out the
USB bus (all four dongles reset together, which defeats failover).

In the agreed design only one radio carries traffic and the others mostly
listen (~0.1 A each), so steady state is well under 1.2 A. But beacons,
scans and failover moments can make several transmit at once.

**Recommendation:** put the four dongles on a **powered USB hub** (USB 2.0
is enough; the chip is High-Speed) with a 5 V supply of at least 3 A, and
power the Pi from its own 3 A supply. Check `vcgencmd get_throttled` after a
TX stress test (`0x0` = no under-voltage). Measure one dongle with a USB
power meter at full TX before trusting the numbers above.

USB bandwidth: 4 x ~10 Mbps of HaLow is about 40 Mbps, far below USB 2.0 high
speed, even with all four behind one hub. [guess, safe margin]

## 5. US channel plan (default in `config/mimohl.conf`)

From the driver's US channel table (`dot11ah/s1g_channels_rules.c`)
[verified], with Morse hostapd's US operating classes
1 MHz = 68, 2 MHz = 69, 4 MHz = 70, 8 MHz = 71 [verified in `src/utils/morse.c`]:

| Radio | BW | S1G ch | Occupies | op_class |
|---|---|---|---|---|
| 0 | 8 MHz | 44 | 920-928 MHz | 71 |
| 1 | 4 MHz | 24 | 912-916 MHz | 70 |
| 2 | 2 MHz | 10 | 906-908 MHz | 69 |
| 3 | 1 MHz | 1 | 902-903 MHz | 68 |

No two radios overlap, and the closest pair has a 3 MHz gap.
Channel 1 sits at the 902 MHz band edge, where the BCF may cap TX power
lower. [guess] Other valid US channels: 1 MHz odd 1-51; 2 MHz
2,6,10,...,50; 4 MHz 8,16,24,32,40,48; 8 MHz 12,28,44.

Primary channel width: 1 MHz for the 1 MHz radio, 2 MHz for the wider
ones. A 1 MHz primary on the wide channels would make beacons and
control frames more robust at range; worth testing. [guess]

## 6. Vantron VT-USB-AH-8108 source package (V1.15.3, 2025-07-14)

Vu's dongles are Vantron VT-USB-AH-8108. Their Linux package was checked
against the public release used here:

- It ships Morse driver **rel_1_15_3** (Apr 2025), firmware `mm8108b2-rl.bin`,
  BCF `bcf_mf15457.bin` (the dongle uses Morse's MF15457 "Etna" module), and
  matching hostapd/wpa_supplicant/morse_cli/morsectrl. [verified]
- Same USB ID 325b:8100. [verified]
- It needs **Morse's kernel patches** applied to mac80211/cfg80211 (for
  example `IEEE80211_CHAN_IGNORE`, 8 MHz channel flags) and lists kernels only
  up to **6.6.x**. Cross-compiling it against the Pi kernels fails:
  rpi-6.12.y (CHAN_IGNORE missing, S1G API changes) and rpi-6.18.y (also timer
  API changes). [verified]
- It has **both multi-dongle bugs** from section 3 (`/dev/morse_io` + global
  uaccess pointer in `usb.c`, global `beacon_irqs_enabled`). Our beacon patch
  applies to it with offsets. [verified]
- The public mm8108-2.2.3 BCF table maps OTP board types 0804 and 0807 to
  `bcf_mf15457.bin`, so the newer stack should pick the right BCF for this
  dongle by itself. [guess until a dongle is plugged in]

Conclusion: use the public mm8108-2.2.3 stack (this repo) with the Vantron
hardware. The firmware is loaded by the host, so the dongle runs whatever
release the driver brings. Keep driver, firmware and BCF from the **same**
release. Do not mix Vantron's 1.15.3 BCF with the 2.2.3 driver.
Fallback if vendor support requires 1.15.3: a custom Pi kernel from
`rpi-6.6.y` + Morse's 6.6.x patches, driver built with
`CONFIG_MORSE_USER_ACCESS` off + our beacon patch. [untested]

## 7. Open questions to settle on hardware

- Which dongle model is in use, and does its OTP carry a board id and a MAC?
  (`dmesg | grep -iE 'bcf|mac address|board'`)
- Real 5 V current of one dongle at full TX power.
- Do four dongles enumerate and run together behind the planned hub?
- USB autosuspend: the driver enables it with remote wakeup. If wake latency
  hurts failover time, disable it per port (`power/control=on`).
