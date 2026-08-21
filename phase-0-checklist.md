# Phase 0 — Get the Website Live: Step-by-Step Checklist

Goal: portfolio site live at your domain, served from containers, on the Dell running as a hypervisor you'll keep through every later phase. Runs on the normal home network behind the XB6 — no networking gear yet, that's Phase 1.

---

## 1. Physical setup

- [ ] Unbox the Dell OptiPlex Micro
- [ ] Connect UPS (CyberPower CP1500PFCLCD) to a wall outlet
- [ ] Plug the Dell into the UPS (not directly into the wall)
- [ ] Connect display + keyboard/mouse temporarily (borrow desktop monitor) — only needed for the one-time Proxmox install, then goes headless
- [ ] Connect Dell to the XB6 via the one long Cat6 run from the buy-once set

## 2. Prep the Proxmox installer

- [ ] Download the latest Proxmox VE ISO from proxmox.com
- [ ] Flash it to the 16GB USB stick (e.g. `balenaEtcher` or `Rufus`)

*(Do this from your desktop — nothing here touches the Dell yet, so it can happen any time before the install.)*

## 3. Before wiping — use Windows while it's still there

- [ ] **Update the BIOS/firmware via Dell Command Update** — far harder once Proxmox is installed
- [ ] Extract the product key: `(Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey`
- [ ] Verify the refurb matches the listing — 32GB as **2×16GB dual channel**, NVMe capacity, CPU model
- [ ] Note the Service Tag: `wmic bios get serialnumber` (or the sticker) for warranty lookups

> Note: the OEM key is hardware-bound to this Dell. It reactivates on a Windows reinstall *here*, but will **not** activate in a VM — budget a separate license if the Phase 3 Windows VM needs one.

## 4. Wipe Windows, install Proxmox VE

- [ ] Boot the Dell from the USB stick (F12 for the one-time boot menu; F2 for BIOS setup if boot order needs changing)
- [ ] Run the Proxmox installer, wipe the NVMe drive
- [ ] Set a strong root password during install
- [ ] Configure static IP for Proxmox on your home LAN (write it down — this is how you'll reach the web UI headless from now on)
- [ ] Complete install, reboot, remove USB stick

## 5. First login and initial config

- [ ] From another device on the network, browse to `https://<proxmox-ip>:8006`
- [ ] Log in as root
- [ ] Remove the "no valid subscription" popup annoyance (switch to the no-subscription repo) — optional but common
- [ ] Run `apt update && apt full-upgrade` on the Proxmox host itself
- [ ] Disconnect the temporary display/keyboard — go fully headless from here on

## 6. Create the Debian VM

- [ ] Download a Debian netinst ISO, upload it to Proxmox (Datacenter → local storage → ISO Images → Upload)
- [ ] Create a new VM: allocate a sensible slice of the 32GB RAM / 512GB NVMe (leave headroom for later phases — see the roadmap's Phase 3 note about RAM)
- [ ] Install Debian inside the VM (minimal install, no desktop environment needed)
- [ ] Set a static IP (or a DHCP reservation, once you have a real DHCP server in Phase 1 — for now, static is simplest)
- [ ] Enable SSH server during install (or `apt install openssh-server` after)
- [ ] Set up SSH key-based login from your desktop; disable password auth once key login works

## 7. Harden the Debian VM (baseline, more comes in Phase 2)

- [ ] `apt update && apt full-upgrade`
- [ ] Enable unattended-upgrades for security patches
- [ ] Set up a basic firewall on the VM itself (`ufw` — allow SSH, HTTP/HTTPS only)
- [ ] Create a non-root user with sudo, confirm you can log in as it before locking down root SSH login

## 8. Install Docker

- [ ] Install Docker Engine + Docker Compose plugin (official Docker install script/repo, not the Debian-packaged version — usually more current)
- [ ] Add your non-root user to the `docker` group
- [ ] Verify with `docker run hello-world`

## 9. Containerize the portfolio site

- [ ] Write a `Dockerfile` for the Flask app (base image, install deps, copy app code)
- [ ] Configure Gunicorn as the WSGI server (don't run Flask's dev server in production)
- [ ] Write a `docker-compose.yml` for the app container
- [ ] Build and run locally on the VM, confirm the site responds on its internal port (e.g. `curl localhost:8000`)

## 10. Register the domain

- [ ] Register your domain (`yourname.dev` or similar)
- [ ] Create a free Cloudflare account
- [ ] Add the domain to Cloudflare, update nameservers at the registrar to Cloudflare's

## 11. Set up the Cloudflare Tunnel

- [ ] Install `cloudflared` (as a container alongside the app, per the roadmap — add it to the same `docker-compose.yml`)
- [ ] Authenticate `cloudflared` to your Cloudflare account, create a named tunnel
- [ ] Add a config mapping the tunnel to the app container's internal address/port
- [ ] Create the DNS record in Cloudflare (CNAME to the tunnel) — this is what makes port forwarding unnecessary
- [ ] Start the tunnel container, confirm it shows "connected" in the Cloudflare dashboard

## 12. Verify

- [ ] Browse to your domain from an external network (phone on cellular data, not home Wi-Fi) — confirms it's not just working locally
- [ ] Confirm HTTPS is active (padlock, valid cert — Cloudflare handles this automatically)
- [ ] Confirm no ports are forwarded on the XB6 (check the router's port forwarding page — should be empty for this)

## 13. UPS graceful shutdown (do this before you actually need it)

- [ ] Connect UPS to the Dell via USB
- [ ] Install NUT (Network UPS Tools) on Proxmox or the Debian VM
- [ ] Configure NUT to trigger a graceful shutdown of the Dell on prolonged power loss
- [ ] Test by unplugging the UPS from the wall (on battery) and confirming NUT detects it

---

## Milestone

Portfolio live at your domain, served from a container, on a hypervisor you'll build every later phase on top of.

**Next:** Phase 1 — Network foundation (Network+): the MikroTik CRS326 running RouterOS as switch, router, and firewall in one, with VLANs 10/20/30/40 behind it. The website you just stood up moves onto that network once it exists.
