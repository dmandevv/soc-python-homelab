# Audit Log

Deliberate reviews of the live network, written up the way a SOC would write them. Where [incidents.md](incidents.md) records things that broke, this records things that were **looked for**.

**The discipline that makes it an audit rather than a drawing exercise: findings come from observed state, then get diffed against the documentation.** Anything that disagrees is a finding, in whichever direction.

---

## Audit 1 — Network map from observed state, 2026-09-11

**Scope:** the full Layer 1–3 picture. Rebuild the diagrams from what the devices report, and compare against `network-diagrams.md` and `ip-plan.md`.

**Method:** `/interface print`, `/interface ethernet monitor`, `/ip neighbor print`, `/ip neighbor discovery-settings print`, `/interface bridge port print`, `/interface bridge vlan print`, `/ip address print`, `/ip arp print`, plus `qm list`, `pct list` and the Proxmox guest configs.

### Findings

#### 1. ⚠️ Fifteen live unused access ports — four into Management

```
ether4-7     PVID 10   Management   enabled, no link
ether9-11    PVID 20   Trusted      enabled, no link
ether12-15   PVID 30   IoT          enabled, no link
ether16-19   PVID 40   DMZ          enabled, no link
```

All untagged access ports, all enabled, **all with DHCP waiting on their VLAN.**

**The Management four are the finding.** A cable into `ether4` yields a lease in `10.10.10.0/24`, and `forward` rule 12 — `in-interface=vlan10 accept` — grants **reach to every VLAN on the network.** Rule 3's `mgmt-hosts` restriction prevents managing the *switch* from there; it does nothing about lateral movement everywhere else.

**The checklist already says "physical access to the console is equivalent to administrative access." This is broader: physical access to any unused port is equivalent to VLAN 10 membership.**

`ether20-24` were disabled in Phase 1. The pre-assigned ranges never received the same treatment — a sensible provisioning plan, left live.

**Remediation:** disable every unused access port. Enable one when something needs it. This is objective 4.3's "disable unused ports and services" in its literal form.

#### 2. ⚠️ Neighbour discovery advertises on the WAN and every VLAN

`discover-interface-list: static` — every statically-configured interface — with `mode: tx-and-rx` and CDP, LLDP and MNDP all enabled.

**The switch announces its identity, model and RouterOS version on `ether1`** (toward the XB6 LAN, the closest thing here to untrusted territory) **and on `vlan50`** (the sandbox).

This **widens** the sandbox-only MNDP finding recorded during the VLAN 50 build. The WAN half was not previously noted.

**Remediation:** an interface list containing `vlan10` and `vlan20` only. `vlan20` must stay — it is how Winbox discovers the switch from the desktop, and the checklist explicitly warns against breaking that path.

#### 3. The switch can see no neighbours at all

`/ip neighbor print` returns nothing, despite discovery being enabled everywhere in `tx-and-rx`.

**Not a misconfiguration — the neighbours do not speak the protocols.** The XB6 almost certainly does not do LLDP, Debian does not without `lldpd`, and Windows is inconsistent.

**Consequence: the topology cannot be verified from the device's own perspective.** This map was built from configuration and ARP, which is inference; LLDP would make it evidence.

**Remediation attempted and reversed, same day.** `lldpd` was installed on Proxmox and then removed. Two reasons, both worth keeping:

**⚠️ LLDP cannot cross this trunk, and the trunk is right.** `ether2` is `admit-only-vlan-tagged`; LLDP frames are **untagged**. The switch discards them at ingress, and has no untagged egress on that port either, so **neither direction works**. Confirmed: `lldpcli show interfaces` showed `nic0` transmitting while `/ip neighbor print` stayed empty.

**Loosening the trunk to admit untagged frames would fix discovery and reopen double tagging.** That is not a trade worth making. **Two good practices genuinely conflict here and the security one wins.**

**⚠️ And it introduced an exposure that did not previously exist.** `lldpd` advertises on every interface by default, including Proxmox's per-VM firewall bridges — so the hypervisor was broadcasting its **hostname, exact kernel and Proxmox version, and management IP** onto the DMZ bridge and the sandbox bridge. Its only visible output was six self-loop neighbours through its own `fwbr*` veth pairs.

The website VM is the one machine with an inbound path from the internet. Handing a compromised web server the hypervisor's management address and a precise kernel version to look up is a poor trade for a discovery protocol that was not working.

