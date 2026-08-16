# Documentation

The numeric prefix is the reading order. Documents **01–04** build understanding and are worth
reading through once; **05–06** are references you consult when you need them.

| # | Document | Answers |
|---|---|---|
| 01 | [Control node](01-control-node.md) | How do I get a working Ansible control node? Virtualenv and tooling versions, SSH keys, inventory and vault, the first run. Includes WSL2 notes and how to lint the repository with no host at all. |
| 02 | [Architecture](02-architecture.md) | What is being built, and why this shape? The control plane, the provisioning flow, the storage plan, and the VM inventory. |
| 03 | [Network](03-network.md) | How is it wired? Bridges, the VLAN-aware lab L2, the NAT lab subnet, and how lab guests are reached from a workstation. |
| 04 | [Security](04-security.md) | What does "hardened" mean here? The target state `pve_security` implements — identity, SSH, firewall, patching, TLS, backups — plus the secrets model. |
| 05 | [Runbook](05-runbook.md) | How do I operate it? First run, day-2 tasks, storage capacity, and recovery. |
| 06 | [Out-of-band register](06-out-of-band.md) | What changed on the host that Ansible did **not** do? Every such change, with the verbatim command and how to verify it. |

`tailscale-acl.hujson` is deliberately unnumbered. It is not a document but a policy file you
paste into the Tailscale admin console.

## Where to start

**Building it.** Read 01, run the setup, then 02 for context before your first `make bootstrap`.

**Reviewing the code.** Start at 02 for the design, then 04 for the security posture. Neither
requires a Proxmox host, and 01 explains how to lint the repository without one.

**Operating it.** 05 is the day-to-day reference. Check 06 before assuming the host matches
this repository — it records everything applied outside Ansible.

## Related, outside `docs/`

- [`../README.md`](../README.md) — project overview and quickstart
- [`../AGENTS.md`](../AGENTS.md) — the specification: constraints, standards, safety rules
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — branch, commit and PR conventions
- [`../roles/README.md`](../roles/README.md) — what each role is responsible for
- [`../scripts/host-state.sh`](../scripts/host-state.sh) — read-only host snapshot for
  before/after diffing
