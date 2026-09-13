# Detections

Rules that run against the lab's telemetry. Where [audits.md](audits.md) records deliberate reviews and [incidents.md](incidents.md) records things that broke, this records **what is being watched continuously, and what each rule is blind to.**

**A script becomes a detection when its limits are written down.** Every rule here states what it catches, what it misses, and how it was proven to fire — because an untested rule is an assumption, and an unbounded one gets trusted past its evidence.

**Current platform: cron on the syslog collector.** Deliberately primitive. These move into Wazuh in Phase 3, and the point of writing them by hand first is to know what the SIEM is doing rather than trusting a dashboard.

---

## DET-001 — Syslog hostname impersonation

**Status:** ✅ Live since 2026-09-12 · **Severity:** high · **Facility:** `auth` → `/var/log/auth.log`

### What it detects

A host sending syslog under **a hostname that is not its own.**

### Why it is possible at all

**Syslog has no authentication at any layer.** The hostname is a plain-text field inside the message, composed by the sender:

```
<134>Sep 12 10:14:02 switch dhcp,info assigned 10.10.20.50 to a4:bb:...
                     ^^^^^^
                     sender-supplied, unverified
```

Anything that can reach TCP 514 can claim to be anything. **The original collector template named files from that field**, so a forged hostname wrote straight into another device's log — the one file an investigation would treat as authoritative.

### The control that makes it detectable

The rsyslog template was rebound so the **directory** comes from the socket and only the **filename** comes from the message:

```
/var/log/remote/%FROMHOST-IP%/%HOSTNAME%.log
```

`%FROMHOST-IP%` is read from the kernel's peer address, not parsed from the message. **Over TCP it cannot be forged without actually holding that address.**

**The impersonation still succeeds — it just can no longer hide.** A liar is confined to its own IP's directory, and the lie is preserved as a filename instead of being merged into the truth.

### Logic

`/usr/local/sbin/syslog-sentry`, every 10 minutes. For each directory under `/var/log/remote/`:

| Condition | Alert |
|---|---|
| IP has no entry in `/etc/syslog-sentry/expected.txt` | `UNKNOWN SENDER` |
| A filename in that directory ≠ the allowlisted hostname | `HOSTNAME MISMATCH` |

### Validation

**Proven, not assumed.** A syslog message was injected by hand from the bastion carrying the switch's hostname:

```
printf '<134>Sep 12 00:00:00 CRS326 INJECTED-BY-HAND\n' | nc 10.10.10.40 514
```

The next run alerted:

```
HOSTNAME MISMATCH: 10.10.10.30 claims to be 'CRS326', expected 'bastion'
```

**Both branches were also exercised** — the `UNKNOWN SENDER` path fired separately on a host with no allowlist entry.

### What it misses

- **UDP.** Source addresses are forgeable outright with no handshake, so `%FROMHOST-IP%` means nothing on UDP 514. **Closing UDP is the fix**, once every sender is confirmed on TCP
- **A correct hostname sent from an allowlisted IP.** If a permitted sender is compromised, everything it writes is indistinguishable from legitimate
- **Content.** The rule reads filenames, never message bodies. A sender lying *inside* its own log passes cleanly

### Known noise

**None in steady state.** The alert fires per run while a bad file exists, so a single injection alerts every 10 minutes until the file is removed. **Left alone that becomes alert fatigue**, which is why cleanup is part of the response rather than an afterthought.

---

## DET-002 — Sender silence

**Status:** ✅ Live since 2026-09-12 · **Severity:** medium · **Facility:** `local0` → `/var/log/syslog`

### What it detects

An expected sender that has **stopped sending.**

### Why it matters more than it sounds

**DET-001 detects a lie. It cannot detect absence.** An attacker who disables logging produces no events at all, and a host with nothing to say looks identical to a host that has been silenced.

**This is a dead man's switch** — it alerts on the *non-arrival* of something expected, which is the only way to make silence loud.

### Why it beats a ping check

`netwatch` proves a device answers ICMP. This proves **the entire logging path works end to end**: the device generates, the network delivers, rsyslog parses, the disk accepts. Breaks anywhere in that chain go quiet while the host stays perfectly reachable.

