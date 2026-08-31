# Phase 1 — Network Foundation: Step-by-Step Checklist

Goal: a segmented, routed network built on the MikroTik CRS326 running RouterOS as switch, router, and firewall in one. VLANs 10/20/30/40 behind it, native VLAN 99 empty by design, and the Phase 0 website moved onto VLAN 40.

**The governing constraint: the website is already live.** Every step is ordered so the site stays up and a rollback is always one cable away.

---

> ## ⏸ Paused 2026-08-31 — resume at §2b
>
> **Working state, verified:** RouterOS 7.24.1 on the CRS326, WAN static on ether1 (`10.0.0.2/24`), flat `10.10.10.0/24` LAN with NAT and DHCP, default-deny input firewall confirmed from an off-network device, `rp-filter=strict`. The desktop sits behind the switch at `10.10.10.200` and has internet. The Dell and the website are still on the XB6 and have not been touched.
>
> **Next action:** §2 — define VLANs 10/20/30/40/99 in the bridge VLAN table, set access-port PVIDs, build the trunk to the Dell. All of it with `vlan-filtering=no`; activation is a single deliberate step afterwards.
>
> **Do not forget:** the flat config is **temporary**. `temp-pool`, `temp-dhcp`, and `10.10.10.1/24` on `bridge1` get **replaced**, not built on — that address moves from `bridge1` to the `vlan10` interface when filtering goes on.

## 0. Before touching anything

- [ ] Read the ⚠️ **Two ways to lock yourself out** section at the bottom of this file, and install Winbox on the desktop
- [ ] Confirm the CRS326 is booted into **RouterOS**, not SwOS (it dual-boots; the boot setting decides)
- [x] **Serial console port confirmed present** — this is the primary recovery path and makes every Layer 3 lockout survivable
- [x] **Decision: proceeding without a console cable.** Port confirmed present (RJ45, labelled "Console"), but Phase 1 runs on Safe Mode + MAC-connect + config exports instead. Worth buying eventually — a USB-to-RJ45 console cable (~$15–30, FTDI or CH340, **not Prolific PL2303**) is a permanent tool that every later device will need; not a blocker now
- [ ] Verify MAC-connect is available before every risky change: `/tool mac-server print` and `/tool mac-server mac-winbox print`

> **⚠️ Without a console, three disciplines are mandatory, not optional:**
> 1. **Safe Mode (`Ctrl+X`) for every risky change.** Changes revert automatically if the session drops. It only protects against *session loss*, and its buffer is finite (~100 actions) — so enter Safe Mode, make **one** change, verify, commit, exit. Not twenty changes in a batch.
> 2. **Export after every working milestone** (`/export file=phase1-stageN`, then drag the `.rsc` off via Winbox Files). This turns a lockout from a redo-the-phase disaster into a ten-minute reset-and-restore. RouterOS 7 hides sensitive values in a plain export, so these are safe to commit here — skim the first one to confirm.
> 3. **Do not touch `/tool mac-server` or `/ip neighbor discovery-settings` for the rest of Phase 1.** They are the only things that would break MAC-connect, and nothing in this phase needs them changed.
- [ ] Note the current working state: Dell's IP, how you SSH to it, and that `dangagne.com` resolves and loads
- [x] **XB6 recorded: LAN `10.0.0.1`, DHCP pool `10.0.0.100–10.0.0.253` — the whole `10.0.0.0/24` is off limits to internal VLANs**
- [x] **RouterOS 7.19.6 confirmed; direct upgrade to 7.24.1 (both v7, no staged migration)**

## 1. Bench configuration (switch NOT in the path yet)

*Everything in this section happens with the switch connected to nothing but the desktop. The house network is untouched and the website stays up throughout.*

**No laptop, so the switch comes to the desk.** It is small, fanless, and light — carry it to the desktop for bench work and move it to its final position at cutover. Any wall outlet is fine while configuring; it goes on the UPS at step 6.

