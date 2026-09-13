# Homelab Roadmap — Buy As You Grow

An incremental build. Each phase delivers something useful on its own, and every part carries forward — nothing bought early gets thrown away. You start with a live website and end with a segmented network running a home SOC, plus home services (IoT, NAS, media).

Guiding choices: **the Dell is the foundation** (Proxmox hypervisor from day one), and **as much as possible runs as containers.** Prices are approximate CAD.

---

## Simulation model

**[homelab-layout.pkt](homelab-layout.pkt)** is a Cisco Packet Tracer model of this network, built to test changes before applying them to live hardware.

**The intent: build and verify here first, then configure the real switch.** A mistake in simulation costs a mouse click; the same mistake on the CRS326 takes down the website.

Packet Tracer has no MikroTik, so the design is modelled in Cisco equivalents — a **3560 multilayer switch** for the CRS326 and a **2960** standing in for the Dell's `vmbr0` bridge. Port numbers match the real switch where they correspond (`Fa0/2` is the trunk, `Fa0/8` the desktop). **Known gaps between the model and reality, found while building it:**

| Gap | Consequence |
|---|---|
| **IOS ACLs are not stateful** | No `established/related`. Return traffic must be permitted explicitly — hence an `echo-reply` permit on the restricted VLANs |
| **`no ip unreachables` is unsupported in Packet Tracer** | An IOS `deny` sends **ICMP administratively-prohibited**, so the model reports *destination host unreachable* where RouterOS's silent `drop` gives a **timeout**. Same policy, different observable behaviour — and worth remembering, since silence gives an attacker less than a reply does |
| **The 3560 cannot do NAT** | Verified, not assumed — `ip ?` in interface config mode on Packet Tracer's 3560 lists `access-group`, `address`, `arp`, `helper-address`, `mtu`, `ospf` and others, with **no `nat`**. This matches real hardware: no 3560 feature set supports NAT. **The WAN side is therefore modelled with translation on the XB6 router instead of on the switch** — which is what the real XB6 does anyway, as NAT #1 of the live network's double-NAT. The CRS326's own translation layer has no equivalent in the model |

**⚠️ This entry was wrong once and the wrong version was committed.** An earlier note claimed Packet Tracer exposed `ip nat` on the 3560 and that the WAN side could be modelled on the switch. It cannot. The `ip ?` output above is recorded so the question stays closed.

**Consequence for the model's WAN design:** because XB6 performs the translation rather than the switch, XB6 needs a static route back to `10.10.0.0/16` via `10.0.0.2`. The proof that NAT is working therefore moves one hop outward — **Internet-Host** must have no route into the private space, and traffic must still succeed.

## Repo conventions

**This repo is public.** RouterOS `/export` headers carry the switch's serial number and software id, and they get masked before anything is committed:

```
# software id = ****-****
# serial number = ***********
```

**⚠️ That rule was broken once.** `configs/phase1-complete.rsc` was committed unmasked while the three stage exports around it were fine, and the commit was pushed. The values are masked in the working tree now, but **git history still holds them** — a rewrite would break every submodule pointer in `soc-python-journey`, which is a worse trade for a non-credential identifier.

**A `pre-commit` hook now enforces it** rather than relying on remembering. It refuses any commit whose added lines contain an unmasked RouterOS export header, the two values already known to have leaked, a private key block, or a WireGuard private key.

**Enable it after cloning** — hooks are not carried by `git clone`:

```
git config core.hooksPath .githooks
```

Bypass with `git commit --no-verify` when you mean to, not by habit.

**Incidents are logged in [incidents.md](incidents.md).** Real failures, written up the way a SOC would write them.

**Audits are logged in [audits.md](audits.md).** Deliberate reviews of the live network — where incidents record what broke, audits record what was looked for.

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

