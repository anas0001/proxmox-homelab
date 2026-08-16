# AGENTS.md — Context for Claude Code

> This file is the single source of truth for any AI/dev agent working in this repo.
> Read it fully before acting. It defines **what we are building, the hard constraints,
> the standards, and the safety rules.** When in doubt, prefer the safest, most
> idempotent, most-documented option — this repo is public.

---

## 1. What this project is

An **Infrastructure-as-Code homelab**: a single Proxmox VE server, fully configured and
hardened by Ansible, that provisions the lab VMs used to study/practice Linux, Networking &
Storage, and HPC. The goal is **maximum automation** — a clean Proxmox host should become a
secured hypervisor running reproducible lab VMs with a few `make` targets, and the whole
thing should be destroyable and rebuildable from this repo.

**Secondary goal (equally important):** the repository is a maintained artifact in its own
right — clean code, real documentation, a changelog, sensible git history, CI, and zero secrets
or topology leaks. A homelab that only its author can rebuild has failed at its main job.

### Definition of done (every change)
- **Idempotent**: a second `make site` run reports `changed=0`.
- **Linted**: `make lint` (yamllint + ansible-lint `production` profile) passes.
- **No secrets**: `make secrets-scan` (gitleaks) passes; nothing sensitive committed.
- **Documented**: user-facing behaviour is in `README.md`/`docs/`; `CHANGELOG.md` updated.
- **Reviewed**: committed on a feature branch, merged via PR (see section 8).

---

## 2. The hardware (the Proxmox host)

Verified against the running host, not assumed.

| Item | Value | Implication for you |
|------|-------|---------------------|
| CPU | **Xeon E5-2690** (Sandy Bridge-EP), 1 socket, 8C/16T | VT-x + EPT present, so nested virtualisation works. Single socket, so no NUMA pinning concerns. |
| RAM | **62 GB** usable | Generous. RAM is **not** the binding constraint; you can run many small VMs. |
| Disk | **223.6 GB (single disk)** → **130.27 GB LVM-thin pool** | **This is the binding constraint.** Plan storage carefully (section 3). |
| Hypervisor | **Proxmox VE 9.2.10** on Debian 13 "Trixie" | Type-1 (KVM+LXC). Default storage: `local` (dir) + `local-lvm` (LVM-thin). APT uses **deb822 `.sources`**, not `.list`. |
| NICs | `enp0s25` (uplink on `vmbr0`), **`enp7s0` unused/down** | The spare NIC is available for a real second uplink in the Phase 2 networking labs. |

### Hard constraints that shape every decision
1. **Single 223.6 GB disk -> use LVM-thin (`local-lvm`), NOT ZFS on the host.** ZFS needs
   redundant disks and hungry ARC RAM; it is wrong here. Practice ZFS *inside a VM* with
   virtual disks instead (that is how the lab workbooks already teach it). Do **not** try to
   convert the host to ZFS.
2. **Thin provisioning is mandatory.** Over-provision virtual disks but only actual usage
   consumes space. **A full thin pool corrupts data** — so treat pool usage as a first-class
   metric: alert/stop well before 80%. Never let `local-lvm` fill.
3. **Do not power on every VM at once.** RAM is fine but disk churn and thin-pool growth are
   not. Define all VMs; start only the lab you are using. Snapshots also consume pool space.
4. **Old CPU:** nested virtualization works but is slow. Containers-in-VM (the common case)
   need no nesting. Enable nested KVM anyway for the occasional VM-in-VM lab.

---

## 3. Storage & sizing plan (respect the 130 GB thin pool)

Actual on-disk layout (`lsblk`, `vgs`, `lvs`):

| Volume | Size | Notes |
|--------|------|-------|
| `pve-swap` | 8.00 GB | |
| `pve-root` | 65.64 GB | Debian install + `local` storage (`/var/lib/vz`). ~8 GB used. |
| `pve-data` | **130.27 GB** | **The thin pool. All VM disks live here.** |
| unallocated | 16.00 GB | Available to extend the pool (see runbook). |

