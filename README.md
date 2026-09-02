# Homelab Roadmap — Buy As You Grow

An incremental build. Each phase delivers something useful on its own, and every part carries forward — nothing bought early gets thrown away. You start with a live website and end with a segmented network running a home SOC, plus home services (IoT, NAS, media).

Guiding choices: **the Dell is the foundation** (Proxmox hypervisor from day one), and **as much as possible runs as containers.** Prices are approximate CAD.

---

## Phase 0 — Get the website live

**Goal:** Put your Python portfolio site on the internet this week, learn the app + container workflow, and stand the Dell up as the hypervisor that every later phase builds on. Runs on your normal home network behind the XB6 — no networking gear yet.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| Dell OptiPlex Micro (refurb) — **i5-8500T** (6-core), **32GB DDR4**, **512GB NVMe**, Win 11 Pro | ~$400 | The foundation. 32GB + NVMe out of the box (no upgrades needed for ages); free 2.5" bay for later. Wipe Windows for Proxmox — see the licensing note below. |
| UPS — **CyberPower CP1500PFCLCD** (1500VA / 1000W, pure sine, 12 outlets, USB) | ~$230 | Protects the Dell now, and carries the lab core **plus your 6750 XT desktop** through blips; USB → NUT for coordinated graceful shutdown. |
| **Cat6 cabling (buy-once set)** — 8× short (1–2 ft) + 3× long (XB6→lab, desk→lab, AP run — **measure**) + 3× spare (5–7 ft) | ~$80 | Every run through Phase 4 in one purchase. In Phase 0 you use one long run (XB6 → Dell); the rest come into play as you add gear. Cat6 only — 1G now, 2.5G/10G later. |
| Display cable (HDMI or DisplayPort) for the one-time Proxmox install | ~$10 | Screen + keyboard needed once to install Proxmox; borrow the desktop's monitor, then go headless. |
| 16GB USB stick | owned | Proxmox installer media (keep it — reusable for any later OS install). |
| Domain name | ~$15/yr | A real address (`yourname.dev`) instead of an IP. |

**Software (all free):** Proxmox VE → a Debian VM running Docker → your site as containers (Flask + Gunicorn), plus a `cloudflared` container. A **Cloudflare Tunnel** publishes the site with HTTPS and **no open ports** on your router.

> **⚠️ Before wiping Windows — do these three things while it is still installed.**
> 1. **Update the BIOS/firmware.** Dell Command Update is Windows-native; after Proxmox is installed this means a bootable USB or `fwupd` support that may not exist for this model.
> 2. **Extract the product key:** `(Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey`
> 3. **Verify the refurb hardware** matches the listing — 32GB as 2×16GB (dual channel, not one stick), NVMe capacity, CPU model, service tag — while checking is still easy and returning is still simple.
>
> **Windows licensing correction (2026-08-21):** the OEM license is embedded in UEFI firmware (ACPI MSDM table) and is **hardware-bound**. Reinstalling Windows *on this Dell* reactivates automatically, but it will **not** activate in a VM — a guest does not read that firmware table, and exposing it via SMBIOS is legally murky. Plan on a separate license if the Phase 3 Windows VM needs one; unactivated Windows runs indefinitely with cosmetic nags and no functional limits, which is fine for a lab.

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

> **✅ Flag resolved 2026-09-01 — all three questions verified, not assumed.**
>
> **Default-deny inbound on the WAN?** Yes. The `input` chain ends in an explicit drop, and NAT is not relied on for it. Confirmed from a phone on the XB6's network: ICMP to `10.0.0.2` succeeds (permitted deliberately, so PMTUD keeps working) while TCP 22 and 8291 time out, and the drop rule's counter increments.
>
> **Can a WAN-side device reach internal VLANs?** No. `ether1` is deliberately outside the bridge, so there is no Layer 2 path, and `rp-filter=strict` discards any packet whose source address does not match the interface it arrived on.
>
> **Is the native VLAN something other than 1?** Yes — VLAN 99, with no address, no DHCP, no devices, and no `bridge1` membership, so the router does not participate in it. Trunk ports additionally run `frame-types=admit-only-vlan-tagged`, which rejects untagged frames outright — so a double-tagging attempt has no untagged outer frame to ride in on. Two independent mechanisms close the same door.
>
> Full policy matrix and test results in [network-diagrams.md](network-diagrams.md).