> **⚠️ Topology change (single-NIC desktop, no console cable).** The desktop has one Ethernet port and no Wi-Fi, so keeping the switch fully isolated would mean swapping the cable between the XB6 and the switch constantly. **Instead the desktop moves behind the switch once §3 brings up WAN and NAT** — one cable then serves both switch management and internet.
>
> **Security:** no new internet exposure. The switch's WAN port takes a private `10.0.0.x` lease behind the XB6's NAT, and a second NAT layer sits on top. **The one window worth closing quickly** is between NAT coming up (§3) and the firewall existing (§4), during which the switch's management is reachable from the house LAN — other household devices, *not* the internet. Do the **input-chain rules immediately after NAT works**, before the forward-chain work.
>
> **⚠️ And the trap this creates:** §4's `input` rule accepts from **VLAN 10 only**. With the desktop plugged into the switch as the management station, **put its access port on VLAN 10 for the duration of Phase 1** — otherwise that rule locks you out of the only machine you have. Its permanent VLAN is a §8 decision.

- [ ] **Pre-download to the desktop first**, so the bench session needs no internet: the RouterOS `.npk` matching the architecture in `/system resource print`, the RouterBOOT package, Winbox, and **Netinstall** (insurance — download it before you need it)
- [ ] Power the switch from any wall outlet
- [ ] Connect the desktop's Ethernet port directly to a switch port with a white spare cable (keep house internet on Wi-Fi if the desktop has it)
- [ ] Connect with **Winbox by MAC address**, not by IP
- [ ] **Check the shipped RouterOS version.** If it is on v6, upgrade within 6.x to the latest before moving to v7 — an old v6 straight to v7 can go badly
- [ ] **Check `free-hdd-space` in `/system resource print` before uploading** — the CRS326 has only **16 MB of flash**, and the package must fit alongside the running OS
- [ ] Upload the `.npk` via Winbox **Files** drag-and-drop — **drop it in the root, not into a subfolder**, or the bootloader will not find it — and confirm the uploaded size matches the file on disk
- [ ] **If space is too tight:** temporarily connect ether1 → XB6 and use `/system package update check-for-updates` then `install`, which streams rather than staging a full copy. Unplug afterwards
- [ ] Reboot, reconnect by MAC, confirm 7.24.1, **then** `/system routerboard upgrade` and reboot again — that order matters

**Recorded:** ether1 MAC = `D0:EA:11:51:06:BA`
- [ ] **Reset to a clean slate FIRST:** `/system reset-configuration no-defaults=yes skip-backup=no` — this wipes the password and service settings too, so hardening before it is wasted work
- [ ] Reconnect by MAC after the reboot (no IP, `admin` with blank password — this is expected)
- [ ] Set a strong admin password: `/user set admin password="..."`
- [ ] Disable unused services: `/ip service print` then `/ip service disable telnet,ftp,www,api,api-ssl` — **keep ssh and winbox**

> **⚠️ Three hardening steps the standard MikroTik guides recommend that would lock you out right now.** Do **not** restrict `/tool mac-server` (that is MAC-connect, the safety net until the console cable arrives), do **not** disable `/ip neighbor discovery-settings` (that is how Winbox finds the switch), and do **not** set `/ip service set winbox address=10.10.10.0/24` before VLAN 10 exists. All three belong after §2.

> **CLI note:** `/ip service` only *enters* the menu. Commands like `print`, `set`, and `disable` are run inside it. `..` goes back up. Same pattern for every menu in RouterOS.

## IP plan

Third octet = VLAN ID, so any address identifies its own segment at a glance and firewall rules read as self-documenting.

| VLAN | Name | Subnet | Gateway | DHCP pool |
|---|---|---|---|---|
| **10** | Management | `10.10.10.0/24` | `10.10.10.1` | .100 – .200 |
| **20** | Trusted | `10.10.20.0/24` | `10.10.20.1` | .100 – .200 |
| **30** | IoT | `10.10.30.0/24` | `10.10.30.1` | .100 – .200 |
| **40** | DMZ | `10.10.40.0/24` | `10.10.40.1` | .100 – .200 |
| **99** | Native | *none* | *none* | *none* |
| — | **WAN (ether1)** | `10.0.0.0/24` (XB6) | `10.0.0.1` | **static `10.0.0.2`** |