**Software (free):** firewall rules (one-way VLAN boundaries, default-deny); DMZ VLAN 40 for the web VM (inbound 443 only, no lateral access); WireGuard VPN; reverse proxy + Let's Encrypt; Homepage dashboard; bastion LXC; **Suricata** IDS (standalone on the Dell, tapping a mirrored/SPAN port off the switch rather than an OPNsense plugin — same detection capability, decoupled from wherever the firewall lives); SSH-key + MFA hardening; **RA Guard** on the CRS326 bridge ports.

> **RA Guard — added 2026-09-01.** Any device can send IPv6 Router Advertisements, and hosts accept them without authentication — so a malicious or misconfigured machine advertising itself as a router silently redirects traffic through itself. It is the IPv6 equivalent of a rogue DHCP server, and it works even on a network not intentionally running IPv6, since hosts autoconfigure regardless. The switch already exposes the controls (`ra-guard` on the bridge, `trusted-ra` per port).

**✅ Enabled 2026-09-10.** `/interface bridge set bridge1 ra-guard=yes`. **No port needed `trusted-ra=yes`** — `ether1` is the only router-facing link and it is not a bridge port, so nothing legitimate carries inbound Router Advertisements. All services verified still reachable afterwards.

**⚠️ Configured but not demonstrated.** Nothing on this network sends RAs, so the guard has never been observed dropping one. **Proving it belongs in the audit block** — send an RA from the sandbox VM (`rdisc6` or `radvd`) and confirm hosts in other VLANs do not pick it up. A control that is configured and a control that is proven are different states, and this one is the first.

**✅ `dhcp-snooping` enabled 2026-09-11**, with `dhcpv6-snooping` alongside it. **No trusted ports were needed** — all three DHCP servers are the router itself, replying from the CPU rather than ingressing a bridge port, so anything on `ether2` or `ether8` claiming to be a server is now dropped.

**The risk turned out to be far smaller than first assessed.** The earlier note warned the blast radius was every device on every VLAN. That was true of the *servers* and not the *clients*: Proxmox, the bastion, the syslog collector, the website VM and the desktop are all static, and **the sandbox is the only DHCP client on the network.** One VM in a VLAN by itself was the entire test surface. Verified by restarting it and confirming it still received `10.10.50.10`.

**`dhcp-vlan10` was also removed** after the rule 3 audit, so nothing hands out addresses on the management segment at all.

**Together with RA Guard, that is the full set:** rogue routers, rogue IPv4 servers, rogue IPv6 servers.

### DNS over HTTPS — upstream only

**Encrypt the switch's own lookups from the ISP, while keeping local queries visible.**

```
/ip dns set use-doh-server=https://cloudflare-dns.com/dns-query verify-doh-cert=yes
```

```
clients → switch     plain DNS, visible and loggable here
switch  → internet   DoH, opaque to the ISP
```

**⚠️ Do not enable DoH on clients.** A desktop pointed at a public DoH resolver bypasses `10.10.x.1` entirely, and the queries stop being visible — which is the opposite of the Phase 3 logged-resolver plan. **DNS is the richest detection signal on the network; encrypting it away from yourself is a loss, not a gain.** Encrypting it from the ISP is the part worth having.

**⚠️ It fails closed.** `verify-doh-cert=yes` requires the CA certificate imported into `/certificate` first — without it, resolution stops entirely rather than falling back. Import and verify before relying on it.

### Prove the UPS actually shuts the host down — added 2026-09-09

**NUT reads the UPS and is configured to halt the host, and that path has never fired.** Verified 2026-09-09: `upsc` returns full data, `upsmon.conf` carries a valid `MONITOR` line with `SHUTDOWNCMD` and `MODE=standalone`, and the service is enabled and running. **All of that proves it can read a UPS. None of it proves it will shut anything down.**

**Two stages, and only the second is disruptive.**

**Stage 1 — detection, non-destructive.** Pull the UPS mains lead for ~30 seconds:

```
watch -n1 'upsc cyberpower ups.status'
journalctl -u nut-monitor -f
```

