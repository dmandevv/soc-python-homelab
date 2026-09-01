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
| **99** | Native (unused) | — | — | none |
| — | WAN (ether1) | `10.0.0.0/24` (XB6) | `10.0.0.1` | static `10.0.0.2` |

**VLAN 40 runs no DHCP server deliberately.** It holds one web server, which needs a stable address for firewall rules, DNS, and monitoring — and the absence of DHCP means an unauthorised device plugged into a DMZ port receives no address automatically.

## Static allocations

| Address | Device | VLAN | Status |
|---|---|---|---|
| `10.0.0.2` | CRS326 — WAN interface (ether1) | WAN | **Configured** |
| `10.10.10.1` | CRS326 — vlan10 gateway | 10 | **Configured** |
| `10.10.10.50` | Desktop (management station) | 10 | **Configured** — temporary; may return to DHCP |
| `10.10.20.1` | CRS326 — vlan20 gateway | 20 | **Configured** |
| `10.10.30.1` | CRS326 — vlan30 gateway | 30 | **Configured** |
| `10.10.40.1` | CRS326 — vlan40 gateway | 40 | **Configured** |
| `10.10.40.10` | Website VM | 40 | **Reserved** — applied on the VM in §7 |

## Planned (Phase 4)

| Address | Device | VLAN |
|---|---|---|
| `10.10.10.20` | Proxmox host — management | 10 |
| `10.10.10.30` | Access point — management | 10 |
| `10.10.30.10` | Home Assistant (Raspberry Pi) | 30 |
| `10.10.10.40` | NAS — management | 10 |

*(Planned entries are placeholders. Move a row into **Static allocations** and mark it Configured when it is actually assigned.)*
