# Phase 0 — Get the Website Live: Step-by-Step Checklist

Goal: portfolio site live at your domain, served from containers, on the Dell running as a hypervisor you'll keep through every later phase. Runs on the normal home network behind the XB6 — no networking gear yet, that's Phase 1.

---

## 1. Physical setup

- [x] Unbox the Dell OptiPlex Micro
- [x] Connect UPS (CyberPower CP1500PFCLCD) to a wall outlet
- [x] Plug the Dell into the UPS (not directly into the wall)
- [x] Connect display + keyboard/mouse temporarily (borrow desktop monitor) — only needed for the one-time Proxmox install, then goes headless
- [x] Connect Dell to the XB6 via the one long Cat6 run from the buy-once set

## 2. Prep the Proxmox installer

- [x] Download the latest Proxmox VE ISO from proxmox.com
- [x] Flash it to the 16GB USB stick (e.g. `balenaEtcher` or `Rufus`)

*(Do this from your desktop — nothing here touches the Dell yet, so it can happen any time before the install.)*

## 3. Before wiping — use Windows while it's still there

- [x] **Update the BIOS/firmware via Dell Command Update** — far harder once Proxmox is installed
- [x] Extract the product key: `(Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey`
- [x] Verify the refurb matches the listing — 32GB as **2×16GB dual channel**, NVMe capacity, CPU model
- [x] Note the Service Tag: `wmic bios get serialnumber` (or the sticker) for warranty lookups

> Note: the OEM key is hardware-bound to this Dell. It reactivates on a Windows reinstall *here*, but will **not** activate in a VM — budget a separate license if the Phase 3 Windows VM needs one.

## 4. Wipe Windows, install Proxmox VE

- [x] Boot the Dell from the USB stick (F12 for the one-time boot menu; F2 for BIOS setup if boot order needs changing)
- [x] Run the Proxmox installer, wipe the NVMe drive
- [x] Set a strong root password during install
- [x] Configure static IP for Proxmox on your home LAN (write it down — this is how you'll reach the web UI headless from now on)
- [x] Complete install, reboot, remove USB stick

## 5. First login and initial config

- [x] From another device on the network, browse to `https://<proxmox-ip>:8006`
- [x] Log in as root
- [x] Remove the "no valid subscription" popup annoyance (switch to the no-subscription repo) — optional but common
- [x] Run `apt update && apt full-upgrade` on the Proxmox host itself
- [x] Disconnect the temporary display/keyboard — go fully headless from here on

## 6. Create the Debian VM

- [x] Download a Debian netinst ISO, upload it to Proxmox (Datacenter → local storage → ISO Images → Upload)
- [x] Create a new VM: allocate a sensible slice of the 32GB RAM / 512GB NVMe (leave headroom for later phases — see the roadmap's Phase 3 note about RAM)
- [x] Install Debian inside the VM (minimal install, no desktop environment needed)
- [x] Set a static IP (or a DHCP reservation, once you have a real DHCP server in Phase 1 — for now, static is simplest)
- [x] Enable SSH server during install (or `apt install openssh-server` after)
- [x] Set up SSH key-based login from your desktop; disable password auth once key login works

## 7. Harden the Debian VM (baseline, more comes in Phase 2)

- [x] `apt update && apt full-upgrade`
- [x] Enable unattended-upgrades for security patches
- [x] Set up a basic firewall on the VM itself (`ufw` — **SSH only**; the tunnel is outbound-initiated, so no inbound HTTP/HTTPS is needed)
- [x] Create a non-root user with sudo, confirm you can log in as it before locking down root SSH login

## 8. Install Docker

- [x] Install Docker Engine + Docker Compose plugin (official Docker install script/repo, not the Debian-packaged version — usually more current)
- [x] Add your non-root user to the `docker` group
- [x] Verify with `docker run hello-world`

## 9. Containerize the portfolio site

- [x] Write a `Dockerfile` for the Flask app (base image, install deps, copy app code)
- [x] Configure Gunicorn as the WSGI server (don't run Flask's dev server in production)
- [x] Write a `docker-compose.yml` for the app container
- [x] Build and run locally on the VM, confirm the site responds on its internal port (e.g. `curl localhost:8000`)

## 10. Register the domain

- [x] Register your domain (`yourname.dev` or similar)
- [x] Create a free Cloudflare account
- [x] Add the domain to Cloudflare, update nameservers at the registrar to Cloudflare's

## 11. Set up the Cloudflare Tunnel

- [x] Install `cloudflared` (as a container alongside the app, per the roadmap — add it to the same `docker-compose.yml`)
- [x] Authenticate `cloudflared` to your Cloudflare account, create a named tunnel
- [x] Add a config mapping the tunnel to the app container's internal address/port
- [x] Create the DNS record in Cloudflare (CNAME to the tunnel) — this is what makes port forwarding unnecessary
- [x] Start the tunnel container, confirm it shows "connected" in the Cloudflare dashboard

## 12. Verify

- [x] Browse to your domain from an external network (phone on cellular data, not home Wi-Fi) — confirms it's not just working locally
- [x] Confirm HTTPS is active (padlock, valid cert — Cloudflare handles this automatically)
- [x] Confirm no ports are forwarded on the XB6 (check the router's port forwarding page — should be empty for this)

## 13. UPS graceful shutdown (do this before you actually need it)

- [x] Connect UPS to the Dell via USB
- [x] Install NUT (Network UPS Tools) on Proxmox or the Debian VM
- [x] Configure NUT to trigger a graceful shutdown of the Dell on prolonged power loss
- [x] Test by unplugging the UPS from the wall (on battery) and confirming NUT detects it

---

## Milestone

**Reached 2026-08-22** — portfolio live at **dangagne.com**, served from containers, on a hypervisor every later phase builds on. No ports forwarded on the XB6, verified from an external network.

### Notes from the build

- **Domain registered through Cloudflare Registrar**, so no nameserver change was needed.
- **Two containers, no published ports.** `cloudflared` reaches the app at `web:8000` over an internal Docker network, so nothing binds to the VM's external interface — `docker ps` shows `8000/tcp` with no host mapping. This also sidesteps Docker's habit of writing iptables rules that bypass `ufw`.
- **Container hardening beyond the original plan:** non-root user, `.dockerignore` (it was copying `.git` into the image), unbuffered output, two Gunicorn workers with access logs on stdout.
- **The VM pulls from GitHub with a read-only deploy key** scoped to that one repo. Personal documents were moved to a separate `personal-docs` repo so a compromised VM can't reach them.
- **NUT took the most debugging.** The failure was `Can't claim USB device ... Entity not found`, which looked like a permissions problem — running the driver as root worked, as `nut` it didn't. It was actually an orphaned driver process from a manual `upsdrvctl start` still holding the device; `nut-driver-enumerator` auto-starts a driver as soon as `ups.conf` defines one, so the manual start was racing it. **Manage drivers only through systemd on this host.**
- **Measured runtime: ~190 minutes** at current load (`ups.load` reads 0 — the Dell is negligible against a 1000W unit). Low-battery shutdown triggers with 5 minutes remaining.

**Next:** Phase 1 — Network foundation (Network+): the MikroTik CRS326 running RouterOS as switch, router, and firewall in one, with VLANs 10/20/30/40 behind it. The website you just stood up moves onto that network once it exists.