**Outcome: removed.** A control that delivers no benefit and some exposure gets removed rather than tuned. **The topology map therefore remains inference rather than evidence** — acceptable on a network with three cables, and recorded as a real limitation rather than an oversight.

#### 4. The SFP+ ports are not bridge members

`sfp-sfpplus1` and `sfp-sfpplus2` lack the `S` (slave) flag — they are outside the bridge entirely. Anything plugged into them lands in no VLAN and forwards nowhere.

**Harmless today, a puzzling half hour in Phase 4** when the SFP+ backbone goes in. Recorded in the port map.

#### 5. `sandbox-thm` has no `onboot`

Confirmed as the reason it was found stopped on 2026-09-10. **Worth deciding deliberately rather than leaving implicit** — a sandbox that runs only when in use is defensible, but then a stale ARP entry is expected behaviour rather than a symptom.

#### 7. The hypervisor has an unused wireless interface

`lldpcli show interfaces` surfaced **`wlo1`** on the Dell, with the chassis advertising `Capability: Wlan, on`.

**Checked immediately, because a dual-homed hypervisor would be the most significant finding in this audit** — a live wireless association to the XB6 would be a route around every VLAN boundary, every firewall rule, the bastion, and the narrowed management access, all of which assume traffic to the Dell crosses `ether2`.

```
wlo1  DOWN  ac:67:5d:0e:2d:74  <BROADCAST,MULTICAST>
```

**Down, no address, no carrier. The hypervisor is single-homed as designed.**

**Recorded as latent rather than closed.** "Nobody configured it" is a weaker guarantee than "it cannot come up" — the same reasoning being applied to fifteen unused switch ports applies to an unused radio in the machine running every service.

**Remediation:** disable the WLAN radio in the BIOS, bundled with the pending `e1000e` firmware update and the AC Power Recovery setting the UPS shutdown test needs. Three things, one trip to the machine. Blacklisting the kernel module is the software alternative.

#### 6. A dynamic VLAN 1 exists

`added by pvid` — `bridge1` itself carries PVID 1, so VLAN 1 exists with the bridge untagged in it. Harmless, and inconsistent with native VLAN 99 everywhere else.

### Documentation drift found

`network-diagrams.md` predated the **bastion** and the **syslog collector**, and its policy matrix predated the 2026-09-09 narrowing of the desktop's reach. **Rebuilt from observed state as part of this audit.**

### Confirmed correct

An audit listing only problems misrepresents the system. These were checked and are right:

| Checked | Result |
|---|---|
| Link speed and duplex on all active ports | **1 Gbps full duplex**, auto-negotiation complete. No mismatches |
| ARP table | **Seven hosts, every one accounted for.** No unknown devices |
| Addresses against `ip-plan.md` | **Exact match**, comments applied |
| Guest VLAN tags against `ip-plan.md` | **Exact match** — 10, 10, 40, 50 |
| `ether1` outside the bridge | Correct — routed WAN interface |
| Trunk frame types | `admit-only-vlan-tagged` on `ether2` and `ether3` — **untagged frames rejected on trunks** |
| Access port frame types | `admit-only-untagged-and-priority-tagged` — **tagged frames rejected on access ports**, closing switch-spoofing |
| Native VLAN | 99, no address, no devices |
| `onboot` on bastion, syslog, website | Set |
| Hardware offload | Active on every bridge port |

### Action items

- [x] **Disable unused access ports** — `ether4-7`, `ether9-19`
- [x] **Scope neighbour discovery** to an interface list of `vlan10` and `vlan20`
- [x] ~~Install `lldpd` on Proxmox~~ — **attempted and reversed.** Incompatible with the trunk, and it leaked hypervisor details to the DMZ and sandbox. See finding 3
- [ ] **Disable the Dell's WLAN radio in the BIOS** — with the `e1000e` firmware update and AC Power Recovery, in one visit
- [ ] **Decide `onboot` for `sandbox-thm`** either way, deliberately
- [ ] Consider aligning `bridge1`'s PVID with native VLAN 99

### Lesson

**The findings clustered where nothing had ever failed.** Every one of these has been true since Phase 1, none produced a symptom, and none would have been found by fixing something. **Fifteen live ports into segmented VLANs is exactly the kind of thing that is invisible until someone plugs a cable in** — which is the argument for auditing on a schedule rather than on an incident.
