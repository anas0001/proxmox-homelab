# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Repository scaffold: `ansible.cfg`, `requirements.yml`, `Makefile`, linting
  (`.yamllint`, `.ansible-lint`), `pre-commit` (gitleaks + hooks), GitHub Actions CI
  (lint + secret scan), `LICENSE` (MIT).
- Documentation: `AGENTS.md` (agent/dev context), `README.md`, and `docs/`
  (`architecture.md`, `security.md`, `network.md`, `runbook.md`).
- Sanitised example inventory and `vault.example.yml`; secret-safe `.gitignore`.
- Playbook skeletons (`site.yml`, `pve_bootstrap`, `pve_harden`, `provision_vms`,
  `configure_guests`).
- Role skeletons for `pve_base`, `pve_security`, `pve_network`, `vm_template`,
  `vm_provision` and `guest_base`, each with `galaxy_info` metadata and a README
  describing its responsibilities.
- `docs/tailscale-acl.hujson` starter tailnet policy (tagOwners + least-privilege ACL,
  no secrets) and a runbook section for creating the tagged Tailscale auth key.
- Runbook section on thin-pool capacity, documenting the pool extension as a deliberate
  manual operation rather than an automated one.

### Changed
- Hardware and storage documentation now reflects the installed host rather than an
  assumed specification: Xeon E5-2690 (8C/16T), 62 GB RAM, 223.6 GB disk, and a
  **130.27 GB** LVM-thin pool. The previous "~215 GB thin pool" figure was not achievable
  on this machine, so the VM sizing analysis was redone against real numbers.
- `requirements.yml` now depends on `community.proxmox` for all Proxmox modules. They were
  **removed** from `community.general` in 13.0.0, so tasks written against
  `community.general.proxmox_kvm` fail outright on current collections.
- `Makefile` targets prefer a local `.venv` when present and fall back to `PATH`, so the
  same targets work locally and in CI.
- `pre-commit` hook revisions updated to current releases (gitleaks 8.30.0,
  pre-commit-hooks 6.0.0, yamllint 1.38.0, ansible-lint 26.8.0).
- Clarified that Tailscale is already deployed manually: the `tailscale-acl.hujson` policy and
  `vault_tailscale_auth_key` are **optional** (hardening / unattended-enrolment only), not
  connection requirements. Default `pve_tailscale_enabled: false`. Documented how Ansible reaches
  guest VMs (control node on the lab net, or a Tailscale subnet router + ACL).
- Remote access model switched from self-hosted WireGuard to **Tailscale** (WireGuard-based
  mesh, already deployed): host firewall now allows `22`/`8006` from `tailscale0` /
  `100.64.0.0/10` instead of a VPN subnet. Added tailnet hardening (ACLs, tagged non-ephemeral
  auth key in Vault, disabled key expiry, admin 2FA) and an optional `tailscale` role spec.

### Fixed
- `ansible.cfg` set `vault_password_file` with a trailing comment on the value line. Ansible's
  INI parser does not strip these, so the configured path included the comment text and every
  playbook run failed to find the vault password file.
- Lint violations that would have failed CI on the first push: unnamed plays in `site.yml`,
  YAML spacing in `hosts.example.yml`, and a `.yamllint` setting incompatible with
  `ansible-lint`.

### Planned
- Implementation of the six roles, then first release `v0.1.0`: a hardened host provisioning
  lab VMs from a cloud-init template.

<!--
Template for released versions:
## [0.1.0] - 2026-01-01
### Added / Changed / Fixed / Security
-->
