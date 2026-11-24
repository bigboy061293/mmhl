# Mimohl design: a resilient HaLow link from four MM8108 radios

Status: draft v0.1, 2026-11-24. Design only, nothing built yet.

Items marked **⚠ Guess** are unverified. They come from general knowledge of
802.11ah and of Morse Micro's public software, not from testing these
dongles. Each one has a matching check in the test plan or the open questions.

## 1. Goal and non-goals

**Goal.** One logical link between two sites that keeps 1.5 to 10 Mbps of
usable throughput while parts of the 902 to 928 MHz band are jammed, crowded
or fading.

**Non-goals.**

- Maximum throughput. The radios are not bonded or striped.
- True MIMO. Each radio is a single stream; "MIMO" here means diversity of
  frequency, bandwidth and antenna.
- Mesh or multipoint. This is one point-to-point link (a near end and a far
  end). Multipoint can come later.

**Design rule.** Only the sender chooses the link. The far end accepts on all
four links and needs no failover logic of its own.

## 2. System overview

```
        Near end (Pi 4)                                Far end (Pi 4)
  ┌──────────────────────────┐                   ┌──────────────────────────┐
  │ apps ─► wg0 (10.99.0.1)  │                   │ wg0 (10.99.0.2) ◄─ apps  │
  │          │               │                   │          ▲               │
  │   linkd: picks endpoint  │                   │  (no logic: WireGuard    │
  │          │               │                   │   replies to last source)│
  │  wlan0 1 MHz  902.5 ─────┼── ant A ··· ant A'┼───── wlan0  STA ↔ AP     │
  │  wlan1 2 MHz  907   ─────┼── ant B ··· ant B'┼───── wlan1               │
  │  wlan2 4 MHz  914   ─────┼── ant C ··· ant C'┼───── wlan2               │
  │  wlan3 8 MHz  924   ─────┼── ant D ··· ant D'┼───── wlan3               │
  └──────────────────────────┘                   └──────────────────────────┘
         one link active (carries wg0), three standby (associated, probed)
```

Both ends have the same hardware. Each radio pair forms its own small Wi-Fi
link with its own IP subnet. A single WireGuard tunnel runs on top. The near
end's link daemon (`linkd`, to be written) points the tunnel at the far end's
address on the chosen link. The far end replies to wherever the latest
authenticated packet came from, so the return path follows automatically.

## 3. RF plan

### 3.1 Channel plan (US, 902 to 928 MHz)

The 802.11ah US channel grid places channel centres at 902 MHz + 0.5 MHz ×
channel number. **⚠ Guess:** the valid centres below are from the IEEE
802.11ah US table as remembered; confirm them against the channel map in
Morse Micro's driver for `country=US`.

| Radio | Bandwidth | Centre | S1G ch. | Occupies | Role |
|---|---|---|---|---|---|
| wlan3 | 8 MHz | 924 MHz | 44 | 920 – 928 | Primary (most capacity) |
| wlan2 | 4 MHz | 914 MHz | 24 | 912 – 916 | First backup |
| wlan1 | 2 MHz | 907 MHz | 10 | 906 – 908 | Second backup |
| wlan0 | 1 MHz | 902.5 MHz | 1 | 902 – 903 | Lifeline (see 3.3) |

This is the example set from the original brief, with bandwidths assigned so
every channel lands on a valid centre and none overlap. Gaps between channels
are 3 to 4 MHz, which helps adjacent-channel rejection.

Why spread them out: a narrowband jammer kills at most one channel, and a
wideband jammer has to cover the whole 26 MHz band to kill all four. Narrow
channels also have a better link budget (less noise in the receive
bandwidth), so they keep working at longer range or deeper fades.

### 3.2 Known neighbours in the band

These are common in 902 to 928 MHz in the US and should be surveyed on site
before the channel plan is fixed:

- **LoRaWAN US915.** Uplinks around 902.3 to 914.9 MHz, downlinks around
  923.3 to 927.5 MHz. Downlinks overlap the 8 MHz channel.
- **UHF RFID readers.** Hop across 902 to 928 MHz and can raise the noise
  floor everywhere in warehouses and retail.
