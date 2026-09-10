# Phase 1 — Network Foundation: Step-by-Step Checklist

Goal: a segmented, routed network built on the MikroTik CRS326 running RouterOS as switch, router, and firewall in one. VLANs 10/20/30/40 behind it, native VLAN 99 empty by design, and the Phase 0 website moved onto VLAN 40.

**The governing constraint: the website is already live.** Every step is ordered so the site stays up and a rollback is always one cable away.

---

## 0. Before touching anything

- [ ] Read the ⚠️ **Two ways to lock yourself out** section at the bottom of this file, and install Winbox on the desktop
- [ ] Confirm the CRS326 is booted into **RouterOS**, not SwOS (it dual-boots; the boot setting decides)
- [x] **Serial console port confirmed present** — this is the primary recovery path and makes every Layer 3 lockout survivable
- [x] **Console cable purchased and tested 2026-09-06 — ⚠️ UNRESOLVED.** USB-to-RJ45, genuine FTDI FT232R. **Transmit works; receive does not.** The switch logs serial console login attempts, so keystrokes arrive and the baud rate is correct — but nothing the switch sends is ever displayed. **Ruled out — host side:** driver (FTDI `ftdi_sio`, status OK, no problem code), COM port, baud rate, flow control, terminal software (PuTTY, Tera Term), port contention, and the operating system itself — the cable enumerates cleanly on Proxmox as `/dev/ttyUSB0` and behaves identically there.

**Ruled out — switch side:** `/port print detail` reports `baud-rate=115200 data-bits=8 parity=none stop-bits=1 flow-control=none` with `used-by="Serial Console(#0)"`. Nothing in the device configuration suppresses output.

**⚠️ A blind console session does work.** Logging in without seeing a character succeeds — `user admin logged in via local` appears in the log — so **transmit is reliable and commands can be issued unseen.** That is a usable, if uncomfortable, recovery path: a lockout could be undone by typing a command you cannot read.

**One genuine complication found along the way:** serial ports are exclusive, and alternating between two terminal programs was silently stealing the port from one another — the log shows a session dropping the moment the second program claimed it. Much of the apparent intermittency was that, not the cable. **Confirmed by the reboot test:** RouterBOOT prints to the serial console before RouterOS loads, before session logic and before authentication, so nothing but a broken receive path can suppress it — and nothing appeared. **⚠️ SUPERSEDED 2026-09-09 — see the section below.** This paragraph previously concluded that the loopback test had exonerated the switch and proved the cable at fault. **A second, entirely different cable produces the identical symptom**, so that conclusion cannot stand.

**The loopback test should have come first.** It isolates the cable completely in about two minutes, whereas the session instead worked through drivers, COM ports, baud rates, flow control, two terminal programs, two operating systems, and a reboot test — all of which left cable and switch-port faults indistinguishable. **When a link is dead in one direction, test the cable alone before testing anything it connects to.**

## Console, second attempt — 2026-09-09

**Two-piece cable: DTECH USB-to-DB9 (FTDI) plus a Cisco-pinout RJ45-to-DB9 rollover. Same symptom as the first cable — transmit works, receive is dead.**

### What is proven

| Link | Status | Evidence |
|---|---|---|
| PC TxD → DB9 3 → RJ45 6 → switch RxD | ✅ **Works** | `/system serial-terminal` displays typed characters byte-for-byte |
| Console login over serial | ✅ **Works** | Authenticated blind; commands appear in `admin`'s shared history |
| Command execution over serial | ✅ **Works** | `:log info "blindtest"` typed blind produced the log entry |
| USB adapter RxD → terminal | ✅ **Works** | Connector-insertion noise arrived as garbage bytes in PuTTY |
| RJ45 3 → DB9 2 (the return conductor) | ❓ **Unproven** | Cannot be isolated without a meter |
| The switch's console TX driver | ❓ **Unproven** | Same |

**Everything except one conductor and one driver is confirmed working.**

### Ruled out this session