**Software (free):** RouterOS on the switch — WAN interface (NAT + firewall), internal VLANs (below), DHCP, DNS, trunk + access ports. No separate OPNsense VM for now.

**VLAN plan:**

| VLAN | Name | Purpose | Cable colour |
|------|------|---------|--------------|
| **10** | Management | Switch, Proxmox host, IPMI/out-of-band. Only VLAN permitted to reach device management interfaces. | ⚫ Black |
| **20** | Trusted | Desktop, laptops, personal devices. General internet access. | ⚫ Black |
| **30** | IoT | Home Assistant, smart devices, anything untrustworthy but not internet-facing. **No access to 10 or 20.** | 🔴 Red |
| **40** | DMZ | The website VM. Inbound 443 only, **no lateral access to any other VLAN.** | 🔴 Red |
| **99** | Native (unused) | Trunk native VLAN. **Carries no traffic and has no devices** — exists so the native VLAN is never VLAN 1. | — |

**Why VLAN 99 is empty on purpose:** the native VLAN is the position a double-tagging VLAN-hopping attack must be launched from. With no devices in it, there is nowhere to launch from. It also means a native-VLAN mismatch between two trunk ends merges nothing, rather than silently bridging two real segments.

**Planned later:** a **sandbox VLAN** in Phase 3 for live malware analysis (fully isolated, no route anywhere), and possibly a **guest Wi-Fi VLAN** in Phase 4 once the AP maps SSIDs to VLANs.

**Note on the XB6 & Wi-Fi:** you can keep the XB6 **un-bridged (double-NAT)** through the early phases so the house keeps its Wi-Fi — VLANs still work fine behind it. Switch the XB6 to **bridge mode** later (in Phase 4), when you add your own access point — because bridging turns the XB6's Wi-Fi off.

**Milestone:** ✅ **Reached 2026-09-01.** A fully routed, segmented network with the website moved onto it. The CRS326 runs RouterOS as switch, router, and firewall; VLANs 10/20/30/40 are live with hardware offload intact; the Proxmox host sits on VLAN 10 and the website VM on VLAN 40, reachable at dangagne.com through the Cloudflare Tunnel. **Isolation is verified rather than intended** — the DMZ can reach the internet and nothing else internal.

**Documentation:** [phase-1-checklist.md](phase-1-checklist.md) · [ip-plan.md](ip-plan.md) · [network-diagrams.md](network-diagrams.md) · [configs/](configs/)

**⚠️ Measured limitation:** inter-VLAN routing runs on the CPU, not the switch chip. **251 Mbps for a single flow, 468 Mbps aggregate across four.** Same-VLAN traffic is unaffected and runs at line rate. See [network-diagrams.md](network-diagrams.md) for the measurements and what they mean for Phase 4.

---

## Phase 2 — Security controls *(Security+)*

**Goal:** Harden and segment the network, and move the website into an isolated DMZ where it starts drawing real attack traffic. Almost entirely software on hardware you already own.

| Part | ~CAD | Why it's needed |
|------|------|-----------------|
| **2.5G USB NIC (RTL8156B)** | $20–35 | **Suricata's mirror-receive interface.** Moved here from Phase 3 — Suricata is a Phase 2 control and needs traffic to inspect, so the NIC that feeds it belongs in the same phase. The 7070 Micro has no PCIe slot, so USB is the only way to add a second interface. Capture plan documented under Phase 3. |
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
| ~~2.5G USB NIC (RTL8156)~~ | — | **Moved to Phase 2** — Suricata needs it there. Capture plan retained below, since it governs both phases. |

> **⚠️ Flagged 2026-08-13, updated 2026-08-16 — Phase 3 RAM constraint:** the original plan assumed a 64GB RAM upgrade for Wazuh, but the Dell's board hard-caps at 32GB total, and it's already there. Wazuh will have to run within whatever's left of that same fixed 32GB, shared with the website VM and standalone Suricata. **Some headroom came back with the Phase 1 change** — now that the firewall lives on the switch instead of an OPNsense VM on the Dell, only Suricata itself needs Dell RAM (~1-2GB), not OPNsense's own overhead on top of it. Rough budget: ~1-2GB for Suricata, ~1-2GB for the website VM, leaving comfortably more than the original ~24-26GB estimate for Wazuh + Proxmox overhead — likely enough for a constrained single-node deployment (smaller indices, shorter retention). Still worth revisiting before starting Phase 3, with the same three options as before: (1) accept a constrained Wazuh config, (2) give Wazuh its own separate hardware, or (3) check whether this specific board unofficially supports more than 32GB (undocumented, would need community verification first).

