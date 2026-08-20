# Homelab Roadmap — Buy As You Grow

An incremental build. Each phase delivers something useful on its own, and every part carries forward — nothing bought early gets thrown away. You start with a live website and end with a segmented network running a home SOC, plus home services (IoT, NAS, media).

Guiding choices: **the Dell is the foundation** (Proxmox hypervisor from day one), and **as much as possible runs as containers.** Prices are approximate CAD.

---

## Phase 0 — Get the website live

**Goal:** Put your Python portfolio site on the internet this week, learn the app + container workflow, and stand the Dell up as the hypervisor that every later phase builds on. Runs on your normal home network behind the XB6 — no networking gear yet.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| Dell OptiPlex Micro (refurb) — **i5-8500T** (6-core), **32GB DDR4**, **512GB NVMe**, Win 11 Pro | ~$400 | The foundation. 32GB + NVMe out of the box (no upgrades needed for ages); free 2.5" bay + 2nd RAM slot for later. Wipe Windows for Proxmox (license carries to a future VM). |
| UPS — **CyberPower CP1500PFCLCD** (1500VA / 1000W, pure sine, 12 outlets, USB) | ~$230 | Protects the Dell now, and carries the lab core **plus your 6750 XT desktop** through blips; USB → NUT for coordinated graceful shutdown. |
| **Cat6 cabling (buy-once set)** — 8× short (1–2 ft) + 3× long (XB6→lab, desk→lab, AP run — **measure**) + 3× spare (5–7 ft) | ~$80 | Every run through Phase 4 in one purchase. In Phase 0 you use one long run (XB6 → Dell); the rest come into play as you add gear. Cat6 only — 1G now, 2.5G/10G later. |
| Display cable (HDMI or DisplayPort) for the one-time Proxmox install | ~$10 | Screen + keyboard needed once to install Proxmox; borrow the desktop's monitor, then go headless. |
| 16GB USB stick | owned | Proxmox installer media (keep it — reusable for any later OS install). |
| Domain name | ~$15/yr | A real address (`yourname.dev`) instead of an IP. |

**Software (all free):** Proxmox VE → a Debian VM running Docker → your site as containers (Flask + Gunicorn), plus a `cloudflared` container. A **Cloudflare Tunnel** publishes the site with HTTPS and **no open ports** on your router.

**Milestone:** portfolio live at your domain, served from containers, on a hypervisor you'll keep.

---

## Phase 1 — Network foundation *(Network+)*

**Goal:** Build a real, segmented, routed network — the hands-on Network+ layer, and the network you'll later defend. This is the network your Phase 0 site moves onto.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| ~~Dedicated firewall appliance~~ | ~~$520~~ | **Cut 2026-08-13** — see firewall approach below. |
| Managed switch — **MikroTik CRS326-24G-2S+IN** (24× 1GbE + 2× 10G SFP+, fanless) | $200 | VLANs (802.1Q), trunk/access ports, RouterOS CLI practice — **and now the network's firewall/router itself**, see below. **Bought.** |
| ~~USB-to-Ethernet adapter — Realtek RTL8156BG~~ | ~~$15-30~~ | **Order cancelled 2026-08-16** — no longer needed, see firewall approach below. |
| Cat6 cabling | — | Already covered by the Phase 0 buy-once set. |

**Firewall approach (updated 2026-08-16):** the USB-NIC order got cancelled, so instead of virtualizing OPNsense on the Dell, **the switch itself runs the firewall**. The CRS326 dual-boots into full **RouterOS** instead of the lightweight SwOS specifically for this — RouterOS has a genuine stateful firewall, NAT, and routing built in, not just switching. One switch port becomes the WAN interface (plugged straight into the XB6, running NAT + firewall rules in RouterOS); the rest stay LAN-side access/trunk ports for the internal VLANs. The switch is now both the Layer 2 fabric *and* the Layer 3 router/firewall — the same one-box pattern most consumer and small-business routers already use internally.

This is simpler than the VLAN-trunk fallback it replaces: WAN traffic terminates directly on the switch's own router interface instead of being tagged and carried over a trunk to a separate firewall device — so the dedicated WAN VLAN (99) that fallback plan needed isn't necessary either. The Dell drops out of the firewall picture entirely; it becomes a regular (trunked, multi-VLAN) LAN host running Proxmox and its VMs, same as before, just without OPNsense in the mix.

**A "for now" decision, not a final one:** OPNsense-on-Dell is still there to revisit later if you want the NFV/resource-tuning practice for its own sake — nothing about running the firewall on the switch rules it out, and no hardware bought so far is wasted either way.

