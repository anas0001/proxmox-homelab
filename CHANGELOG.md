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
- `pve_access` role: creates the least-privilege API identity used by every later
  API-driven role — a `labs` resource pool, two purpose-scoped custom roles
  (`AnsibleLabVM` on the pool, `AnsibleLabStorage` on the storages), a dedicated
  `ansible@pve` user, and an API token with privilege separation enabled. Bootstraps
  over SSH with `pveum` rather than the API modules, which breaks the circular
  dependency (the modules need the credential this role creates) and avoids storing
  the Proxmox root password anywhere.
- `docs/control-node.md`: complete control-node setup — virtualenv and tooling versions,
  dedicated SSH key, inventory and vault, the first run, and linting the repository with no
  host at all. Also covers running from WSL2 (Tailscale MagicDNS is not inherited) and how to
  tell bufferbloat from packet loss when the link to the host is slow. `README.md` previously
  listed the tooling as a bare prerequisite without saying how to install any of it.
- `scripts/topology-scan.sh`, wired into `make secrets-scan`: fails when tracked files
  contain a real tailnet address, a `.ts.net` name, a MAC address or a real email. gitleaks
  finds credentials but not topology, and `AGENTS.md` section 9 forbids both. The bare
  `100.64.0.0/10` range is allowed, being identical for every Tailscale user and naming no
  host.
- `scripts/host-state.sh`: strictly read-only snapshot of everything this project
  touches on the host — hardware, LVM-thin usage, APT sources, networking, guests,
  the access plane, the firewall and SSH exposure. Diff a before/after pair around
  any change to see exactly what moved.
- `docs/out-of-band.md`: register of every host change not applied by Ansible, so a
  rebuilt host can be restored from this repository plus that one file. Covers the
  pending thin-pool extension and the pre-existing manual Tailscale enrolment.
- `docs/tailscale-acl.hujson` starter tailnet policy (tagOwners + least-privilege ACL,
  no secrets) and a runbook section for creating the tagged Tailscale auth key.
- Runbook section on thin-pool capacity, documenting the pool extension as a deliberate
  manual operation rather than an automated one.
- `make vault-check` — verifies the vault password file exists and successfully decrypts
  the vault, with distinct messages for "missing" and "wrong password".
- `TAGS=` and `CHECK=` modifiers on the playbook targets, so scoped and dry runs stay
  inside `make` where the vault password is already exported.

### Changed
- `docs/` filenames now carry a numeric prefix (`01-control-node.md` ... `06-out-of-band.md`)
  giving an explicit reading order, with `docs/README.md` as an index. Earlier entries in this
  changelog refer to the pre-rename names, deliberately: they record what the files were called
  when those changes were made. `tailscale-acl.hujson` is left unnumbered, being a policy file
  rather than a document.
- Lab guests are now reachable from the workstation via a **Tailscale subnet router** on the
  host, rather than being confined to a host-only network. The control node deliberately does
  not run on the Proxmox host, because the labs need SSH, VNC and XRDP into the guests from the
  desk — which makes guest reachability a design requirement rather than a convenience.
  Documented in `docs/network.md`, with the procedure and its ACL prerequisite in
  `docs/out-of-band.md`.
- Hardware and storage documentation now reflects the installed host rather than an
  assumed specification: Xeon E5-2690 (8C/16T), 62 GB RAM, 223.6 GB disk, and a
  **130.27 GB** LVM-thin pool. The previous "~215 GB thin pool" figure was not achievable
  on this machine, so the VM sizing analysis was redone against real numbers.
- `requirements.yml` now depends on `community.proxmox` for all Proxmox modules. They were
  **removed** from `community.general` in 13.0.0, so tasks written against
  `community.general.proxmox_kvm` fail outright on current collections.
- `Makefile` targets prefer a local `.venv` when present and fall back to `PATH`, so the
  same targets work locally and in CI.
- `ansible.cfg` uses the native `result_format = yaml` on the default callback. The
  previous `stdout_callback = yaml` referred to `community.general.yaml`, removed in
  community.general 12.0.0, which made every playbook run abort before its first task.
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
- `docs/06-out-of-band.md` recorded the host's real tailnet address. Redacted; the address
  belongs in the gitignored inventory. Caught before publication by the scan now automated
  in `scripts/topology-scan.sh`.
- `ansible.cfg` no longer pins `vault_password_file`. The vault password lives in a gitignored
  file, so naming its path in committed configuration made the repository unusable to anyone
  without that file: `ansible-lint` and `--syntax-check` fail hard when the configured path is
  missing, even though linting never decrypts anything. This broke CI on the first push and
  would have broken `make lint` for anyone cloning the repo. The path now comes from
  `ANSIBLE_VAULT_PASSWORD_FILE`, which the `Makefile` exports automatically when `.vault_pass`
  is present.
- `ansible.cfg` previously set `vault_password_file` with a trailing comment on the value line.
  Ansible's INI parser does not strip these, so the configured path included the comment text
  and every playbook run failed to find the vault password file.
- `docs/tailscale-acl.hujson` carried a real email address in an example ACL rule; replaced with
  a placeholder, per the repository's own sanitisation rules.
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