- **Baud, framing, flow control** — matched at both ends and re-verified
- **`silent-boot`** — set to `no`, and RouterBOOT still printed nothing at a matched rate
- **RouterBOOT's own baud rate**, which is a **separate setting** from `/port set serial0 baud-rate` and was not checked in the first attempt
- **Marginal signalling.** A `\0C` in the log looked like a corrupted `\0D`; it was literally **Ctrl-L**. The switch receives exactly what is sent

### The two things that wasted the most time

**⚠️ Serial ports are exclusive, and this bit three times in one evening.** PuTTY and Tera Term silently steal the port from one another with no error. **One terminal program, and confirm the other's process is gone** — `ttermpro.exe` survives closing its window.

**⚠️ `/system console` must be enabled and holding the port, and it was repeatedly left disabled.** Freeing the port for `serial-terminal` requires `console disable`, and forgetting to re-enable it means every subsequent test runs against a switched-off console. Check `/system console print` for the **`X`** flag and `/port print detail` for `used-by="Serial Console(#0)"` **before** concluding anything.

### To close it

A **multimeter** (~$20) settles it: continuity from RJ45 pin 3 to DB9 pin 2. Or a **second RJ45-to-DB9 adapter** (~$10) settles it by substitution. No further software test can distinguish the two remaining candidates — every test that drives the switch's transmitter is equally silent whether the driver is dead or the wire is open.

---

## Blind recovery card

**The console transmits nothing, but it receives, authenticates, and executes.** That makes it a usable recovery path — verified 2026-09-09, not assumed.

**Technique:**

1. **Press `Ctrl-C` before every command.** You cannot see the line you are editing, so a stray keystroke or a leftover fragment silently malforms the next command. `Ctrl-C` abandons the line and gives a known-empty start. **This is not optional when blind.**
2. **Paste, do not type.** Right-click pastes in PuTTY. A pasted string cannot be mistyped.
3. **One command at a time**, then pause.
4. **Verification is whether access returns.** In a real lockout there is no second channel — that is why the console is being used at all.
5. **Link LEDs confirm a reboot took.** If they go dark, the login and the command both landed.

**Login sequence, blind:**

```
Ctrl-C
admin        <Enter>
<password>   <Enter>
Ctrl-C
```

**The likely lockouts and their one-line undo:**

| Lockout | Paste this |
|---|---|
| Firewall `input` drop rule locked you out | `/ip firewall filter disable [find chain=input action=drop]` |
| VLAN filtering broke the trunk | `/interface bridge set bridge1 vlan-filtering=no` |
| Management gateway address wrong | `/ip address set [find interface=vlan10] address=10.10.10.1/24` |
| SSH disabled | `/ip service enable [find name=ssh]` |
| Winbox disabled | `/ip service enable [find name=winbox]` |
| The `management LAN` rule broke after tightening | `/ip firewall filter disable [find comment="management LAN"]` |
| Anything unpersisted | `/system reboot` then `y` on the next line |

**⚠️ `/system reboot` prompts `[y/N]` invisibly.** The `y` goes on its own line. Forgetting it means nothing happens and you will assume the console failed.

**Rehearse it now while Winbox still works.** Type a command blind in PuTTY, read the result in the Winbox terminal — `admin`'s command history is shared between sessions, so both show the same buffer. That rehearsal channel is exactly what will be missing during a real lockout, which is the reason to use it beforehand.

**Next attempt — go two-piece:** a **USB-to-DB9 serial adapter** plus an **RJ45-to-DB9 console adapter**. If the fault is a pinout difference rather than a defect, another Cisco-pinout USB-to-RJ45 cable will fail identically; a separate RJ45-to-DB9 adapter can be selected or re-pinned to match MikroTik, and either half swapped to isolate a future fault.

**The pinout to match — MikroTik's own table** (RouterOS docs, RJ45 serial port on RB2011/3011/4011, CCR1072 and CRS series). It is identical to the Cisco rollover console pinout, so a genuine `CAB-CONSOLE-RJ45` / `72-3383-01` cable is the correct part:

| RJ45 pin | Signal | DB-9 pin | DB-25 pin |
|---|---|---|---|
| 1 | RTS | 8 | 5 |
| 2 | DTR | 6 | 6 |
| 3 | TxD | 2 | 3 |
| 4 | Ground | 5 | 7 |
| 5 | Ground | 5 | 7 |
| 6 | RxD | 3 | 2 |
| 7 | DSR | 4 | 20 |
| 8 | CTS | 7 | 4 |

**MikroTik documents the port default as hardware (RTS/CTS) flow control** — but this switch reports `flow-control=none`, so a 3-conductor cable (TxD, RxD, Ground only) is sufficient here and handshake lines were never the cause. Buy the FTDI half on chipset, not price: counterfeit Prolific PL2303 chips are bricked by the current Windows driver.
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

- [x] **Pre-download to the desktop first**, so the bench session needs no internet: the RouterOS `.npk` matching the architecture in `/system resource print`, the RouterBOOT package, Winbox, and **Netinstall** (insurance — download it before you need it)
- [x] Power the switch from any wall outlet
- [x] Connect the desktop's Ethernet port directly to a switch port with a white spare cable (keep house internet on Wi-Fi if the desktop has it)
- [x] Connect with **Winbox by MAC address**, not by IP
- [x] **Check the shipped RouterOS version.** If it is on v6, upgrade within 6.x to the latest before moving to v7 — an old v6 straight to v7 can go badly
- [x] **Check `free-hdd-space` in `/system resource print` before uploading** — the CRS326 has only **16 MB of flash**, and the package must fit alongside the running OS
- [x] Upload the `.npk` via Winbox **Files** drag-and-drop — **drop it in the root, not into a subfolder**, or the bootloader will not find it — and confirm the uploaded size matches the file on disk
- [x] **If space is too tight:** temporarily connect ether1 → XB6 and use `/system package update check-for-updates` then `install`, which streams rather than staging a full copy. Unplug afterwards
- [x] Reboot, reconnect by MAC, confirm 7.24.1, **then** `/system routerboard upgrade` and reboot again — that order matters

**Recorded:** ether1 MAC = `D0:EA:11:51:06:BA`
- [x] **Reset to a clean slate FIRST:** `/system reset-configuration no-defaults=yes skip-backup=no` — this wipes the password and service settings too, so hardening before it is wasted work
- [x] Reconnect by MAC after the reboot (no IP, `admin` with blank password — this is expected)
- [x] Set a strong admin password: `/user set admin password="..."`
- [x] Disable unused services: `/ip service print` then `/ip service disable telnet,ftp,www,api,api-ssl` — **keep ssh and winbox**

> **⚠️ Three hardening steps the standard MikroTik guides recommend that would lock you out right now.** Do **not** restrict `/tool mac-server` (that is MAC-connect, the safety net — narrowed but deliberately kept, see the end of this file), do **not** disable `/ip neighbor discovery-settings` (that is how Winbox finds the switch), and do **not** set `/ip service set winbox address=10.10.10.0/24` before VLAN 10 exists. All three belong after §2.

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

- [x] Create one bridge (`bridge1`) with `vlan-filtering=no` for now — **filtering goes on last, deliberately**
- [x] Add all LAN ports to the bridge; leave the WAN port **out** of it
- [x] Define VLANs 10, 20, 30, 40, 99 in the bridge VLAN table
- [x] Set access ports: `pvid` per port, per the VLAN plan in README.md
- [x] Set the trunk port to the Dell: tagged 10/20/30/40, `pvid=99`
- [x] Create the VLAN interfaces (`/interface vlan`) for 10, 20, 30, 40 on `bridge1`
- [x] Assign each VLAN interface its gateway IP
- [x] **Add your management access to VLAN 10 before enabling filtering**
- [x] Enable `vlan-filtering=yes` — **in Safe Mode** (`Ctrl-X`), so a mistake reverts on disconnect
- [x] Verify hardware offload is active (`/interface bridge port print` — `HW` flag present)

## 3. Routing, DHCP, and DNS

