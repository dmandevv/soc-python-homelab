# Network Diagrams — Phase 1

Two views of the same network. **Each hides what the other shows:** the physical view draws one cable to the Dell, while the logical view draws two isolated segments — both are true, and neither diagram can express the other's fact.

Kept as Mermaid so they render on GitHub and still diff as text in git.

---

## Physical — what is plugged into what

```mermaid
graph TD
    NET([Internet])
    XB6["<b>XB6</b><br/>modem / router / Wi-Fi<br/>10.0.0.1"]
    E1["<b>ether1</b> — WAN<br/>10.0.0.2/24 static"]
    E2["<b>ether2</b> — trunk<br/>tagged 10,20,30,40"]
    E3["<b>ether3</b> — trunk<br/>reserved for AP (Phase 4)"]
    E8["<b>ether8</b> — access<br/>VLAN 20"]
    EU["<b>ether20-24</b><br/>disabled"]
    DESK["<b>Desktop</b><br/>10.10.20.50"]
    DELL["<b>Dell OptiPlex 7070</b><br/>Proxmox VE<br/>vmbr0 VLAN-aware"]
    HOST["<b>vmbr0.10</b> — host mgmt<br/>10.10.10.20"]
    VM["<b>Website VM</b><br/>ens18 tag 40<br/>10.10.40.10"]

    NET --- XB6
    XB6 -->|"yellow"| E1

    subgraph SW["CRS326-24G-2S+IN — RouterOS 7.24.1"]
        E1
        E2
        E3
        E8
        EU
    end

    E2 -->|"blue"| DELL
    E8 -->|"black"| DESK

    subgraph D["the Dell"]
        DELL --- HOST
        DELL --- VM
    end
```

**Note the single blue cable to the Dell.** It carries the host on VLAN 10 and the website VM on VLAN 40 — two segments that cannot reach each other, over one wire. That fact is invisible here and is the whole point of the second diagram.

### Cable map

| Colour | From | To | Purpose |
|---|---|---|---|
| 🟡 Yellow | XB6 LAN | switch **ether1** | WAN uplink — the only cable touching the public internet |
| 🔵 Blue | Dell `nic0` | switch **ether2** | Trunk — tagged 10/20/30/40 |
| ⚫ Black | Desktop | switch **ether8** | Access — VLAN 20 |

**Both ends of every run are labelled** with the same text, including the port number. A label on one end is useless when you are holding the other.

---

## Logical — how traffic moves

```mermaid
graph LR
    WAN([Internet])
    R{{"CRS326 — router / firewall<br/>NAT + stateful filtering"}}

    V10["<b>VLAN 10 — Management</b><br/>10.10.10.0/24<br/>Proxmox host"]
    V20["<b>VLAN 20 — Trusted</b><br/>10.10.20.0/24<br/>Desktop"]
    V30["<b>VLAN 30 — IoT</b><br/>10.10.30.0/24<br/>empty until Phase 4"]
    V40["<b>VLAN 40 — DMZ</b><br/>10.10.40.0/24<br/>Website VM"]
    V99["<b>VLAN 99 — Native</b><br/>no address, no devices"]

    V10 --- R
    V20 --- R
    V30 --- R
    V40 --- R
    R -->|"NAT via ether1"| WAN

    V10 -.->|"permitted"| V20
    V10 -.->|"permitted"| V30
    V10 -.->|"permitted"| V40
    V20 -.->|"TCP 22, 8006<br/>one host only"| V10
```

**Solid lines are routed adjacency. Dotted lines are what the firewall permits between segments.** Every pair without a dotted line is dropped by the forward chain's default deny.

### Traffic policy

| From ↓ To → | Internet | VLAN 10 | VLAN 20 | VLAN 30 | VLAN 40 |
|---|---|---|---|---|---|
| **10 Management** | ✅ | — | ✅ | ✅ | ✅ |
| **20 Trusted** | ✅ | ⚠️ one host, TCP 22/8006 | — | ❌ | ❌ |
| **30 IoT** | ✅ | ❌ | ❌ | — | ❌ |
| **40 DMZ** | ✅ | ❌ | ❌ | ❌ | — |

**The asymmetry is deliberate and is what a stateful firewall buys.** Management reaches every segment; nothing reaches management unbidden. A DMZ host can *answer* when spoken to — its replies match `established/related` — but it cannot *initiate* toward anything internal.

**VLAN 99 appears in neither routing nor policy**, because the router has no interface in it. It exists solely so the trunk's native VLAN is not VLAN 1, and it holds no devices — leaving a double-tagging attack nowhere to launch from.

---

## Verified, not assumed

Every cell above was tested rather than inferred:

| Test | Result |
|---|---|
| DMZ → Proxmox host, DMZ → Desktop | **Dropped** — 100% loss, forward drop counter incremented |
| Management → DMZ | **Permitted** |
| Trusted → DMZ | **Dropped** |
| Trusted → Management, TCP 8006 | **Permitted** — scoped to one address |
| WAN → switch management | **Dropped** — confirmed from off-network |

---

## Measured throughput — the CPU ceiling

The CRS326 is a **switch with a router attached**. Same-VLAN traffic is handled by the Marvell switch chip at line rate; **inter-VLAN routing, NAT, and firewalling run on the CPU.**

Measured with `iperf3` between the desktop (VLAN 20, ether8) and the Proxmox host (VLAN 10, ether2) — each link crossed once, so no hairpin distortion.

| Traffic | Throughput | Switch CPU |
|---|---|---|
| **Same VLAN** | Line rate | Untouched — hardware offloaded |
| **Cross-VLAN, single flow** | **251 Mbps** | 99% on one core, 43% on the other |
| **Cross-VLAN, 4 parallel flows** | **468 Mbps** | 100% and 69% |

**The single-flow ceiling is a per-core limit, not a device limit.** RouterOS does not spread one connection's routing work across cores, so a single transfer saturates one core while the other idles. Four parallel streams reached 1.86× the single-flow figure by engaging both.

**This is the same behaviour as link aggregation** — one flow is pinned to one path, and only many concurrent flows use the available capacity. The resource differs; the principle does not.

### ⚠️ Consequence for the Phase 4 NAS

A large file copy is **a single TCP flow**, so it gets the **251 Mbps** figure — parallelism does not help it. Across a 10G SFP+ link that is roughly **2.5% of the link**.

**The NAS and its primary consumer must share a VLAN**, so their traffic is switched by the Marvell chip rather than routed through the CPU. This is an architectural decision made at design time, not a setting that can be tuned afterwards.

If cross-VLAN storage access is ever genuinely required at speed, that is the point at which routing moves off the switch — the OPNsense-on-Dell option deliberately left open in the README.
