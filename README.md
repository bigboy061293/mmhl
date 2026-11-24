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
| Radios | 4 × MM8108 USB dongles, one antenna each |
| Channels (example, US) | 1 MHz @ 902.5, 2 MHz @ 907, 4 MHz @ 914, 8 MHz @ 924 MHz |
| Link mode | One AP/STA pair per channel, all four kept associated |
| Overlay | One WireGuard tunnel; the sender picks the link by setting the peer endpoint |
| Far end | Listens on all four links and replies on whichever one it last heard from |
| Failover input | Per-link probe loss, RTT, peer RSSI, noise floor, MCS and retries |

## Documents

- [docs/design.md](docs/design.md): the full design. RF plan, driver stack,
  link and overlay architecture, failover logic, test plan, risks and open
  questions.

Anything in the design marked **⚠ Guess** is unverified and should be checked
against hardware or vendor documentation before it is relied on.

## Status

Design only. No code yet. The next step is single-radio bring-up on
Raspberry Pi OS (see the test plan, phase 1).

## Legal note

Testing failover means creating interference on purpose. Do that only
conducted (cables, attenuators, splitters) or inside a shielded enclosure.
Radiating a jammer is illegal in most countries, including in the US ISM band.