With thin provisioning, real usage per freshly-installed VM is ~3–8 GB. The full lab inventory
in section 4 *provisions* ~300 GB into this pool — a deliberate 2.3x over-commit — but realistic
consumption lands at ~90–110 GB once Ceph OSDs and `clean` snapshots are counted. That is close
enough to the 80% gate that the pool should be extended and lab sets run one at a time.

- Store ISOs and the golden cloud images on `local`.
- All VM disks on `local-lvm` (thin).
- **Snapshots policy:** keep a single `clean` snapshot per lab VM for the break-and-fix labs;
  delete stale snapshots (they grow with divergence).
- Add a monitoring guard (role `pve_base`): a check/alert if `local-lvm` data% > 80.
- If the user later adds a disk, introduce a second thin pool or a ZFS pool — but **only when
  there is redundancy**. Until then, single-disk assumptions hold.

---

## 4. Architecture & VM inventory (what to provision)

Ansible runs **from the user's workstation** (or a tiny control LXC), targeting:
- the **Proxmox host** over SSH + the **Proxmox API** (token auth) for VM lifecycle, and
- the **guest VMs** over SSH for in-guest configuration.

Provisioning flow: build a **cloud-init golden template** once -> `community.proxmox.proxmox_kvm`
**clones** it per VM -> cloud-init sets hostname/user/SSH-key/network -> Ansible connects and
configures the guest -> snapshot `clean`.

### Golden templates (role `vm_template`)
- `tmpl-rocky9` — Rocky Linux 9 cloud image + cloud-init (primary; RHCSA/HPC labs).
- `tmpl-ubuntu2404` — Ubuntu 24.04 (Containerlab/tooling labs). Optional, build on demand.

### Lab VM sets (defined in inventory; provisioned per phase, not all at once)
| Set | VMs | vCPU / RAM / disk (thin) | Purpose (workbook) |
|-----|-----|--------------------------|--------------------|
| linux | `node1`, `node2` | 2 / 2 GB / 20 GB (+2x5 GB spare disks) | Phase 1 Linux labs |
| net | `net1`, `net2` + Containerlab on `node1` | 1 / 1 GB / 15 GB | Phase 2 networking |
| storage | `ceph1..3` | 2 / 4 GB / 20 GB (+2x10 GB OSD disks) | Phase 2 Ceph/ZFS |
| hpc | `hpc-head`, `hpc-c1..c3` | 2 / 2 GB / 20 GB (+spare disk on compute) | Phase 3 cluster |

RAM check when running concurrently: any single set fits easily in 64 GB (largest ~ Ceph 3x4 GB
= 12 GB). Disk (thin pool) is the thing to watch, not RAM.

### Networking (role `pve_network`)
- `vmbr0` — management bridge to the home LAN (Proxmox web UI + host).
- `vmbr1` — **VLAN-aware** bridge, no uplink -> isolated lab L2 for the Phase 2 networking labs.
- A NAT'd lab network (e.g. `10.10.10.0/24`) so lab VMs reach the internet for package installs
  without being exposed. Keep the lab subnet off the management path where practical.
- **Do not** bridge lab VMs directly onto the home LAN by default.

---

## 5. Repository layout

