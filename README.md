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
| 16GB USB stick | owned | Proxmox installer media (reused later for OPNsense). |
| Domain name | ~$15/yr | A real address (`yourname.dev`) instead of an IP. |

**Software (all free):** Proxmox VE → a Debian VM running Docker → your site as containers (Flask + Gunicorn), plus a `cloudflared` container. A **Cloudflare Tunnel** publishes the site with HTTPS and **no open ports** on your router.

**Milestone:** portfolio live at your domain, served from containers, on a hypervisor you'll keep.

---

## Phase 1 — Network foundation *(Network+)*

**Goal:** Build a real, segmented, routed network — the hands-on Network+ layer, and the network you'll later defend. This is the network your Phase 0 site moves onto.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| ~~Dedicated firewall appliance~~ | ~~$520~~ | **Cut 2026-08-13** — see firewall approach below. |
| Managed switch — **MikroTik CRS326-24G-2S+IN** (24× 1GbE + 2× 10G SFP+, fanless) | $200 | VLANs (802.1Q), trunk/access ports, and RouterOS CLI practice. SFP+ ports wait for a future NAS. |
| Cat6 cabling | — | Already covered by the Phase 0 buy-once set; the short table runs get used here (switch ↔ Dell). |

**Firewall approach (decided 2026-08-13):** OPNsense runs as a **VM on the Dell** (NFV — virtualizing what would traditionally be a dedicated appliance, using the hypervisor already stood up in Phase 0) instead of a separate physical box. The Dell only has one onboard NIC, so **WAN and LAN both ride the same physical link as tagged VLANs** — no second NIC needed at all:
- MikroTik port facing the XB6 (WAN) is configured as an **access port** on a dedicated WAN VLAN (e.g. VLAN 99) — the switch tags the XB6's plain untagged traffic as it enters.
- MikroTik port facing the Dell is a **trunk port**, carrying the WAN VLAN plus all internal VLANs (10/20/30/40) together.
- OPNsense reads the trunk over the Dell's single NIC and creates a sub-interface per VLAN tag, treating the WAN VLAN's sub-interface as its actual WAN interface.

Chosen over buying a dedicated 6-port appliance (~$520-685 across several options researched — Kikusenko/KETUOPU N305 boxes, CWWK U300, MinisForum MS-01, Lenovo M720q) specifically for the NFV/resource-tuning learning experience and lower cost. Known tradeoff accepted: firewall/internet goes down whenever the Dell reboots for unrelated reasons (website VM work, Proxmox updates, etc.).

> **⚠️ Flag — verify VLAN isolation is actually enforced before trusting this setup.** WAN and LAN now share one physical cable, separated only by VLAN tags rather than genuinely separate wires — this is normally adequate, but it's worth actively testing rather than assuming it's correct, given VLAN hopping (double-tagging, switch spoofing) is a real attack category. Before treating Phase 1 as done: confirm the WAN VLAN cannot reach internal VLANs and vice versa (try pinging/scanning across them from both directions), confirm the native VLAN isn't left as the default VLAN 1 (a known VLAN-hopping vector), and confirm OPNsense's WAN interface has no route back into LAN-side VLANs except through its own firewall rules. Don't skip this just because the switch config "looks right."

**Software (free):** OPNsense (WAN/LAN, VLANs 10/20/30/40/99, DHCP, DNS) as a VM on the Dell; RouterOS on the switch (trunk + access ports).

**Note on the XB6 & Wi-Fi:** you can keep the XB6 **un-bridged (double-NAT)** through the early phases so the house keeps its Wi-Fi — VLANs still work fine behind it. Switch the XB6 to **bridge mode** later (in Phase 4), when you add your own access point — because bridging turns the XB6's Wi-Fi off.

**Milestone:** a fully routed, correctly segmented network you understand end to end; the website moves onto it.

---

## Phase 2 — Security controls *(Security+)*

**Goal:** Harden and segment the network, and move the website into an isolated DMZ where it starts drawing real attack traffic. Almost entirely software on hardware you already own.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| *(none required)* | $0 | Everything here is software configured on the Phase 1 gear. |
| *(optional)* Access point — U7 Lite or TP-Link Omada EAP + PoE injector | $100–160 | Only if you want **segmented Wi-Fi** now (SSID → VLAN). Otherwise defer to Phase 4. |