`OL` → `OB` (On Line → On Battery) and a logged transition. Plug back in, returns to `OL`. Proves detection and notification; proves nothing about shutdown.

**Stage 2 — the real test.** Force the shutdown rather than draining the battery for 50 minutes:

```
upsmon -c fsd
```

`fsd` is Forced ShutDown — it sets the flag and runs `SHUTDOWNCMD` exactly as a genuine low-battery event would.

**⚠️ This actually halts the host. The website goes down. Schedule it.**

What to confirm afterwards:

| Check | Why |
|---|---|
| Every guest shut down **cleanly**, not killed | A hypervisor that halts without stopping its VMs is only half a graceful shutdown |
| `/etc/killpower` was created | The flag telling NUT this was a power event |
| The UPS cut output after `ups.delay.shutdown` (20 s) | The other half — the UPS must actually remove power, or the host reboots into the same dying battery |
| **The host powered itself back on when mains returned** | See below |
| Guests came back — everything needs `onboot: 1` | Two guests were found stopped after the Sep 8 outage |

**⚠️ The step most people miss is in the BIOS, not in NUT.** The Dell's *AC Power Recovery* setting decides what happens when power returns. If it is **Off** or **Last State**, the host stays down after the UPS cuts and restores — so the graceful shutdown works perfectly and nothing comes back until someone presses the button.

**Set it to Power On**, and check it while doing the pending BIOS update rather than as a separate trip to the machine.

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

### Syslog collector — ✅ built 2026-09-10

**The prerequisite for everything else in this phase.** The switch's log lives in RAM and rotates away within hours; the 2026-09-08 outage proved the cost, with every log needed to diagnose it trapped on the machine that could not be reached.

**Unprivileged Debian LXC at `10.10.10.40`**, VLAN 10, 16 GB disk, `onboot=1` with `startup order=1,up=15` so it is listening before anything that logs to it starts.

**The working configuration**, after several wrong turns:

| Setting | Value | Why |
|---|---|---|
| `remote-protocol` | **`tcp`** | UDP syslog has no delivery guarantee, no retry and no buffer — a message sent while the collector is down is gone silently |
| `remote-log-format` | **`syslog`** | v7 accepts `default`, `syslog`, `cef`. **Not `bsd-syslog`** — that is a v6 value |
| `syslog-time-format` | **`iso8601`** | Carries the UTC offset |
| Collector side | `imtcp` + `imudp` on 514, per-host files via `dynaFile`, `stop` to prevent duplication | |
| Retention | logrotate daily, 30 days, compressed, with `postrotate` signalling rsyslog | |

**⚠️ Four things learned the hard way, all worth keeping:**

**RouterOS 7 hides properties that do not apply to the current mode.** `syslog-facility`, `syslog-severity` and `syslog-time-format` **do not appear in `print detail` until `remote-log-format=syslog` is set**. Their absence looks like "this version does not support it" and is not.

**BSD syslog timestamps carry no timezone, so the receiver assumes its own.** The switch sent local time, the collector was in UTC, and messages arrived stamped `20:53+00:00` when the real time was 20:53 **PDT**. Neither end was broken — the format is lossy. `iso8601` fixes it by carrying the offset.

**TCP is a byte stream with no message boundaries.** A format that works over UDP — one datagram, one message — can leave rsyslog holding bytes and waiting for a terminator that never comes. **Connection established, data arriving, nothing written** is the signature.

**logrotate renames; it does not move the writer.** A file descriptor follows the **inode**, not the name, so without the `postrotate` signal rsyslog keeps writing into the archive and the new log stays empty forever. Silent, and one of the most common log-pipeline failures there is.

### Log integrity and detections — added 2026-09-12

**The collector was trusting the senders.** `%HOSTNAME%` is a plain-text field *inside* the syslog message, chosen by whoever sent it — so the original per-host template let any sender write into any device's log file. Proven by injecting a message from the bastion carrying the switch's hostname; it filed obediently into `switch.log`.