```
.
├── AGENTS.md                # this file
├── README.md                # public overview + quickstart
├── CHANGELOG.md             # Keep a Changelog format
├── CONTRIBUTING.md          # git workflow, commit/branch conventions
├── LICENSE                  # MIT
├── Makefile                 # make deps/lint/check/site/...
├── ansible.cfg
├── requirements.yml         # Galaxy collections
├── .gitignore               # blocks secrets/real inventory (read it before adding files)
├── .yamllint / .ansible-lint / .pre-commit-config.yaml
├── .github/workflows/ci.yml # lint + gitleaks on PR
├── docs/
│   ├── README.md            # index; the numeric prefixes are the reading order
│   ├── 01-control-node.md   # workstation setup: venv, tooling, keys, vault, WSL2
│   ├── 02-architecture.md   # design + VM plan (hardware-aware)
│   ├── 03-network.md        # bridges, VLANs, subnets
│   ├── 04-security.md       # Proxmox hardening spec + secrets model
│   ├── 05-runbook.md        # first-run, day-2 ops, recovery
│   ├── 06-out-of-band.md    # register of host changes NOT applied by Ansible
│   └── tailscale-acl.hujson # tailnet policy (a policy file, not a document)
├── inventories/homelab/
│   ├── hosts.example.yml    # SANITISED example — copy to hosts.yml (gitignored)
│   ├── group_vars/
│   │   ├── all/main.yml            # non-secret defaults
│   │   ├── all/vault.example.yml   # template for secrets (copy to vault.yml, encrypt)
│   │   ├── pve/main.yml
│   │   └── guests/main.yml
│   └── host_vars/           # gitignored (real per-host data)
├── playbooks/
│   ├── site.yml             # orchestrates everything
│   ├── pve_bootstrap.yml
│   ├── pve_harden.yml
│   ├── provision_vms.yml
│   └── configure_guests.yml
└── roles/                   # you build these (scaffold with ansible-galaxy role init)
    ├── pve_base/            # repos, packages, chrony, thin-pool guard, no-subscription nag
    ├── pve_security/        # hardening (see docs/04-security.md)
    ├── pve_network/         # bridges + VLAN-aware + NAT lab net
    ├── vm_template/         # download cloud image, build cloud-init template
    ├── vm_provision/        # clone template -> VM, cloud-init, disks, snapshot 'clean'
    └── guest_base/          # baseline guest config (users, ssh, firewall, updates)
```

---

## 6. Ansible standards (non-negotiable)

- **FQCN everywhere**: `ansible.builtin.copy`, `community.general.proxmox_kvm`, etc.
- **Idempotent**: use modules, not `command`/`shell`, unless there is no module; when you must,
  add `changed_when`/`creates`/`args`. Never leave a task always-changed.
- **Roles** with `defaults/main.yml` (overridable) vs `vars/main.yml` (internal). Handlers for
  restarts. `meta/main.yml` with `galaxy_info` + dependencies. A short `README.md` per role.
- **Variables**: prefix role vars (`pve_security_ssh_port`); no magic numbers; document each in
  `defaults`. Booleans are `true`/`false`.
- **No secrets in plaintext, ever.** All credentials/tokens/keys come from **Ansible Vault**
  (`group_vars/**/vault.yml`, gitignored) and are referenced via non-secret aliases in
  `main.yml` (e.g. `pve_api_token: "{{ vault_pve_api_token }}"`). Add `no_log: true` to tasks
  that handle secrets.
- **Check-mode friendly**: support `--check` where feasible.
- **Tags** on plays/roles (`bootstrap`, `harden`, `network`, `provision`, `configure`) so runs
  can be scoped.
- **Least privilege**: connect to the Proxmox API with a **dedicated token**, not `root@pam`
  password (see docs/04-security.md). `become` only where needed.
- Prefer the **`community.general.proxmox_*`** modules for VM/template lifecycle over shelling
  out to `qm`/`pct`.

---

## 7. Security requirements

Full spec in `docs/04-security.md`. What the hardening MUST deliver:

- **SSH**: key-only (no password auth), no direct root login, a dedicated admin user with sudo,
  `AllowGroups`, modern ciphers/KEX, `MaxAuthTries`, fail2ban on sshd + `pveproxy`.
- **Proxmox access**: dedicated PVE user + realm, **API token with least-privilege role** (a
  custom role/pool, not Administrator), **TOTP 2FA** on the human admin account.
- **Firewall**: enable the Proxmox datacenter+host firewall, **default-deny inbound**, allow
  web UI `8006` and SSH `22` **only from the Tailscale interface (`tailscale0` / `100.64.0.0/10`)**
  (optionally the local mgmt subnet for console access). Never expose `8006`/`22` to the LAN-at-
  large or the internet.
- **Remote access**: via **Tailscale** (WireGuard-based mesh; already in use). No router port-
  forwarding. Harden the tailnet: **ACLs** limiting which devices/users reach the host and on
  which ports, **disable key expiry** on the server node, **2FA on the Tailscale admin account**,
  server joined with a **tagged, non-ephemeral auth key** (in Vault). See docs/04-security.md section 3.
- **Patching**: configure the `pve-no-subscription` repo correctly, remove the enterprise-repo
  error, document an update cadence (optionally enable unattended security updates).
- **TLS**: replace the default self-signed cert (ACME/Let's Encrypt if reachable, else an
  internal CA); document the choice.