**Software (free):** firewall rules (one-way VLAN boundaries, default-deny); DMZ VLAN 40 for the web VM (inbound 443 only, no lateral access); WireGuard VPN; reverse proxy + Let's Encrypt; Homepage dashboard; bastion LXC; **Suricata** IDS; SSH-key + MFA hardening.

**Milestone:** a hardened, segmented perimeter with a live public service generating real-world traffic.

---

## Phase 3 — Home SOC *(CCDL1)*

**Goal:** Operate a home SOC — collect telemetry, detect, triage, and investigate — the hands-on CCDL1 skill set. Runs on existing hardware; the only spend is optional headroom.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| ~~Dell RAM top-up to 64GB~~ — **NOT POSSIBLE, see flag below** | — | The OptiPlex 7070 Micro's board caps at 32GB total (2 slots × 16GB max/slot) — already maxed out from the Phase 0 purchase. No upgrade path exists on this hardware. |
| Analyst workstation — your **existing desktop** | $0 | SIEM dashboards and investigations want a real screen/keyboard. Same room as the lab; also your out-of-band recovery box. |
| *(optional)* 2.5G USB NIC (RTL8156) for the Dell | $20 | Faster trunk / second interface as telemetry and traffic grow. |

> **⚠️ Flagged 2026-08-13 — Phase 3 RAM constraint:** the original plan assumed a 64GB RAM upgrade for Wazuh, but the Dell's board hard-caps at 32GB total, and it's already there. Wazuh will have to run within whatever's left of that same fixed 32GB, shared with the website VM and (per the Phase 1 firewall-consolidation decision — OPNsense virtualized on this same Dell rather than a separate appliance) OPNsense + Suricata too. Rough budget: ~4GB for OPNsense+Suricata, ~1-2GB for the website VM, leaving ~24-26GB for Wazuh + Proxmox overhead — likely enough for a constrained single-node deployment (smaller indices, shorter retention), but with less headroom than originally planned. Revisit before starting Phase 3, with three options: (1) accept a more constrained Wazuh config, (2) give Wazuh its own separate hardware, breaking from full consolidation, or (3) check whether this specific board unofficially supports more than 32GB (undocumented, would need community verification first).

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
| 1 | Network foundation *(Net+)* | ~$720 | ~$1,440 |
| 2 | Security controls *(Sec+)* | ~$0 (opt. AP $100–160) | ~$1,440 |
| 3 | Home SOC *(CCDL1)* | ~$60–100 | ~$1,540 |
| 4 | IoT · NAS · Media | ~$780–1,255+ | ~$2,320–2,795+ |

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
| 🟡 Yellow | XB6 → firewall (WAN) | **measure** + slack | 1 |
| 🟡 Yellow | WAN spare | 3 ft | 1 |
| 🔵 Blue | firewall ↔ switch (trunk) | 1 ft | 1 |
| 🔵 Blue | switch → AP (trunk, Phase 4) | **measure** (AP mount) | 1 |
| ⚫ Black | Dell ↔ switch | 1 ft | 1 |
| ⚫ Black | desktop → switch | **measure** | 1 |
| ⚫ Black | management / trusted access | 3 ft | 2 |
| 🔴 Red | IoT / DMZ / sandbox access ports | 3 ft | 3 |
| ⚪ White | spares / bench-test | 5–7 ft | 3 |

**Order roughly:** 2 yellow, 2 blue, 4 black, 3 red, 3 white — short runs split into **2× 1 ft** (the adjacent firewall↔switch and Dell↔switch links) and **6× 3 ft** for the rest. (No dedicated trunk spare — a white spare covers the short trunk run if it ever fails.)

Only the three **measure** runs (XB6→lab, desk→lab, AP→switch) can't be bought blind — measure them and buy the next size up; leave the AP run's length until you pick its mounting spot in Phase 4. Everything else is a safe order today. Label both ends of the long runs with tape, and keep this legend handy for the first few weeks until it's second nature.