**VLAN 99 gets no subnet, no gateway, no DHCP** — an empty VLAN with an IP address is not empty.

**Double-NAT is expected and fine:** `10.10.x.0/24` → `10.0.0.0/24` → internet. The website's Cloudflare Tunnel is outbound-only, so it is unaffected by either layer.

## 2. Build the Layer 2 fabric

- [ ] Create one bridge (`bridge1`) with `vlan-filtering=no` for now — **filtering goes on last, deliberately**
- [ ] Add all LAN ports to the bridge; leave the WAN port **out** of it
- [ ] Define VLANs 10, 20, 30, 40, 99 in the bridge VLAN table
- [ ] Set access ports: `pvid` per port, per the VLAN plan in README.md
- [ ] Set the trunk port to the Dell: tagged 10/20/30/40, `pvid=99`
- [ ] Create the VLAN interfaces (`/interface vlan`) for 10, 20, 30, 40 on `bridge1`
- [ ] Assign each VLAN interface its gateway IP
- [ ] **Add your management access to VLAN 10 before enabling filtering**
- [ ] Enable `vlan-filtering=yes` — **in Safe Mode** (`Ctrl-X`), so a mistake reverts on disconnect
- [ ] Verify hardware offload is active (`/interface bridge port print` — `HW` flag present)

## 3. Routing, DHCP, and DNS

- [x] **WAN configured static on ether1: `10.0.0.2/24`, default route via `10.0.0.1`.** Started as a DHCP client (leased `.176`), then converted — remove the client **before** adding the static address, and add the default route manually, since the client was providing it silently
- [ ] Add a DHCP server per VLAN, each with its own pool and gateway
- [ ] Set DNS servers and enable `allow-remote-requests` on the router
- [ ] Add the NAT masquerade rule on the WAN out-interface
- [ ] Move the desktop behind the switch: yellow ether1 → XB6, desktop → a **VLAN 10** access port
- [ ] Confirm the desktop gets an address and reaches the internet through the switch
- [ ] **Do §4's input-chain rules now, before continuing** — that closes the house-LAN exposure window

## 4. Firewall — the part that actually matters

*NAT is not a firewall. Every rule below is separate from it.*

- [ ] `input` chain: accept established/related, accept from VLAN 10 only, **drop everything else**
- [ ] `input` chain: explicitly drop all input on the WAN interface
- [ ] `forward` chain: accept established/related, drop invalid
- [ ] `forward`: VLAN 30 (IoT) → internet only, **blocked to 10, 20, 40**
- [ ] `forward`: VLAN 40 (DMZ) → internet only, **blocked to every internal VLAN**
- [ ] `forward`: VLAN 20 (Trusted) → internet, and to 40 only on the ports you actually need
- [ ] `forward`: default **drop** at the end of the chain
- [ ] Verify rule counters increment on the drops — a rule that never matches is usually in the wrong position

## 5. Verify before cutover — still on the bench

- [ ] From a VLAN 30 port, attempt to reach a VLAN 10 and a VLAN 20 host — **both must fail**
- [ ] From a VLAN 40 port, attempt to reach anything internal — **must fail**
- [ ] From VLAN 20, confirm you can reach the internet but **not** the switch's management
- [ ] Confirm the native VLAN on the trunk is **99** and that VLAN 1 is unused everywhere
- [ ] Port-scan the WAN interface from outside — expect nothing open
- [ ] **Export the config** (`/export file=phase1-verified`) and copy it off the switch

## 6. Physical cutover