- **Hardening extras**: `auditd` rules, `chrony` time sync, disable unused services, kernel
  `sysctl` hardening, restrict cron, sensible `limits`.
- **Backups**: document a vzdump/PBS target and a 3-2-1 intent (even if the target is added later).
- Everything above is **codified in Ansible** and **idempotent** — not click-ops.

---

## 8. Git workflow & repo hygiene

- **Branching**: `main` is protected/stable. Short-lived branches:
  `feat/pve-hardening`, `feat/vm-provisioning`, `docs/architecture`, `fix/thin-pool-guard`,
  `chore/ci`. One feature per branch.
- **Commits**: **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`,
  `ci:`, `test:`). Small, logical, buildable commits — not one giant dump. Commit at natural
  stages (scaffold -> each role -> docs -> CI).
- **PRs**: even solo, open a PR per branch with a short what/why; let CI (lint + gitleaks) pass
  before merge. Squash or rebase-merge to keep history clean.
- **Releases**: tag milestones (`v0.1.0` = hardened host provisioning VMs) and keep
  `CHANGELOG.md` in sync (Unreleased -> versioned on tag).
- **Suggested first-commits sequence:**
  1. `chore: scaffold repo, tooling, CI` (this scaffold)
  2. `docs: architecture, security, network`
  3. `feat: pve_base role`
  4. `feat: pve_security hardening`
  5. `feat: pve_network bridges + VLAN`
  6. `feat: vm_template (cloud-init golden image)`
  7. `feat: vm_provision (clone + cloud-init + snapshot)`
  8. `feat: guest_base baseline`
  9. `docs: runbook + README quickstart`, then tag `v0.1.0`.

---

## 9. PUBLIC-REPO SAFETY (read twice — do not skip)

This repo will be public. **Nothing that could expose or endanger the setup may be committed.**

**NEVER commit:**
- Vault passwords (`.vault_pass`), API tokens, passwords, SSH **private** keys, TLS **private**
  keys, PBS keys, or any credential — even "temporarily".
- The **real** inventory (`hosts.yml`), real `host_vars`, real public IPs, external hostnames,
  MAC addresses, serial numbers, or anything that reveals the actual topology or how to reach
  the host from outside.
- cloud-init `user-data` containing hashed passwords or keys.

**ALWAYS:**
- Provide **`*.example.yml`** templates with placeholders; the real files are gitignored.
- Put every secret in **Ansible Vault**; keep the vault password **outside** the repo.
- Use **RFC1918** ranges and placeholder domains (`homelab.local`, `10.10.10.0/24`,
  `admin@example.com`) in all committed examples.
- Run `make secrets-scan` before committing; CI runs gitleaks on every PR as a backstop.
- If a secret is ever committed by accident: **rotate it immediately**, then scrub history
  (`git filter-repo`/BFG) — rotation first, because public history may already be scraped.

> Rule of thumb: a stranger reading this repo should learn *how* it's built and be able to
> reproduce it on **their** hardware, while learning **nothing** that helps them attack **this**
> host.

---

## 10. How to work in this repo (agent playbook)

1. Read `docs/02-architecture.md`, `docs/04-security.md`, `docs/03-network.md` before writing tasks.
2. Never invent hosts/credentials. If you need the real Proxmox endpoint, token, or user, read
   them from the vaulted vars / **ask the user** — do not hardcode or guess.
3. Build one role at a time on its own branch; scaffold with `ansible-galaxy role init`.
4. Develop against `--check --diff` first; then a real run; then run again to prove idempotence.
5. Keep the thin-pool guard and safety checks in mind — destructive VM/disk actions must be
   guarded (`when:` conditions, `--limit`) and must never target the host's own disks.
6. Update `CHANGELOG.md` and the relevant doc with every functional change.
6a. **Any host change made outside Ansible must be recorded in `docs/06-out-of-band.md`
   before it is made**, with the verbatim command and how to verify it. The repository
   plus that file must be enough to rebuild the host. Prefer codifying to recording.
7. `make lint && make secrets-scan` must pass before you commit; open a PR.

If a requested action risks data loss (deleting VMs/disks, resizing the host pool, touching the
boot disk, opening the firewall to the internet), **stop and confirm with the user first.**
