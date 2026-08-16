# homelab — Proxmox VE, hardened and automated with Ansible

Infrastructure-as-Code for a single-node **Proxmox VE** homelab. A clean Proxmox install becomes
a **security-hardened hypervisor** running reproducible lab VMs (Linux, Networking & Storage,
HPC) with a few `make` targets — and can be torn down and rebuilt entirely from this repo.

> Built as a learning platform **and** a portfolio piece: real IaC, security hardening, docs,
> CI, and a clean git history. No secrets or real topology are committed (see
> [Security](#security)).

## Highlights
- **One-command bring-up**: `make site` bootstraps, hardens, networks, and provisions the lab.
- **Security-first**: key-only SSH, least-privilege Proxmox API token, 2FA, default-deny
  firewall, WireGuard-only management, fail2ban, auditd, TLS, patched repos.
- **Reproducible VMs** from a cloud-init golden template (clone -> configure -> `clean` snapshot).
- **Idempotent & linted**: ansible-lint (`production` profile), yamllint, gitleaks, CI on PRs.
- **Hardware-aware**: tuned for a 64 GB / 256 GB single-disk host (LVM-thin, thin-pool guard).

## Architecture (short)
Ansible runs from your workstation and targets the Proxmox host (SSH + API) and the guest VMs
(SSH). Storage is LVM-thin on a single disk; networking uses a management bridge, a VLAN-aware
isolated lab bridge, and a NAT lab network. Full detail in
[`docs/architecture.md`](docs/architecture.md).

## Requirements
- Proxmox VE installed on the host, reachable over SSH.
- A control node with Python 3.11+ and `git`. Full setup — virtualenv, tooling versions,
  SSH keys, inventory, vault, and WSL2 notes — is in
  [`docs/control-node.md`](docs/control-node.md).

The Proxmox API token is created **by** this repository (`pve_access`), not required before it.

## Quickstart
```bash
git clone <your-repo> && cd homelab
cp inventories/homelab/hosts.example.yml inventories/homelab/hosts.yml            # edit
cp inventories/homelab/group_vars/all/vault.example.yml \
   inventories/homelab/group_vars/all/vault.yml                                  # fill + encrypt
ansible-vault encrypt inventories/homelab/group_vars/all/vault.yml
make deps      # collections + pre-commit hooks
make check     # dry-run
make site      # bootstrap -> harden -> network -> provision -> configure
```
See [`docs/runbook.md`](docs/runbook.md) for the full first-run, token creation, and recovery.

## Repository layout
```
docs/            control-node setup, architecture, security, network, runbook,
                 out-of-band register
scripts/         read-only host state snapshot for before/after diffing
inventories/     sanitised example inventory + vault template (real files gitignored)
playbooks/       site.yml + staged playbooks
roles/           pve_base, pve_security, pve_network, vm_template, vm_provision, guest_base
```

## Make targets
`make help` lists them. Common: `deps`, `lint`, `check`, `ping`, `bootstrap`, `harden`,
`provision`, `configure`, `site`, `secrets-scan`.

## Security
Nothing sensitive is committed. Secrets live in **Ansible Vault**; the real inventory and host
data are **gitignored**; committed examples use RFC1918 ranges and placeholder domains.
`pre-commit` + CI **gitleaks** block accidental secret commits. Full model:
[`docs/security.md`](docs/security.md) and `AGENTS.md` section 9.

> This repo teaches **how** the lab is built and lets you reproduce it on **your** hardware,
> while exposing nothing that helps anyone attack the author's host.

## Status
Early stage — see [`CHANGELOG.md`](CHANGELOG.md). Roadmap: hardened host -> template ->
provisioning -> per-phase lab configuration.

## License
[MIT](LICENSE).
