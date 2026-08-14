# `pve_security`

Security hardening for the Proxmox VE host: SSH, firewall, fail2ban, auditd and sysctl.

Implements the target state in `docs/security.md`.

- **SSH**: key-only, no root login, `AllowGroups`, restricted auth attempts, modern ciphers.
- **Firewall**: Proxmox datacenter and host firewall with a default-deny inbound policy,
  permitting management access only from the Tailscale interface and the management LAN.
- **fail2ban** jails for `sshd` and `pveproxy`; **auditd** with a baseline ruleset.
- **sysctl** hardening appropriate to a hypervisor.

Ordering is safety-critical. The role proves the replacement access path works before removing
the existing one, validates `sshd` configuration before any reload, and installs firewall accept
rules before switching the default policy to drop.

## Tags

`harden`

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
