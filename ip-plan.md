# IP Plan and Static Allocation Register

Hand-maintained IPAM for the homelab. **Every static address must be recorded here before it is configured** — nothing on the switch tracks statics, so an unrecorded allocation exists only in someone's memory.

Superseded by NetBox in Phase 4 (see README). Until then, this file is the source of truth.

## Address scheme

Third octet = VLAN ID, so any address identifies its own segment on sight.

Within every /24:

| Range | Purpose |
|---|---|
| `.1` | Gateway — the VLAN's interface on the switch |
| `.2 – .99` | **Static assignments** (recorded below) |
| `.100 – .200` | DHCP pool |
| `.201 – .254` | Reserved — room to grow without renumbering |

**Statics sit below the pool by design**, so a static can never collide with an address the DHCP server might issue.

## Segments

| VLAN | Name | Subnet | Gateway | DHCP |
|---|---|---|---|---|
| **10** | Management | `10.10.10.0/24` | `10.10.10.1` | `.100–.200` |
| **20** | Trusted | `10.10.20.0/24` | `10.10.20.1` | `.100–.200` |
| **30** | IoT | `10.10.30.0/24` | `10.10.30.1` | `.100–.200` |
| **40** | DMZ | `10.10.40.0/24` | `10.10.40.1` | **none — static only** |
| **50** | **Sandbox** | `10.10.50.0/24` | `10.10.50.1` | `.100–.200` |
| **99** | Native (unused) | — | — | none |
| — | WAN (ether1) | `10.0.0.0/24` (XB6) | `10.0.0.1` | static `10.0.0.2` |

**VLAN 50 is the sandbox segment**, added 2026-09-07 for a Kali VM used with TryHackMe. It runs security tooling and connects a VPN into deliberately vulnerable networks, so it is the least trusted thing on the lab — **it reaches the internet and nothing else.** It gets its own VLAN rather than sharing VLAN 30 because a smart plug and a machine running Metasploit should not share a broadcast domain once Phase 4 brings real IoT devices.

**Its DHCP hands out an external resolver (1.1.1.1) rather than the switch**, so the sandbox needs no `input`-chain permit at all. One less rule, and one less path from the least trusted segment to the device that enforces every other boundary.

**VLAN 40 runs no DHCP server deliberately.** It holds one web server, which needs a stable address for firewall rules, DNS, and monitoring — and the absence of DHCP means an unauthorised device plugged into a DMZ port receives no address automatically.

## Static allocations

| Address | Device | VLAN | Status |
|---|---|---|---|
| `10.0.0.2` | CRS326 — WAN interface (ether1) | WAN | **Configured** |
| `10.10.10.1` | CRS326 — vlan10 gateway | 10 | **Configured** |
| `10.10.10.20` | Proxmox host — `vmbr0.10` | 10 | **Configured** |
| `10.10.10.30` | Bastion — SSH jump host (LXC) | 10 | **Configured** |
| `10.10.10.40` | Syslog collector (LXC) | 10 | **Configured** |
| `10.10.20.1` | CRS326 — vlan20 gateway | 20 | **Configured** |
| `10.10.20.50` | Desktop — management station | 20 | **Configured** — see note below |
| `10.10.30.1` | CRS326 — vlan30 gateway | 30 | **Configured** |
| `10.10.40.1` | CRS326 — vlan40 gateway | 40 | **Configured** |
| `10.10.40.10` | Website VM — `ens18` | 40 | **Configured** |
| `10.10.50.1` | CRS326 — vlan50 gateway | 50 | **Planned** |
| `10.10.50.10` | Debian VM — TryHackMe workstation | 50 | **Planned** |

**The bastion at `10.10.10.30` exists to stop Proxmox being the jump host.** Reaching another VLAN over SSH currently means jumping through the hypervisor, which already carries `forward` rule 11 and therefore reaches every segment. That works, and it means **one compromise gets the jump host, the hypervisor, and every VM on it** — three things that should be separable.

The bastion has **the same reach and a fraction of the surface**: `sshd` and nothing else, no hypervisor API, no VM disks. Reach reduction — its own VLAN with explicit per-destination permits instead of inheriting rule 11 — is a later refinement.

**⚠️ Jump, rather than adding firewall exceptions per destination.** A firewall rule grants **unauthenticated network reachability** to anything at that source address; a jump host grants **authenticated access** and leaves a login record. Use `ssh -J`, never agent forwarding — ProxyJump authenticates to the final host from the client through a tunnel, so the bastion relays bytes it cannot read.

**The syslog collector at `10.10.10.40` is the Phase 3 prerequisite.** The switch's log lives in RAM and rotates away within hours, and the 2026-09-08 outage proved the cost: every log needed to diagnose it sat on the machine that could not be reached, and none of it was readable until after recovery.

**⚠️ A log collector is a high-value target** — it holds the evidence, and an attacker who reaches it can delete their own traces. On VLAN 10 it inherits rule 12's reach to every segment, the same as Proxmox and the bastion. **The stricter design is a segment that can receive on 514 and initiate nothing**, so logs flow one way. Revisit when Phase 3 makes it worth the work.

**The desktop sits on VLAN 20, not VLAN 10, deliberately.** It is a general-purpose machine that browses the web and reads email, which makes it the highest-risk device on the network — and the management VLAN is the segment that can reach every device's management interface. Placing it in VLAN 20 keeps that boundary intact.

It reaches management through **two host-specific firewall exceptions**, both scoped to `10.10.20.50` alone rather than to VLAN 20 as a whole:

| Chain | Permits |
|---|---|
| `input` | The desktop → **the switch itself**, TCP 22 and 8291 |
| `forward` | The desktop → **the bastion**, TCP 22 |
| `forward` | The desktop → **Proxmox**, TCP 8006 |

**Narrowed 2026-09-09.** The `forward` rule previously permitted the desktop to reach **any host in VLAN 10** on TCP 22. It is now two host-scoped rules, so the desktop can open a shell on the bastion and nothing else — every other destination goes through the jump.

**⚠️ The `input` rule stays direct, deliberately.** It is the recovery path to the switch, and a recovery path must not depend on a container running on a hypervisor behind the thing it recovers. It is earmarked for removal **only** once the console is proven working — see `phase-1-checklist.md`.

**⚠️ `input` is "to the switch"; `forward` is "through the switch".** Adding `dst-address=10.10.10.30` to the `input` rule made it unmatchable — the bastion is not the switch — and silently removed the desktop's ability to open a new session to the switch at all. The existing session survived on `established,related`, which hid it. **Test rule changes with a fresh connection, never the one already open.**

**If the desktop's address ever changes, both rules must be updated**, or management access silently stops working. That coupling is the cost of host-scoped rules, and the reason the address is static rather than leased.

## Planned (Phase 4)

| Address | Device | VLAN |
|---|---|---|
| `10.10.10.30` | Access point — management | 10 |
| `10.10.30.10` | Home Assistant (Raspberry Pi) | 30 |
| `10.10.10.40` | NAS — management | 10 |

*(Planned entries are placeholders. Move a row into **Static allocations** and mark it Configured when it is actually assigned.)*