**Rebound so the unforgeable part decides the path:**

```
/var/log/remote/%FROMHOST-IP%/%HOSTNAME%.log
```

`%FROMHOST-IP%` comes from the socket, not the message. **The impersonation still succeeds — it can no longer hide.** A liar is confined to its own IP's directory, and the lie survives as a filename instead of being merged into the truth.

**Three rules now run against this**, documented properly in [detections.md](detections.md):

| Rule | Detects | Runs on |
|---|---|---|
| **DET-001** `syslog-sentry` | A sender using another host's name | Collector, cron |
| **DET-002** `syslog-heartbeat` | A sender that has gone silent | Collector, cron |
| **DET-003** `netwatch` | The collector no longer accepting on 514 | **The switch** |

**DET-003 lives on the switch on purpose. Nothing can monitor its own death** — if the collector fails, every rule running on it fails silently. The switch watches the collector and the collector watches the switch, so **neither vouches for itself.**

**⚠️ `logger -p security.warning` does not land in `/var/log/syslog`.** `security` aliases to `auth`, and Debian's stock rsyslog routes `auth` to `auth.log` while explicitly excluding it from the catch-all. **The facility is routing, not a label** — detections now use `auth`, health checks `local0`, so the two separate without grepping.

### Senders — ✅ switch, ✅ Proxmox, ✅ bastion

**Proxmox had no rsyslog at all** — recent PVE logs through systemd-journald alone. Installed rather than using `systemd-journal-upload`, because **the switch speaks syslog and nothing else**, and every sender converging on one protocol is the entire value of having a collector.

Forwarded with a durable queue rather than the one-line shorthand:

```
*.* action(type="omfwd" target="10.10.10.40" port="514" protocol="tcp"
           action.resumeRetryCount="-1"
           queue.type="linkedList" queue.size="10000"
           queue.saveOnShutdown="on")
```

**The queue is the part that matters.** Without it, forwarding is synchronous — an unreachable collector can stall the logging path on the machine running every service in the lab. **A monitoring system must never be able to take down what it monitors.** 10,000 messages buys well over a day of collector downtime with nothing lost.

**Local plaintext logs deliberately left enabled on the hypervisor**, despite duplicating the journal on disk. The 2026-09-08 incident is the argument: every log needed to diagnose it lived on the box that could not be reached.

**The bastion was the highest-value addition.** Every SSH session in the lab crosses it, and those records previously existed only on the container an attacker would be sitting in. **A login record stored on the machine being logged into is evidence the attacker controls.** `Accepted publickey for dan from 10.10.20.50 ... ED25519 SHA256:...` now lands off-box within a second, key fingerprint included — which is how a retired key still being accepted would be spotted.

**⚠️ Containers cannot produce kernel logs.** `imklog` fails in an unprivileged LXC because `/proc/kmsg` is the **host's** ring buffer and access is denied by design — the container boundary working, not a misconfiguration. The module is disabled on the container senders. **Proxmox is the only machine that can ship kernel messages**, which is exactly where the 2026-09-08 `e1000e` hang warnings would have gone had this existed.

**⚠️ `sudo cat > /etc/...` fails even as root.** The redirect is performed by the *calling* shell before `sudo` runs, so the file is opened as the unprivileged user. `sudo tee` is the fix — it receives the content on stdin and does the writing itself.

**Still to do:** the website VM and the sandbox do not ship yet. **They are the harder case** — they sit in the DMZ and sandbox VLANs, so shipping to VLAN 10 means opening a path from untrusted segments into management, which the firewall currently denies in both directions. **That is a policy decision, not a configuration step.**

### A resolver we control and log — wanted 2026-09-09

**Today the switch is the resolver for VLANs 10-40**, and `/ip dns cache print` is the only visibility — no timestamps, no source attribution, and it ages out. That is enough to see *what* was resolved and never *by whom* or *when*.