> **⚠️ Flag — verify the switch's own firewall rules are actually doing their job.** With RouterOS as the only perimeter defense now, confirm before trusting this setup: does the WAN interface have a default-deny inbound rule (NAT alone doesn't block unsolicited inbound traffic — that's a separate, additional rule)? Can a device on the WAN side reach internal VLANs directly, bypassing the router's own rules? Is the native/default VLAN not left as VLAN 1 on the internal ports (a known VLAN-hopping vector)? Same verification discipline as before, just aimed at RouterOS's firewall instead of a VLAN-tag boundary — don't skip it because it's "just the switch's default config."

**Software (free):** RouterOS on the switch — WAN interface (NAT + firewall), internal VLANs 10/20/30/40, DHCP, DNS, trunk + access ports. No separate OPNsense VM for now.

**Note on the XB6 & Wi-Fi:** you can keep the XB6 **un-bridged (double-NAT)** through the early phases so the house keeps its Wi-Fi — VLANs still work fine behind it. Switch the XB6 to **bridge mode** later (in Phase 4), when you add your own access point — because bridging turns the XB6's Wi-Fi off.

**Milestone:** a fully routed, correctly segmented network you understand end to end; the website moves onto it.

---

## Phase 2 — Security controls *(Security+)*

**Goal:** Harden and segment the network, and move the website into an isolated DMZ where it starts drawing real attack traffic. Almost entirely software on hardware you already own.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| *(none required)* | $0 | Everything here is software configured on the Phase 1 gear. |
| *(optional)* Access point — U7 Lite or TP-Link Omada EAP + PoE injector | $100–160 | Only if you want **segmented Wi-Fi** now (SSID → VLAN). Otherwise defer to Phase 4. |

**Software (free):** firewall rules (one-way VLAN boundaries, default-deny); DMZ VLAN 40 for the web VM (inbound 443 only, no lateral access); WireGuard VPN; reverse proxy + Let's Encrypt; Homepage dashboard; bastion LXC; **Suricata** IDS (standalone on the Dell, tapping a mirrored/SPAN port off the switch rather than an OPNsense plugin — same detection capability, decoupled from wherever the firewall lives); SSH-key + MFA hardening.

**Milestone:** a hardened, segmented perimeter with a live public service generating real-world traffic.

---

## Phase 3 — Home SOC *(CCDL1)*

**Goal:** Operate a home SOC — collect telemetry, detect, triage, and investigate — the hands-on CCDL1 skill set. Runs on existing hardware; the only spend is optional headroom.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| ~~Dell RAM top-up to 64GB~~ — **NOT POSSIBLE, see flag below** | — | The OptiPlex 7070 Micro's board caps at 32GB total (2 slots × 16GB max/slot) — already maxed out from the Phase 0 purchase. No upgrade path exists on this hardware. |
| Analyst workstation — your **existing desktop** | $0 | SIEM dashboards and investigations want a real screen/keyboard. Same room as the lab; also your out-of-band recovery box. |
| *(optional)* 2.5G USB NIC (RTL8156) for the Dell | $20 | Faster trunk / second interface as telemetry and traffic grow. |

> **⚠️ Flagged 2026-08-13, updated 2026-08-16 — Phase 3 RAM constraint:** the original plan assumed a 64GB RAM upgrade for Wazuh, but the Dell's board hard-caps at 32GB total, and it's already there. Wazuh will have to run within whatever's left of that same fixed 32GB, shared with the website VM and standalone Suricata. **Some headroom came back with the Phase 1 change** — now that the firewall lives on the switch instead of an OPNsense VM on the Dell, only Suricata itself needs Dell RAM (~1-2GB), not OPNsense's own overhead on top of it. Rough budget: ~1-2GB for Suricata, ~1-2GB for the website VM, leaving comfortably more than the original ~24-26GB estimate for Wazuh + Proxmox overhead — likely enough for a constrained single-node deployment (smaller indices, shorter retention). Still worth revisiting before starting Phase 3, with the same three options as before: (1) accept a constrained Wazuh config, (2) give Wazuh its own separate hardware, or (3) check whether this specific board unofficially supports more than 32GB (undocumented, would need community verification first).

**Software (free):** Wazuh SIEM (VM); Wazuh agents on VMs/LXCs + desktop; a Windows VM with Sysmon; an isolated **sandbox** (spare firewall port → REMnux/FLARE-VM); Atomic Red Team; MITRE ATT&CK-mapped triage. Stretch: Zeek (SPAN port), Volatility (memory forensics).

**Rule:** live samples run **only** inside sandbox VMs — never on the bare desktop.