- **Smart meters and other frequency-hopping ISM gear.** Bursty, wideband in
  aggregate.
- **Cellular band 5 / band 26 and paging** just outside the band edges. The
  1 MHz channel at 902.5 MHz sits right at the lower edge. **⚠ Guess:** this
  may be noisier than the middle of the band in some areas.

The channel plan must be configurable per site, not hard-coded.

### 3.3 Capacity per channel versus the 1.5 Mbps floor

Approximate 802.11ah PHY rates, one spatial stream, long guard interval
(**⚠ Guess:** from the standard's MCS tables as remembered; usable TCP
throughput is often 50 to 70 % of PHY rate):

| Bandwidth | MCS0 | MCS7 | Highest MCS | Rough usable at top MCS |
|---|---|---|---|---|
| 1 MHz | 0.3 Mbps | 3.0 Mbps | MCS9 ≈ 4.0 Mbps (MCS10 = 0.15 Mbps, extended range) | ~2 to 2.5 Mbps |
| 2 MHz | 0.65 Mbps | 6.5 Mbps | MCS8 ≈ 7.8 Mbps | ~4 to 5 Mbps |
| 4 MHz | 1.35 Mbps | 13.5 Mbps | MCS9 ≈ 18 Mbps | ~9 to 12 Mbps |
| 8 MHz | 2.9 Mbps | 29 Mbps | MCS9 ≈ 39 Mbps | ~20 to 25 Mbps |

**Consequence.** The 1 MHz radio holds 1.5 Mbps only at MCS6 or above, which
needs a clean, strong link. In exactly the conditions where it would be the
last survivor (heavy interference, deep fade) it will be at low MCS and well
under 1 Mbps. Treat it as a lifeline that keeps control and telemetry
alive, not as a link that meets the floor. If the floor is a hard
requirement, swap it for a second 2 MHz channel (for example 2 MHz at 903 or
919 MHz). This is listed as open question Q1.

### 3.4 Antennas and co-location

- One antenna per radio, as planned. Use different polarisation or
  pattern where possible (for example two vertical, one horizontal, one
  directional) to add polarisation and pattern diversity on top of frequency
  diversity.
- Separate the four antennas as far as the enclosure allows. At 915 MHz a
  wavelength is about 33 cm; aim for at least λ/2 (~16 cm) between antennas.
  **⚠ Guess:** a few tens of dB of antenna-to-antenna isolation should be
  enough because only one radio transmits at a time.
- **No SAW filters needed** (earlier conclusion). Only one radio transmits at a
  time, so there is no case where one radio must receive weak signals while
  a neighbour is transmitting traffic it cares about.

**The one co-location problem that remains.** When the active radio
transmits, the standby radios a few centimetres away see that energy. Their
noise-floor readings will jump during active transmit bursts even though
their own channels are clean. The failover logic must not read this as
jamming. Mitigations, in order of preference:

1. Weight noise-floor readings lightly and rely mainly on probe loss over
   each standby link (section 6.2). A real jammer causes probe loss; our own
   transmitter mostly does not, because the probes are short and get retried.
2. Sample standby noise floor only when the active radio has been idle for a
   few milliseconds (needs a transmit-activity signal from the driver,
   **⚠ Guess** whether one is available).
3. Measure each standby's noise floor with the active radio idle and with it
   saturated, during commissioning, and subtract the difference.

This is measured explicitly in test phase 3.

## 4. Hardware and host

- **Raspberry Pi 4**, 4 GB or more.
- **USB.** All four Pi 4 USB ports go through one VL805 controller on a
  single PCIe lane. Four HaLow dongles at ≤ 10 Mbps total is far below that
  limit, so bandwidth is fine.
- **Power.** The Pi 4 limits total USB current to about 1.2 A across all
  ports. **⚠ Guess:** an MM8108 dongle transmitting at full power may draw a
  few hundred mA. Four of them plus peaks can brown out. Plan on a **powered
  USB hub** (or a hub with a separate supply) from the start.
- **Stable names.** USB enumeration order can change between boots. Bind each
  radio to its channel by USB port path or MAC address with udev rules
  (`wlan-hl1`, `wlan-hl2`, ... rather than `wlan0..3`) so a reboot never puts
  the 8 MHz config on the 1 MHz antenna.