### Logic

`/usr/local/sbin/syslog-heartbeat`, every 5 minutes. For each entry in the allowlist:

| Condition | Alert |
|---|---|
| No directory under `/var/log/remote/` | `SILENT: <host> has never sent logs` |
| No `*.log` modified in the last **15 minutes** | `SILENT: nothing from <host> in 15 minutes` |

**Threshold is ~3× the heartbeat interval.** Tighter and a single dropped message pages you; looser and the blind window grows.

### The heartbeat itself

Senders emit a periodic message so that a quiet device does not look dead:

```
# RouterOS
/system scheduler add name=heartbeat interval=5m on-event={:log info "heartbeat"}
```

**⚠️ The switch's remote logging rule must carry the topic the heartbeat is emitted under.** `:log info` files under `script,info`; a remote rule shipping only `error` and `critical` generates the beat and never sends it. **A heartbeat that cannot reach the collector is worse than none**, because it makes the path look monitored.

### It keys on file mtime, not on the word "heartbeat"

**Deliberate.** The question is *"is this sender's path working?"*, and a device sending real logs is already answering yes. **The heartbeat is a floor for quiet devices**, not the thing being counted.

**Consequence for testing:** disabling the scheduler alone does not produce silence on a chatty device. The real test is disabling the remote logging action entirely.

### Validation

Remote logging was disabled on the switch with the threshold temporarily cut to 3 minutes. Both branches fired:

```
SILENT: nothing from CRS326 (10.10.10.1) in 3 minutes
SILENT: pve1 (10.10.10.20) has never sent logs
```

### What it misses

- **Partial suppression.** An attacker who deletes only their own events keeps the heartbeat flowing. **Catching that needs volume baselining** — a sender whose rate collapses while still beating
- **The collector itself.** Its own logs never enter `/var/log/remote`, so it cannot appear in this rule. Covered by DET-003 instead
- **Queued-but-undelivered logs.** Proxmox buffers up to 10,000 messages; the beat resumes on reconnect and the outage leaves no alert behind, only a timestamp gap

---

## DET-003 — Collector unreachable

**Status:** ✅ Live since 2026-09-12 · **Severity:** high · **Runs on:** the switch

### What it detects

The syslog collector no longer accepting connections.

### Why it cannot live on the collector

**Nothing can monitor its own death.** If the collector fails, every rule running on it fails with it and the silence is total and unremarked — the failure mode that most resembles everything being fine.

**The answer at this scale is mutual monitoring.** The switch watches the collector, the collector watches the switch, and **neither vouches for itself.**

### Logic

```
/tool netwatch add name=collector host=10.10.10.40 type=tcp-conn port=514 \
  interval=1m down-script={:log error "syslog collector unreachable"}
```

**`type=tcp-conn`, not `simple`.** A ping proves the container is up; a TCP connect to 514 proves **rsyslog is listening and accepting.** Those diverge exactly when it matters — a crashed daemon in a healthy container answers pings all day.

**Logged at `error`**, a topic the remote rule already ships. The alert travels to the collector when it can and stays in the switch's own log when it cannot — **which is the case this exists for.**

### What it misses

- **A collector that accepts connections and discards messages.** A full disk, a broken ruleset, or a `stop` in the wrong place all leave 514 answering normally
- **Its own full disk.** The collector cannot alert on that, since the alert would be written to the disk that is full

---

## Open gaps

Recorded rather than left implicit:

| Gap | Notes |
|---|---|
| **UDP 514 still open** | Undermines DET-001 entirely for anything that uses it. Close once every sender is confirmed on TCP |
| **The collector's logs exist only on the collector** | Every other host has an off-box copy; the machine holding the evidence does not. Needs a second destination |
| **No volume baselining** | The blind spot shared by DET-001 and DET-002 — partial log suppression passes both |
| **Collector disk space** | Unmonitored, and cannot be self-monitored. Belongs on the switch or a future Wazuh agent |
| **Alerts have no delivery path** | They land in files. Nothing pages anyone. Acceptable while the analyst and the operator are the same person, and it is the first thing a SIEM fixes |
