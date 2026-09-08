# Incident Log

Real incidents in this lab, written up the way a SOC would write them. The point is the discipline: what was observed, what was concluded, and which of those two the evidence actually supported.

---

## 2026-09-08 — Hypervisor unreachable; website offline

**Severity:** the public website was down. Everything on the Dell was unreachable at once.

### Summary

**The host did not crash.** Its single network interface stopped transmitting, which made a perfectly healthy hypervisor unreachable. It was then shut down by hand from the power button.

### Timeline

| Time | Event |
|---|---|
| **Aug 22 17:36** | Host boots. Uptime runs 17 days |
| **Aug 22 23:09–23:20** | `nut-driver@cyberpower` fails repeatedly and never recovers. **UPS monitoring dead from this point** |
| **Sep 8, during the day** | 196 `Detected Hardware Unit Hang` messages on `nic0`, **all on this date** |
| **Sep 8 15:53** | User returns to the desktop, finds nothing on the Dell reachable |
| **Sep 8 15:56:12–15** | Kernel logs the final `e1000e ... Detected Hardware Unit Hang` on `nic0` |
| **Sep 8 15:56:15** | `systemd-logind: Power key pressed short` → clean shutdown begins |
| — | Shutdown does not complete; `last -x` records the boot as `crash` |
| **Sep 8 15:57:10** | Host boots. Website returns |

### Root cause

**A transmit-unit hang on the onboard Intel I219 (`e1000e`) driver.** A well-documented defect on this chipset, commonly triggered by segmentation offload interacting with certain traffic patterns. Not a configuration fault.

### Why the impact was total

**`nic0` is the only uplink, and it carries all five VLANs.** When it stopped transmitting, Proxmox management, the website VM, and the sandbox VM went dark simultaneously — from a workstation this is indistinguishable from a dead host.

### Resolution

```
ethtool -K nic0 tso off gso off gro off
```

Verified all three read `off`. Moves segmentation from the NIC to the CPU — a rounding error on a gigabit link with an i5-8500T, and the standard trade for stability on this chipset.

### Action items

- [ ] **Persist the ethtool call** as a `post-up` line in `/etc/network/interfaces`. Runtime-only, so it is lost on the next reboot
- [ ] **Fix `nut-driver@cyberpower`** — broken since Aug 22, so a power event could not be ruled in or out from logs
- [ ] **Check for a Dell BIOS update** — several e1000e fixes shipped that way
- [ ] **Second interface in Phase 2** — the 2.5G USB NIC removes the single-uplink single point of failure
- [ ] **Syslog collector** — reinforces the existing Phase 3 item

### Lessons

**"It crashed" was wrong, and it would have sent the investigation the wrong way.** The host was healthy the whole time. *What crashed my hypervisor* and *what hung my NIC* are different questions with different evidence. **Establish whether a thing is down or merely unreachable before deciding what to look at.**

**The evidence was on the unreachable machine.** Every log needed to diagnose this lived on the box that could not be reached, and none of it was readable until after recovery. That is the argument for shipping logs off the host, stated as an experience rather than a principle.

**Counting by day changed the severity.** 196 hang messages looked like weeks of chronic failure. Grouping them by date — `grep ... | awk '{print $1,$2}' | sort | uniq -c` — showed all 196 fell on one day. **One event, not a failing NIC.** The raw count invited the wrong conclusion; the distribution corrected it.

**A hypothesis that fits is not a cause.** A long-running OpenVPN tunnel is a plausible trigger and remains unproven. The mitigation was applied because it addresses the mechanism regardless of which trigger was real — which is the right move when you have one event and several candidate explanations.