- **Antenna cabling.** Label each dongle, cable and antenna as a set. The
  config file maps name → port path → channel → antenna.

## 5. Software stack

### 5.1 Driver and firmware

Morse Micro publishes its Linux software on GitHub. **⚠ Guess** on the
exact names and layout, to confirm during bring-up:

| Layer | Component | Notes |
|---|---|---|
| Kernel driver | `morse_driver` (out-of-tree module, `morse.ko` plus a `dot11ah` helper module) | mac80211-based softMAC driver. Needs USB bus support built in for MM8108 USB. |
| Firmware | MM8108 firmware image + board configuration file (BCF) under `/lib/firmware/morse/` | The BCF is specific to the dongle's RF design. Use the one from the dongle vendor. |
| Regulatory | Module parameter for country (for example `country=US`) | Sets the S1G channel map and power limits. |
| Userspace | Morse's S1G-aware `hostapd` and `wpa_supplicant` builds | Stock hostapd does not know S1G channels. |
| Tools | `morse_cli` | Per-device stats, channel info, firmware version. Also standard `iw`. |

**Multiple devices.** The critical bring-up question is whether one driver
instance handles four MM8108 USB devices at once, each with its own channel
and bandwidth. **⚠ Guess:** mac80211 drivers normally support several
devices, but vendor drivers sometimes keep global state (for example one
firmware load path or one country setting). Test phase 2 answers this first.

### 5.2 Operating system

- **Raspberry Pi OS (64-bit) for bring-up.** Easy to build the out-of-tree
  module against `raspberrypi-kernel-headers`, easy to debug, full tooling.
- **OpenWrt for deployment.** **⚠ Guess:** Morse Micro maintains an OpenWrt
  tree with its driver and S1G hostapd packaged. Moving to OpenWrt is a
  packaging task once the design works on Pi OS. Using the vendor tree is
  probably easier than porting the driver to mainline OpenWrt.

### 5.3 Link layer: one AP/STA pair per channel

Each channel is a separate, ordinary 802.11ah link:

- **Far end runs four APs** (one per radio, fixed channel, hidden or not).
- **Near end runs four STAs**, each locked to its AP by BSSID and channel.
- **All four stay associated all the time.** Failover never waits for scan,
  authentication or association, which can take seconds. It only changes
  where the overlay sends packets.
- Each link has its own /30 or /29 subnet, for example `10.10.k.0/30`
  with the AP at `.1` and the STA at `.2` for k = 1..4.
- WPA3-SAE per link (802.11ah requires SAE or OWE for protected links,
  **⚠ Guess** on what the Morse builds require by default).
