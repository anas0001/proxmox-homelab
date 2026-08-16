# Security hardening spec (Proxmox host)

This is the target state the `pve_security` role must reach, written to a senior
cyber-security bar. Everything here is **codified in Ansible and idempotent** — no click-ops.
Threat model: an internet-adjacent home network; assume the LAN is semi-trusted and the host
must not be reachable or attackable from outside, and must limit blast radius internally.

## 1. Identity & access
- **Dedicated admin user** (e.g. `svc_admin`) in a `wheel`/`sudo` group; **no daily use of
  `root`**. Root password set, stored in Vault, login disabled over SSH.
- **Proxmox realm/user**: a human admin in `pve` realm with **TOTP 2FA enforced** on the web UI.
- **API access for Ansible**: a dedicated PVE user + **API token** bound to a **custom role**
  with least privilege (VM lifecycle on a specific pool), **not** `Administrator`/`root@pam`.
  Token secret lives only in Vault. Example role grants: `VM.Allocate, VM.Clone, VM.Config.*,
  VM.PowerMgmt, VM.Snapshot, Datastore.AllocateSpace, SDN.Use` scoped to a `labs` pool.

## 2. SSH
- `PasswordAuthentication no`, `PermitRootLogin no`, `KbdInteractiveAuthentication no`.
- **Key-only**, ed25519; `AllowGroups ssh-users`.
- `MaxAuthTries 3`, `LoginGraceTime 20`, `X11Forwarding no`, `AllowAgentForwarding no`.
- Modern crypto only (curated `KexAlgorithms`/`Ciphers`/`MACs`).
- **fail2ban** jails for `sshd` and `proxmox` (pveproxy auth failures).

## 3. Network exposure & firewall
- Enable the **Proxmox firewall** at datacenter + host level; **default policy INBOUND DROP**.
- Allow only: SSH `22` and web UI `8006` **from the Tailscale interface (`tailscale0`) / the
  `100.64.0.0/10` CGNAT range** (optionally the local mgmt subnet for direct console). Cluster/
  Corosync N/A (single node). Everything else denied.
- **Never expose `8006` or `22` to the internet.** No port-forwards on the router to the host.
- **Remote admin via Tailscale** (WireGuard-based mesh), then reach `8006` privately over the
  tailnet. See section 3a for the tailnet hardening. (The Phase 2 VPN lab still teaches raw
  WireGuard/IPsec for the fundamentals; Tailscale is the operational choice here.)
- Lab VMs default to the **isolated `vmbr1`/NAT** networks, not the home LAN.

## 3a. Tailscale (remote-access overlay — hardening)
Tailscale is **already deployed** (the host was joined manually via SSO), and its default
policy is *allow-all* — which is why access already works. The items below are **hardening**
(least privilege), not connection requirements. **Automating** Tailscale in Ansible and the
**auth key** are **optional** — needed only for unattended (re)enrolment (host rebuilds) or to
enrol VMs / a subnet router. Harden the tailnet like any access plane:
- **Join with a tagged auth key**: `tailscale up --auth-key=... --advertise-tags=tag:homelab`
  using a **non-ephemeral, pre-authorized** key (stored in Vault, `no_log`). Tagged nodes are
  governed by ACLs, not by an individual user's login.
- **Disable key expiry** for the server node (admin console) so the hypervisor never silently
  drops off the tailnet; re-key on a schedule instead.
- **ACLs (least privilege)**: restrict which users/devices can reach `tag:homelab` and on which
  ports — e.g. only your admin device may reach `:22` and `:8006`; nothing else on the tailnet
  can. Keep the policy file in this repo (it contains no secrets) as `docs/tailscale-acl.hujson`.
- **2FA on the Tailscale admin account**; consider **tailnet lock** for high assurance.
- **Do not enable Tailscale SSH** as a replacement for hardened OpenSSH unless deliberate —
  keep key-only OpenSSH as the baseline; Tailscale is the transport, not the auth of record.
- **Subnet routing (optional)**: to reach lab VMs (`10.10.10.0/24`) over the tailnet, advertise
  the route from the host (`--advertise-routes=10.10.10.0/24`) and gate it with ACLs. Otherwise
  keep the lab networks unreachable from the tailnet.
- Automate install/enrolment in Ansible (`tailscale` task/role); the auth key is the only secret.

## 4. Patching & repositories
- Remove the **enterprise repo** entry that errors without a subscription; enable
  `pve-no-subscription` (and the matching Ceph no-subscription repo only if Ceph is used).
- Keep the host patched; document a cadence. Optionally enable **unattended-upgrades** for
  security updates with automatic-reboot windowed off (manual reboot for a hypervisor).

## 5. TLS
- Replace the **self-signed** UI cert:
  - if the host is reachable for ACME: **Let's Encrypt via Proxmox ACME** (DNS-01 preferred so
    nothing is exposed); else
  - an **internal CA**-issued cert trusted by your workstation.
- Document which path was chosen and how to renew.

## 6. Host hardening
- **chrony** time sync (clock skew breaks TLS/auth/logs).
- **auditd** with a baseline ruleset (watch `/etc/pve`, `/etc/ssh`, sudoers, passwd/shadow,
  privileged exec).
- **sysctl** hardening (rp_filter, `tcp_syncookies`, disable redirects/source-routing, restrict
  `kptr`/`dmesg`, enable ASLR).
- Disable/uninstall unused services; restrict `at`/`cron` to admins.
- Sensible `login.defs`/`limits`; umask; lock unused system accounts.
- Optional: CIS-style scan (`openscap`) run and report kept as evidence (not the raw report if
  it reveals specifics — summarise).

## 7. Backups & recovery
- Define a **vzdump** schedule for VM configs + a target (external disk/NFS/PBS). State a
  **3-2-1** intent even if the offsite copy is added later.
- Back up **`/etc/pve`, `/etc/network/interfaces`, firewall rules, and this repo** — the host is
  reproducible from repo + `/etc/pve`.
- Document the restore procedure in `05-runbook.md` and **test a restore** at least once.

## 8. Secrets model (how credentials flow, safely)
- All secrets live in **Ansible Vault**: `inventories/homelab/group_vars/**/vault.yml`
  (gitignored). Committed counterpart is `vault.example.yml` with placeholders.
- Non-secret code references secrets via aliases: `pve_api_token_secret:
  "{{ vault_pve_api_token_secret }}"`. Tasks touching secrets set `no_log: true`.
- Vault password is **never** in the repo (`.vault_pass` is gitignored; store it in your OS
  keychain/password manager).
- **Rotation:** if any secret is exposed, rotate first (Proxmox token, SSH keys, admin
  password), then scrub git history. Public history may already be scraped.

## 9. What must never reach the public repo
See `AGENTS.md` section 9. In short: no vault password, tokens, private keys, real inventory,
real IPs/hostnames/MACs, or cloud-init user-data with secrets. Examples use RFC1918 +
placeholder domains. `pre-commit` + CI `gitleaks` enforce this; treat them as a backstop, not a
substitute for care.
