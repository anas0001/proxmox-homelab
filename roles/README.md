# Roles — specifications

Build each role with `ansible-galaxy role init <name>` inside this directory, then implement to
the spec below. Every role: FQCN modules, idempotent, `defaults/main.yml` documented, handlers
for restarts, `meta/main.yml` with galaxy_info, a short `README.md`, `no_log: true` on secret
tasks, and tags. Develop with `--check --diff`, then prove idempotence (2nd run `changed=0`).

Build order (one branch + PR each): `pve_base` -> `pve_security` -> `pve_network` ->
`vm_template` -> `vm_provision` -> `guest_base`.

---

## pve_base   (branch: feat/pve-base)
Base host configuration.
- Configure APT repos: **remove enterprise repo**, enable `pve-no-subscription`; remove the
  no-subscription nag; `apt update` (handler-safe).
- Install base packages (vim, git, tmux, curl, jq, chrony, fail2ban prerequisites).
- **chrony** enabled + synced.
- **Thin-pool guard**: task that reads `local-lvm` Data% and **fails** (or warns per
  `pve_thin_pool_warn_percent`) above the threshold — protects against a full thin pool.
- Enable nested virtualization (kvm-intel `nested=1`) idempotently.
- Sysctl/limits baseline that is safe on a hypervisor.
Tags: `bootstrap`.

## pve_security   (branch: feat/pve-hardening)   — implements docs/04-security.md
- **SSH**: template `sshd_config.d/00-hardening.conf` (key-only, no root, AllowGroups, MaxAuthTries,
  modern crypto); ensure `ssh-users` group + admin membership. Handler: reload sshd (validate first).
- **fail2ban**: jails for `sshd` and `proxmox` (pveproxy).
- **Firewall**: enable datacenter + host firewall, default **inbound DROP**, allow `22`/`8006`
  from `pve_security_mgmt_cidr` (+ WG) only. Manage via `/etc/pve/firewall/` + node rules.
- **auditd**: install + baseline ruleset (watch /etc/pve, /etc/ssh, sudoers, passwd/shadow, exec).
- **sysctl hardening**: rp_filter, syncookies, no redirects/source-route, kptr_restrict, ASLR.
- **TLS**: hook for ACME (DNS-01) or internal-CA cert; document via var, do not hardcode secrets.
- Optional: **unattended security upgrades** (no auto-reboot).
- 2FA and the API token/role are created out-of-band (runbook) — role can assert they exist.
All secret handling uses Vault + `no_log: true`. Tags: `harden`.

## pve_network   (branch: feat/pve-network)
- Manage `/etc/network/interfaces` (or ifupdown2) idempotently: `vmbr0` (uplink, mgmt),
  `vmbr1` (bridge_vlan_aware yes, no uplink).
- Create the **NAT lab network** `lab_nat_subnet` (masquerade via the host, dnsmasq for
  DHCP/DNS on the NAT net optional).
- Never disrupt the management interface in a way that locks Ansible out — apply carefully,
  prefer `ifreload -a`, and guard the mgmt bridge.
Tags: `network`.

## vm_template   (branch: feat/vm-template)
- Download the cloud image from `vm_templates.<os>.image_url` to `pve_iso_storage` (idempotent;
  skip if present, checksum if available).
- Create a VM from it, import the disk, set cloud-init drive, agent, serial console, then
  `qm template` / `proxmox_kvm ... template: true`. Use the configured `vmid`/`name`.
- Result: a reusable golden template. Rebuild only when the base image updates.
Tags: `provision`, `template`.

## vm_provision   (branch: feat/vm-provisioning)
- For each VM defined in inventory/vars: **clone** the template
  (`community.general.proxmox_kvm clone: ... full: false` = linked for space, or `true` where
  isolation matters), set cores/memory/disk size, attach extra disks per lab, configure
  cloud-init (hostname, `guest_admin_user`, PUBLIC ssh key, IP on the lab net), place in the
  `labs` pool, start, wait for guest agent.
- Take a **`clean` snapshot** after first boot+config.
- **Guards**: operate only on lab VMIDs from inventory; never touch the host disks; support a
  safe `state: absent` teardown path behind an explicit flag.
Tags: `provision`.

## tailscale   (branch: feat/tailscale)   — OPTIONAL; skip if you manage Tailscale by hand
- Only needed for **unattended enrolment** (host rebuilds, or enrolling VMs / a subnet router).
  If the host is already joined manually, you can omit this role and the auth key entirely.
- Install Tailscale (official apt repo), enable the service.
- `tailscale up` **idempotently** with a tagged, non-ephemeral **auth key** from Vault
  (`no_log: true`); set `--advertise-tags`, optional `--advertise-routes` for the lab subnet.
- Do **not** enable Tailscale SSH by default (keep hardened OpenSSH as baseline).
- Assert the node is up and tagged; leave key-expiry/ACLs to the admin console + committed ACL
  policy (`docs/tailscale-acl.hujson`, no secrets).
Tags: `harden`, `network`.

## guest_base   (branch: feat/guest-base)
- Baseline every guest over SSH: create admin user (if not via cloud-init), key-only SSH,
  host firewall (firewalld/nftables) default-deny + allow SSH, `guest_base_packages`, chrony,
  timezone, unattended security updates.
- Keep it distro-aware (Rocky/Ubuntu) via `ansible_facts['os_family']`.
Tags: `configure`.