- Rate control: leave Minstrel (or the driver's own) on, but consider capping
  maximum MCS on the backup links to keep them robust rather than fast.

Why AP/STA rather than IBSS or 802.11s mesh: it is the best-tested mode on
any Wi-Fi driver, it gives clean per-link stats (`iw station dump`), and the
point-to-point topology does not need mesh routing.

### 5.4 Overlay: WireGuard with endpoint steering

One WireGuard interface (`wg0`) on each end, with tunnel addresses
`10.99.0.1` (near) and `10.99.0.2` (far). Application traffic uses only the
tunnel addresses, so it never notices failover.

- **Near end chooses** by setting the peer endpoint to the far end's address
  on the chosen link:
  `wg set wg0 peer <far-pubkey> endpoint 10.10.k.1:51820`.
  Normal routing then sends the encrypted packets out the matching radio
  because each link has its own subnet.
- **Far end follows.** WireGuard updates a peer's endpoint to the source
  address of the most recent authenticated packet. The far end's replies
  therefore leave on whichever link the near end used last. The far end has
  no endpoint set for the near end and runs no daemon. This is standard
  WireGuard roaming behaviour, not a custom feature.
- **Keepalive.** `PersistentKeepalive = 1` on the near end so the far end
  learns the new path within about one second even when no data flows. The
  link daemon also sends a packet right after each switch.
- **MTU.** Set `wg0` MTU to the HaLow link MTU minus 80 bytes of WireGuard
  overhead (for example 1420 if the links carry 1500).
- **Cost.** Encryption at 10 Mbps is light work for a Pi 4.

Alternatives considered:

| Option | Why not first choice |
|---|---|
| Linux bonding, active-backup | Needs layer-2 bridging across STA links, which needs 4-address (WDS) mode on every link (**⚠ Guess** on driver support). Its link checks (MII or ARP) cannot see "noisy but up". |
| Policy routing only, no tunnel | Works, but the far end then needs its own logic or conntrack tricks to reply on the right link. Loses the "far end needs no logic" property. |
| MPTCP | Only helps TCP and would spread traffic over all links, which works against "one active radio". Worth revisiting if throughput later matters. |

## 6. Failover logic (`linkd`)

A small daemon on the near end. Python first, rewrite later only if needed.

### 6.1 Inputs, per link, sampled every 100 ms to 1 s

| Signal | Source | What it tells us |
|---|---|---|
| Probe loss and RTT | UDP probes sent on each link's own subnet (not through wg0), echoed by a tiny responder on the far end | The ground truth: is the link carrying packets now? |
| Peer RSSI / signal | `iw dev <if> station dump` | Fading and range |
| TX bitrate / MCS, retries, failed TX | `iw dev <if> station dump` | Effective capacity and interference |
| Noise floor | `iw dev <if> survey dump` or `morse_cli` stats (**⚠ Guess** which is populated by this driver) | Jamming or crowding on the channel |
| Association state | `iw dev <if> link`, netlink events | Hard down |

The probe responder on the far end is the only far-end software besides
WireGuard and hostapd. It is a stateless echo, so it does not break the "far
end has no failover logic" rule.

Probe rates: 10 Hz on the active link, 2 to 5 Hz on standbys. At 64 bytes per
probe this costs a few kbps per link. **⚠ Guess** that 1 MHz airtime makes
this fine; check it in phase 4.

### 6.2 Link health score

Each link gets a state and an estimated capacity.

- **Down:** not associated, or ≥ 3 consecutive probes lost on the active link
  (≥ 5 on a standby).
- **Degraded:** probe loss above 10 % over the last 2 s, or noise floor more
  than 10 dB above that link's commissioning baseline for more than 1 s, or
  estimated capacity below the 1.5 Mbps floor.
- **Good:** none of the above.

Estimated capacity = TX PHY rate × (1 − retry fraction) × an efficiency
factor (start at 0.6, calibrate in phase 4).

All thresholds are starting points (**⚠ Guess**) and live in the config file.

### 6.3 Choosing the active link

1. Rank links by preference: Good before Degraded before Down. Within a state,
   higher estimated capacity first. Ties go to the configured priority order
   (8 → 4 → 2 → 1 MHz).
2. **Switch away immediately** (no hold-down) if the active link goes Down.
   Target: detect within 300 ms, switch within 50 ms of the decision.
3. **Switch away after 1 s** if the active link is Degraded and a Good link
   exists.
4. **Switch back (fail-back) only after the better link has been Good for
   30 s**, and never more than once per 60 s per link. This stops flapping
   when a jammer duty-cycles.
5. If every link is Down, keep trying the last active link and the lifeline,
   log loudly, and switch the moment any probe comes back.

### 6.4 Switching

A switch is two steps: `wg set ... endpoint <new>`, then one immediate packet
to the far end over the tunnel so it learns the new source address. In-flight
packets on the old link may be lost; TCP will retransmit. Expected outage is
the detection time plus about one RTT.

### 6.5 Outputs

- Log every switch with the reason and the score table.
- Expose state as JSON on a local socket or file for dashboards.
- Optional: Prometheus text endpoint for long-run tests.

### 6.6 Configuration sketch

```yaml
links:
  - name: hl8
    usb_path: "1-1.4:1.0"      # from udev
    channel_mhz: 924
    bw_mhz: 8
    far_ip: 10.10.4.1
    priority: 1
  - name: hl4
    usb_path: "1-1.3:1.0"
    channel_mhz: 914
    bw_mhz: 4
    far_ip: 10.10.3.1
    priority: 2
  # hl2, hl1 ...
thresholds:
  floor_mbps: 1.5
  loss_degraded: 0.10
  noise_rise_db: 10
  failback_stable_s: 30
```

## 7. Test plan

All interference tests are conducted (coax, step attenuators, splitters) or
in a shielded box. No radiated jamming.

**Test gear.** Two Pi 4 + 4 dongles each, powered hubs, coax pigtails, 30 to
60 dB step attenuators per link, 4-way splitters, and an interference source:
a signal generator, an SDR (for example a HackRF) into the coax, or a fifth
HaLow radio sending saturating traffic on a chosen channel.

| Phase | What | Pass criteria |
|---|---|---|
| 1. Single-radio bring-up | Build driver on Pi OS, load firmware and BCF, one AP/STA pair on the 8 MHz channel, cabled | Associates; iperf3 runs; `morse_cli` and `iw` report stats |
| 2. Four radios on one host | All four dongles on each Pi, each on its own channel and bandwidth, all associated at once; reboot 20× | All four links up after every boot; udev names stable; no USB brown-outs (check `dmesg`, `vcgencmd get_throttled`). **Settles the multi-device driver guess.** |
| 3. Co-location | With links cabled through attenuators, saturate one link and read the noise floor and probe loss on the other three | Record noise-floor rise per standby. Probe loss on standbys < 1 %. Decide which noise mitigation from 3.4 to use. |
| 4. Per-link baseline | iperf3 TCP and UDP on each link alone at several attenuations; record MCS, RSSI, throughput, probe overhead | Table of usable throughput vs signal per bandwidth; calibrates the capacity estimate. Confirms or kills the 1 MHz floor concern (Q1). |
| 5. Failover, hard | Pull the coax or kill the AP on the active link during an iperf3 run and an SSH session | Switch < 500 ms; SSH survives; no manual action |
| 6. Failover, jamming | Inject narrowband and wideband interference on the active channel at rising power; repeat with duty-cycled jamming | Switch before throughput drops below 1.5 Mbps for more than 1 s; no flapping with a 50 % duty-cycle jammer |
| 7. Fail-back | Remove the interference | Returns to preferred link after the stable time, once |
| 8. Soak | 24 h with random scripted faults every few minutes | No stuck states, no memory growth, every outage < 1 s |
| 9. Field | Two real sites with antennas, site survey first (`iw survey` scans or an SDR sweep) | Meets the floor across a day; log of switches matches observed interference |
| 10. OpenWrt port | Repeat phases 2, 5 and 6 on OpenWrt | Same results as on Pi OS |

Metrics recorded in every run: time to detect, time to switch, packets lost
during the switch, throughput before, during and after, and the reason
`linkd` logged.

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Driver cannot run four USB devices at once | Blocks the design on one Pi | Phase 2 first. Fallback: two Pis with two radios each, or SDIO/SPI modules if available |
| USB power brown-outs | Random disconnects that look like jamming | Powered hub from day one; watch `get_throttled` |
| Standby noise readings polluted by own TX | False failovers | Rely on probe loss; mitigations in 3.4 |
| 1 MHz link below floor | Last backup does not meet 1.5 Mbps | Treat as lifeline, or replace with a second 2 MHz channel (Q1) |
| Wideband jammer covers all 26 MHz | All links fail together | Out of scope for one band. Document it; the lifeline may survive weak wideband noise thanks to its narrow bandwidth |
| Vendor tooling differs from assumptions | Rework of stats collection | `linkd` reads stats through small adapter functions so sources can change |

## 9. Open questions

- **Q1.** Is 1.5 Mbps a hard floor for every backup, or is a slower lifeline
  acceptable as the last resort? (Decides whether the 1 MHz channel stays.)
- **Q2.** Which exact MM8108 USB dongle, and does its vendor supply the BCF and
  a known-good driver version?
- **Q3.** Region: US 902 to 928 MHz assumed. Other regions (EU 863 to 868,
  for example) allow far less spectrum and would need a new plan.
- **Q4.** Is the far end also a Pi 4 with four dongles, or could it be a
  commercial HaLow AP that supports several radios?
- **Q5.** Does the link need to carry traffic both ways at similar rates, or
  mostly one way (for example video up, control down)?
- **Q6.** Acceptable outage during a switch: is about 0.5 s fine, or is there
  a tighter requirement?
