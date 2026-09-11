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

- [x] **Persist the ethtool call.** Done 2026-09-08 — verified across a reboot:

  ```
  auto nic0
  iface nic0 inet manual
          post-up /sbin/ethtool -K nic0 tso off gso off gro off || true
  ```

  **`auto nic0` is what makes it run.** The interface previously had no `auto` line and was brought up implicitly as a bridge port, which is not a path a `post-up` can be relied on to survive.

  **`|| true` is what makes it safe.** A `post-up` that exits non-zero marks the interface **failed**, so without it a missing or changed `ethtool` would leave the bridge with no uplink — trading a possible intermittent hang for a guaranteed outage on a headless machine. **A tuning step must never be able to prevent the thing it tunes from working.**
- [x] **`nut-driver@cyberpower`** — **resolved, and it was not what it looked like.** Verified 2026-09-09.

  **It had already fixed itself.** The Aug 22 failures were historical; the service came up cleanly at the Sep 8 reboot and had been running 24 hours by the time it was checked. Reading a failure at the *start* of a 17-day boot and assuming it was still true is the same mistake as reading the head of `journalctl -b -1` instead of the tail.

  **⚠️ Power still could not have been ruled out for the outage** — that part stands. `upsmon` reads the UPS, but nothing was recording its state anywhere durable.

  Confirmed working end to end: `upsc cyberpower` returns full data (`ups.status: OL`, 100% charge, **~53 min runtime at 15% load**), and `upsmon.conf` carries a valid `MONITOR` line with `SHUTDOWNCMD` and `MODE=standalone`, so a power cut triggers a real shutdown rather than only a notification.

  **⚠️ Two gotchas found while rotating the monitoring password:**
  - **NUT treats `#` as a comment character mid-line.** A password containing one truncates silently, leaving a four-field `MONITOR` line that NUT rejects as "old-style ... without a username" — an error naming the symptom and not the cause. **Space and `"` break it the same way**; quote the value if it must contain them.
  - **systemd stops retrying after five failures.** `systemctl restart` is then refused with "Start request repeated too quickly" until `systemctl reset-failed` clears the counter — a state where the config is correct and the service still will not launch.

  **Not yet tested: the shutdown itself.** Pulling the UPS mains lead for 30 seconds proves detection (`OL` → `OB`) and is non-destructive. Proving the shutdown fires means letting it actually halt the host — worth doing deliberately, on an evening when the website being down does not matter.
- [ ] **Check for a Dell BIOS update** — several e1000e fixes shipped that way
- [ ] **Second interface in Phase 2** — the 2.5G USB NIC removes the single-uplink single point of failure
- [x] **Syslog collector** — ✅ built 2026-09-10. rsyslog LXC at `10.10.10.40`, switch shipping over TCP with ISO 8601 timestamps, per-host files, 30-day rotation. **The gap this incident exposed is closed for the switch** — not yet for Proxmox or the VMs. Details in the README

### Lessons

**"It crashed" was wrong, and it would have sent the investigation the wrong way.** The host was healthy the whole time. *What crashed my hypervisor* and *what hung my NIC* are different questions with different evidence. **Establish whether a thing is down or merely unreachable before deciding what to look at.**

**The evidence was on the unreachable machine.** Every log needed to diagnose this lived on the box that could not be reached, and none of it was readable until after recovery. That is the argument for shipping logs off the host, stated as an experience rather than a principle.

**Counting by day changed the severity.** 196 hang messages looked like weeks of chronic failure. Grouping them by date — `grep ... | awk '{print $1,$2}' | sort | uniq -c` — showed all 196 fell on one day. **One event, not a failing NIC.** The raw count invited the wrong conclusion; the distribution corrected it.

**A hypothesis that fits is not a cause.** A long-running OpenVPN tunnel is a plausible trigger and remains unproven. The mitigation was applied because it addresses the mechanism regardless of which trigger was real — which is the right move when you have one event and several candidate explanations.