**Milestone:** a running home SOC you operate like a Tier 1 analyst.

---

## Phase 4 — Home services (IoT · NAS · Media)

**Goal:** Round out the original "useful self-hosting" vision — a segmented IoT hub, network storage, and movie/music streaming.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| Access point — **UniFi U7 Lite** (or Omada EAP) + PoE injector | $100–160 | Segmented Wi-Fi: maps SSIDs to VLANs so IoT/guest devices land on the right (isolated) segment. Pair with switching the XB6 to bridge mode. |
| **Raspberry Pi 5 (8GB)** + fanless case + NVMe + PSU + Zigbee/Matter USB stick | $260 | Dedicated Home Assistant appliance on the IoT VLAN. Boot from **NVMe** (HA is write-heavy — kills SD cards). |
| **NAS** — multi-TB drives + enclosure (DIY TrueNAS or Synology), redundancy (ZFS/RAID) | $400–800+ | Bulk storage for music + movies. Drives are the cost driver; connects over the 10G SFP+ backbone. |
| 2.5G USB NIC / 10G SFP+ DAC | $20–35 | Faster links once multiple streams and large transfers are in play. |

**Software (free):** Home Assistant OS (on the Pi); Jellyfin media server as an LXC on the Dell (uses the i5's Quick Sync for transcoding), mounting the NAS for storage.

**Milestone:** the full vision — portfolio, segmented network, home SOC, IoT hub, and a streaming media library.

---

## Cost summary (approximate CAD)

| Phase | Focus | New spend | Cumulative |
|-------|-------|-----------|------------|
| 0 | Website live | ~$720 (+$15/yr domain) | ~$720 |
| 1 | Network foundation *(Net+)* | ~$200 | ~$920 |
| 2 | Security controls *(Sec+)* | ~$0 (opt. AP $100–160) | ~$920 |
| 3 | Home SOC *(CCDL1)* | ~$60–100 | ~$980–1,020 |
| 4 | IoT · NAS · Media | ~$780–1,255+ | ~$1,760–2,275+ |

You control the pace — each phase is a natural stopping point, and you only buy the next tier of hardware when you're ready to use it.

---

## Reference: Cabling plan (colors & lengths)

**Spec for every cable:** Cat6, 24 AWG, UTP (unshielded), snagless, PVC jacket, **bare copper**.

**Color = role / trust level** (so the network reads at a glance):

| Color | Meaning |
|-------|---------|
| 🟡 Yellow | WAN / internet-facing (the one cable that touches the public internet) |
| 🔵 Blue | Trunks / backbone (all-VLAN tagged links — the critical infrastructure) |
| ⚫ Black | Trusted access (Personal / Management VLANs) |
| 🔴 Red | Untrusted / isolated (IoT, DMZ, sandbox — the walled-off segments) |
| ⚪ White | Spares & temporary / bench-test |

**Buy list** (~15 cables — covers everything through Phase 4). The store stocks **1 ft and 3 ft** for short runs (no 2 ft), so the rule is: **1 ft only for gear that sits side-by-side; 3 ft for everything else and whenever you're unsure** (excess slack is harmless — a too-short cable is useless):

| Color | Run(s) | Length | Qty |
|-------|--------|--------|-----|
| 🟡 Yellow | XB6 → switch (WAN port) | **measure** + slack | 1 |
| 🟡 Yellow | WAN spare | 3 ft | 1 |
| 🔵 Blue | Dell ↔ switch (trunk — Dell hosts VMs across several VLANs) | 1 ft | 1 |
| 🔵 Blue | switch → AP (trunk, Phase 4) | **measure** (AP mount) | 1 |
| ⚫ Black | desktop → switch | **measure** | 1 |
| ⚫ Black | management / trusted access | 3 ft | 2 |
| 🔴 Red | IoT / DMZ / sandbox access ports | 3 ft | 3 |
| ⚪ White | spares / bench-test | 5–7 ft | 3 |

**Order roughly:** 2 yellow, 2 blue, 3 black, 3 red, 3 white — short runs split into **1× 1 ft** (the Dell↔switch trunk — no separate firewall device to sit next to the switch anymore) and **6× 3 ft** for the rest. (No dedicated trunk spare — a white spare covers the short trunk run if it ever fails.)

Only the three **measure** runs (XB6→switch, desk→switch, AP→switch) can't be bought blind — measure them and buy the next size up; leave the AP run's length until you pick its mounting spot in Phase 4. Everything else is a safe order today. Label both ends of the long runs with tape, and keep this legend handy for the first few weeks until it's second nature.