- [x] **WAN configured static on ether1: `10.0.0.2/24`, default route via `10.0.0.1`.** Started as a DHCP client (leased `.176`), then converted — remove the client **before** adding the static address, and add the default route manually, since the client was providing it silently
- [x] Add a DHCP server per VLAN, each with its own pool and gateway
- [x] Set DNS servers and enable `allow-remote-requests` on the router
- [x] Add the NAT masquerade rule on the WAN out-interface
- [x] Move the desktop behind the switch: yellow ether1 → XB6, desktop → a **VLAN 10** access port
- [x] Confirm the desktop gets an address and reaches the internet through the switch
- [x] **Do §4's input-chain rules now, before continuing** — that closes the house-LAN exposure window

## 4. Firewall — the part that actually matters

*NAT is not a firewall. Every rule below is separate from it.*

- [x] `input` chain: accept established/related, accept from VLAN 10 only, **drop everything else**
- [x] `input` chain: explicitly drop all input on the WAN interface
- [x] `forward` chain: accept established/related, drop invalid
- [x] `forward`: VLAN 30 (IoT) → internet only, **blocked to 10, 20, 40**
- [x] `forward`: VLAN 40 (DMZ) → internet only, **blocked to every internal VLAN**
- [x] `forward`: VLAN 20 (Trusted) → internet, and to 40 only on the ports you actually need
- [x] `forward`: default **drop** at the end of the chain
- [x] Verify rule counters increment on the drops — a rule that never matches is usually in the wrong position

## 5. Verify before cutover — still on the bench

> **Deferred to §7 — only one host exists.** Proving VLAN 30 cannot reach VLAN 10 requires a device in VLAN 30. The forward chain is built and its default-deny is counting; it is enforced but not yet demonstrated. Test these once the Dell is trunked and hosts exist in more than one segment.

- [ ] From a VLAN 30 port, attempt to reach a VLAN 10 and a VLAN 20 host — **both must fail**
- [ ] From a VLAN 40 port, attempt to reach anything internal — **must fail**
- [x] From VLAN 20, confirmed internet access, DHCP, DNS, and scoped management via a single host rule
- [ ] Confirm the native VLAN on the trunk is **99** and that VLAN 1 is unused everywhere
- [ ] Port-scan the WAN interface from outside — expect nothing open
- [ ] **Export the config** (`/export file=phase1-verified`) and copy it off the switch

## 6. Physical cutover

- [ ] Move the switch to its final position and plug it into a **battery + surge** outlet on the UPS, not surge-only — if the switch drops during an outage the Dell is unreachable and the site is down anyway
- [ ] Put the **XB6 on battery + surge** too, for the same reason: no modem means no internet, so lab runtime is wasted without it
- [x] Yellow cable: XB6 → switch **ether1** (WAN — ether1 by convention, so MikroTik docs and a future reset-to-defaults both line up)
- [x] **WAN is static, so no XB6 reservation is needed** — `10.0.0.2` sits outside the XB6's `.100–.253` pool and cannot be handed to anything else
- [ ] Blue cable: Dell → switch trunk port
- [x] Black: desktop → switch VLAN 20 access port
- [ ] Label both ends of every run
- [x] Confirm the desktop still reaches the internet through the new path

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

---

## Build notes

**⚠️ Safe Mode cannot protect a change that breaks your own session.** Enabling `vlan-filtering` failed three times, and the config was correct every time. Moving `10.10.10.1/24` from `bridge1` to `vlan10` severs management for a second or two — Winbox notices, the session drops, and **Safe Mode dutifully reverts a configuration that would have worked.** The reversion was never triggered by a fault; it was triggered by the transition itself.

**The fix is to move the safety net off session state.** A revert script on a scheduler:

```
/system script add name=revert-vlan source={
  /interface bridge set bridge1 vlan-filtering=no
  /ip address set [find address~"10.10.10.1"] interface=bridge1
}
/system scheduler add name=auto-revert interval=5m on-event="/system script run revert-vlan"
```

Arm it, **test the revert script before relying on it**, make the change without Safe Mode, reconnect, verify, then `/system scheduler remove auto-revert`. If the change is bad, the timer undoes it. Use this pattern for any change whose transition breaks the management path.