- [ ] Move the switch to its final position and plug it into a **battery + surge** outlet on the UPS, not surge-only — if the switch drops during an outage the Dell is unreachable and the site is down anyway
- [ ] Put the **XB6 on battery + surge** too, for the same reason: no modem means no internet, so lab runtime is wasted without it
- [ ] Yellow cable: XB6 → switch **ether1** (WAN — ether1 by convention, so MikroTik docs and a future reset-to-defaults both line up)
- [x] **WAN is static, so no XB6 reservation is needed** — `10.0.0.2` sits outside the XB6's `.100–.253` pool and cannot be handed to anything else
- [ ] Blue cable: Dell → switch trunk port
- [ ] Black: desktop → switch VLAN 20 access port
- [ ] Label both ends of every run
- [ ] Confirm the desktop still reaches the internet through the new path

## 7. Move Proxmox onto the trunk

*⚠️ The step most likely to cost you access to the Dell. Have the display cable and keyboard ready before starting.*

- [ ] Take a written copy of the current `/etc/network/interfaces` before editing
- [ ] Make `vmbr0` VLAN-aware
- [ ] Move the Proxmox host management IP onto **VLAN 10**
- [ ] Apply, and confirm you can still reach the web UI on the new address
- [ ] Set the website VM's network device to **VLAN tag 40**
- [ ] Confirm the site is still reachable at `dangagne.com` — the Cloudflare Tunnel is outbound, so VLAN 40 only needs egress
- [ ] Confirm the website VM **cannot** reach the Proxmox host or the desktop

## 8. Document and close out

- [ ] **Write the IP plan and static allocation register** to this repo as markdown — per VLAN: subnet, gateway, DHCP pool range, and **which static addresses below the pool are reserved for what** (switch SVIs, Proxmox host, website VM, future AP/NAS/Home Assistant). This is hand-maintained IPAM, and it is what prevents a static being assigned inside a DHCP pool — the conflict that works until the pool hands the same address out
- [ ] Export the running config and commit it
- [ ] Draw the physical and logical diagrams (Objective 3.1 material — do it while it's fresh)
- [ ] Note the measured inter-VLAN routing throughput
- [ ] Update README.md with anything done differently from this plan

---

## ⚠️ Two ways to lock yourself out

**1. Enabling `vlan-filtering` without giving yourself a way back in.** The single most common RouterOS mistake. The instant filtering activates, untagged management traffic stops matching anything and the session dies.

**Protection: always make that change in Safe Mode** (`Ctrl-X` in the terminal, or the Safe Mode button in Winbox). If your session drops, RouterOS automatically reverts every change made since Safe Mode was entered.

**2. Changing Proxmox's network config remotely.** A syntax error or a wrong VLAN tag in `/etc/network/interfaces` takes the host off the network with no way back except a physical console.

**Protection: have the display cable and keyboard physically connected before you start step 7.**

### Recovery paths, weakest to strongest

| Method | Works when |
|---|---|
| **Serial console** ✅ | **Primary path.** Independent of all network config — survives any VLAN, IP, or firewall mistake, and shows RouterBOOT messages during a failed boot |
| **Winbox MAC connect** | IP config is broken but the switch still boots — connects at Layer 2, no IP needed |
| **Reset button** | Config is unusable; returns to defaults |
| **Netinstall** | Nothing else works — a bricked bootloader is the case the console cannot fix |

**⚠️ The console is unauthenticated at the physical layer** — anyone who can reach the switch gets a login prompt. This is the *lockable* control from objective 2.4 applying to this rack directly: physical access to the console is equivalent to administrative access, so the switch's final position should not be somewhere casual visitors reach.

---

## ⚠️ Known limitation: routing throughput

The CRS326 is a **switch with a router attached**, not a router. Switching between ports on the same VLAN is handled in the switch chip at line rate. **Inter-VLAN routing, NAT, and firewalling all run on the CPU** — a single-core 800 MHz ARM.

**Expect a few hundred Mbps for routed traffic, not gigabit.** Traffic that stays inside one VLAN is unaffected.

This is acceptable for the Phase 1 goal — building and understanding a segmented network — and it is worth measuring in step 8 so the number is known rather than assumed. If it ever becomes the bottleneck, the OPNsense-on-Dell option is still open.