**Pi-hole, AdGuard Home, or Unbound in a container**, with per-client logging. Then DNS becomes a monitored feed rather than an unattributed cache.

**⚠️ The DMZ host is the reason this matters most.** Its baseline is small and enumerable — `cloudflared` resolving Cloudflare's edge, `apt` resolving Debian mirrors, an NTP pool, Docker Hub on a pull. **Everything else is an anomaly**, which is the condition anomaly detection actually needs and rarely gets.

**And the architecture forces attacker traffic through it.** The site is published by an outbound tunnel with no inbound ports, so there is nothing to connect *to* — any interactive access has to be initiated from inside as a reverse shell, a beacon, or a tunnel dialling out. **Nearly all of that begins with a DNS lookup.**

What to watch for, roughly in order of likelihood:

| Indicator | Signature |
|---|---|
| **C2 domain resolution** | An unknown domain queried **at regular intervals** |
| **Reverse shell to dynamic DNS** | `duckdns.org`, `no-ip.com`, `ngrok.io` |
| **Stage-two download** | One or two lookups of an unknown host, then silence |
| **DGA** | Many pseudo-random domains, high **NXDOMAIN** rate |
| **DNS exfiltration** | Long base32-style labels under one parent, high volume, TXT or NULL queries |

**⚠️ Note the deliberate asymmetry with VLAN 50.** The sandbox uses an external resolver because its DNS traffic is *noise* — it is supposed to resolve hostile domains. The DMZ uses the switch because its DNS traffic is *signal*. Same decision, opposite answers, and the difference is what the segment is for.

### Honeypot, then a small honeynet — wanted 2026-09-08

**Start with one honeypot; a honeynet of several decoys later.** The appeal is that a decoy has **no legitimate traffic**, so any interaction is anomalous by definition — a detection signal with no false-positive problem, which is the opposite of every other sensor in this phase. A honeynet adds the ability to watch **lateral movement** rather than just first contact.

**⚠️ Not before the syslog collector exists.** A honeypot whose alerts go nowhere is an ornament. This sits after telemetry collection, not before it.

**The design requirement is data control, not just data capture.** Capture is recording what the attacker does. **Control is limiting what they can do outbound**, and it is what separates a decoy from a machine you have handed to a stranger. If the honeypot attacks a third party, that is your host and your liability.

| Control | Mechanism |
|---|---|
| **Outbound rate limiting** | Permit a few connections per hour and drop the rest — tooling works, a scan or payload does not |
| **Protocol allow-listing** | Let DNS and HTTP out so the C2 callback is observable; block SMTP so it cannot spam |
| **Trigger-based isolation** | Any outbound connection to a non-decoy destination disables the port or reverts the VM |
| **Scheduled snapshot revert** | Roll back to clean on a timer regardless of what happened |

**⚠️ The current firewall is wrong for a decoy, and specifically in one rule.** VLAN 50 already has the right shape — no lateral path, internet only — but `forward` rule 14 permits `vlan50 → ether1` **unrestricted**. That is correct for a workstation being driven by hand and wrong for a machine nobody is supervising. Outbound restriction is the change a honeypot requires.

**⚠️ And it should not share VLAN 50 with the workstation.** A decoy and a machine in daily use do not belong in one broadcast domain, for the same reason the sandbox was not put in the IoT VLAN. A dedicated segment when the time comes.

**Candidate software, against this hardware's RAM ceiling:**

| | Weight | Notes |
|---|---|---|
| **OpenCanary** | Very light — LXC | Multiple emulated services, alerts to syslog. **The sensible first one** |
| **Cowrie** | Light | SSH and Telnet only, but records full attacker sessions including typed commands |
| **T-Pot** | **8 GB+** | Everything at once with its own dashboards. **Does not fit** alongside Wazuh on a 32 GB box |

**The tension worth knowing before starting:** too much containment and an attacker notices the network is fake and leaves, taking the intelligence with them; too little and you are running an attack platform. Balancing that is most of the work.

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