**MAC-connect bypasses the IP firewall entirely.** Management from VLAN 20 appeared to work before any rule permitted it, because Winbox was connecting at Layer 2. **Anyone with Layer 2 access can attempt MAC-Winbox regardless of firewall rules.**

**⚠️ Open item found 2026-09-07 — the switch broadcasts MNDP into the sandbox.** Building VLAN 50 surfaced MikroTik Neighbor Discovery Protocol traffic on UDP 5678 originating from `10.10.50.1`, meaning the switch announces its identity, model and RouterOS version to the least trusted segment on the network. **Do not disable discovery globally** — Winbox depends on it, and that is one of the three lockout traps recorded above. The fix is restricting `/ip neighbor discovery-settings` to an interface list that excludes `vlan50`, which is safe because management runs from VLAN 20 and is unaffected.

### Resolved 2026-09-09 — narrowed rather than deferred

**The console is no longer being pursued as a recovery path.** Two cables, two evenings, and it transmits but has never displayed a character. It stays connected and remains usable **blind** — see the recovery card above — but the plan of "restrict MAC-connect once the console works" is abandoned rather than pending.

**So MAC-connect stays available from the desktop**, because without a console it is the only path that survives a broken IP configuration — a wrong address, a bad firewall rule, a VLAN filtering mistake. `input` rule 6 stays for the same reason.

**⚠️ But `allowed-interface-list=all` was the real exposure, and that is fixed.** `all` included **`ether1`** — so anything on the XB6's `10.0.0.0/24` could attempt MAC-Winbox at Layer 2, **bypassing every firewall rule on the device**. It also included the DMZ and the sandbox.

```
/interface list add name=mac-recovery comment="MAC-connect: recovery paths only"
/interface list member add list=mac-recovery interface=vlan20
/interface list member add list=mac-recovery interface=vlan10
/tool mac-server set allowed-interface-list=mac-recovery
/tool mac-server mac-winbox set allowed-interface-list=mac-recovery
/tool mac-server ping set enabled=no
```

| Path | Before | After |
|---|---|---|
| **WAN → MAC-connect** | **Open** | **Closed** |
| DMZ → MAC-connect | Open | **Closed** |
| Sandbox → MAC-connect | Open | **Closed** |
| Desktop → MAC-connect | Open | **Kept — it is the fallback** |

**⚠️ Test MAC-Winbox from the desktop before closing any session.** Winbox → Neighbors → connect by MAC rather than IP. Failing that check means the fallback is gone and the only thing left is a console that does not display.

**The lesson worth keeping:** the deferral was written as all-or-nothing — restrict everything, or nothing, once the console works. **Most of the benefit was in the half that cost nothing.** Closing the WAN, DMZ and sandbox paths never depended on the console at all, and waiting on it left a Layer 2 bypass open from the internet-facing side for weeks.

**DHCP and DNS are input-chain traffic.** A default-deny input chain silently blocks clients in every VLAN except the one explicitly permitted — no error, no log, the client simply never receives an address. Match on `in-interface-list` rather than `src-address`, since a DHCP discover originates from `0.0.0.0` and no source-address rule will ever match it.

**A specific-accept rule counts only the first packet of each connection.** The `established/related` rule at the top absorbs everything after the handshake, so a host rule showing single-digit packets is working correctly rather than barely matching.

**`resolvconf` is installed on the website VM, so `dns-nameservers` works there.** The general rule is that `dns-nameservers` in `/etc/network/interfaces` is ignored unless `resolvconf` is present — but on this VM it *is* present (v1.94, `systemd-resolved` inactive), which means DNS belongs in the interfaces file and **`/etc/resolv.conf` is generated and must not be hand-edited**. Editing it directly appears to work and is silently overwritten at the next `ifup`, so the failure surfaces after a reboot rather than immediately. Check `head -3 /etc/resolv.conf` and `dpkg -l | grep resolvconf` before deciding where DNS goes on any host.

**The Proxmox host and its Debian guests reload networking differently.** The host runs **ifupdown2**, so `ifreload -a` applies changes without dropping unaffected interfaces. A plain Debian VM has classic **ifupdown**, where that command does not exist — use `systemctl restart networking` instead.