### Traffic capture plan — decided 2026-09-01

**The sensor needs its own path to mirrored traffic.** The Dell has a single NIC on ether2 carrying the production trunk; mirroring into that port would mix a copy of everything with live traffic on the same wire, breaking the bridge and doubling its load. A mirror destination needs a dedicated physical interface.

**⚠️ The OptiPlex 7070 Micro has no PCIe slot**, so an internal card is not an option — its M.2 slots take storage and WiFi, not a NIC. **USB is the only way to add a second interface to this machine**, which is what makes the 2.5G USB NIC required rather than a convenience.

**The arrangement:**

| | |
|---|---|
| **Mirror source** | **ether1 (WAN)** — everything entering or leaving the network |
| **Mirror target** | A port taken out of the bridge (one of ether20–24, currently disabled) |
| **Path to sensor** | That port → cable → USB NIC on the Dell |
| **Sensor access** | USB device passed through to the sensor VM in Proxmox |

**Mirror the WAN port only.** It is the highest-value monitoring point, and its volume is capped by the ISP plan — so a 1 Gbps mirror destination cannot be oversubscribed. Adding internal ports would risk silent packet loss during exactly the peak-load moments an investigation cares about, since an oversubscribed SPAN drops frames without reporting it.

**⚠️ USB NICs can drop packets under sustained line-rate load.** That weakness is real and does not apply here — a 2.5G adapter has ample headroom for a sub-gigabit WAN feed. It also matters far less in this role than in the one this part was originally bought for: a dropped packet costs a little visibility rather than causing an outage.

**No network TAP, for now.** Gigabit copper uses all four pairs bidirectionally with echo cancellation, so **passive copper TAPs do not exist at that speed** — every gigabit copper TAP is an active, powered device, which would put a new failure point inline on the one uplink the website depends on, for $150–400. **Fibre TAPs are genuinely passive and cheap**, so the decision is deferred to Phase 4 when the SFP+ backbone exists. Port mirroring is adequate until then; the traffic volumes here are nowhere near where SPAN's weaknesses appear.

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
| **NAS** — multi-TB drives + enclosure (DIY TrueNAS or Synology), redundancy (ZFS/RAID) | $400–800+ | Bulk storage for music + movies. Drives are the cost driver; connects over the 10G SFP+ backbone. **⚠️ Must share a VLAN with its primary consumer** — see below. |
| 2.5G USB NIC / 10G SFP+ DAC | $20–35 | Faster links once multiple streams and large transfers are in play. |

**Software (free):** Home Assistant OS (on the Pi); Jellyfin media server as an LXC on the Dell (uses the i5's Quick Sync for transcoding), mounting the NAS for storage.

> **⚠️ Put the NAS on the same VLAN as whatever reads from it.** Phase 1 measured the CRS326's inter-VLAN routing at **251 Mbps for a single flow** — and a large file copy *is* a single flow, so parallelism does not help it. Across a 10G SFP+ link that is roughly **2.5% of the link**. Same-VLAN traffic is switched by the Marvell chip at line rate and never touches the CPU, so co-locating the NAS and the Dell on one segment is the difference between 10G and 251 Mbps. This is an architectural decision made when the VLAN is assigned, not something tunable afterwards. If cross-VLAN storage access at speed is ever genuinely needed, that is the point at which routing moves off the switch — the OPNsense-on-Dell option deliberately kept open above.

**Documentation tooling — consider here:** **NetBox** as a container stack on the Dell. It covers four of the Network+ 3.1 documentation artifacts in one tool — **IPAM, asset inventory, rack elevations, and cable maps** — and is genuinely used in infrastructure roles, so running it is a portfolio item rather than housekeeping. Deliberately *not* earlier: ten devices do not justify a PostgreSQL-backed DCIM, and maintaining the markdown IP plan by hand first teaches the problem the tool solves rather than just its UI.

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
