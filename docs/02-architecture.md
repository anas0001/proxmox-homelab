# Architecture

## Overview

A single **Proxmox VE** host, configured and hardened entirely by Ansible, that hosts
reproducible lab VMs. Everything is Infrastructure-as-Code: a bare Proxmox install becomes a
secured hypervisor running the labs with `make site`, and can be rebuilt from this repo.

```
                +-----------------------------------------------------------+
                |                    Proxmox VE 9.2 host                    |
                |  (Xeon E5-2690 8C/16T, 62 GB RAM, 223 GB disk)            |
                |                                                           |
   Workstation  |   local  (dir: ISOs, images)   local-lvm (LVM-thin: VMs) |
  (Ansible +    |                                                           |
   Tailscale)   |   vmbr0 --- home LAN (mgmt, web UI 8006, SSH)             |
       |        |   vmbr1 --- VLAN-aware, no uplink (isolated lab L2)       |
       |  SSH   |   NAT   --- 10.10.10.0/24 lab net (internet egress only)  |
       +------->|                                                           |
       |  API   |   [tmpl-rocky9]  [tmpl-ubuntu2404]   (cloud-init golden)  |
       +------->|      |  clone                                            |
                |      v                                                    |
                |   node1 node2 | ceph1-3 | hpc-head hpc-c1-3 | net1 net2   |
                +-----------------------------------------------------------+
```

## Control plane

Ansible runs from the **user's workstation** (or a small control LXC on the host). It reaches:
- the **Proxmox host** via SSH (guest-agnostic host config) and the **Proxmox API** (token) for
  VM/template lifecycle;
- each **guest VM** via SSH (cloud-init injects the admin SSH key) for in-guest configuration.

Because the guest VMs sit on the internal lab network (`10.10.10.0/24`, not the tailnet), the
control node must be able to reach that network. Choose one:
- **Run Ansible from a control node on the lab network** (a small LXC on the host, or the host
  itself) — simplest; Tailscale is not involved in reaching the VMs.
- **Advertise the lab subnet via a Tailscale subnet router** on the host
  (`--advertise-routes=10.10.10.0/24`) and add a scoped ACL rule — then your workstation reaches
  VMs over the tailnet. Only this option needs the Tailscale ACL/auth-key machinery.

## Provisioning flow

1. `vm_template` downloads the Rocky 9 cloud image and builds a cloud-init **golden template**.
2. `vm_provision` **clones** the template per VM (`community.general.proxmox_kvm`), attaches
   extra disks where the lab needs them, sets cloud-init (hostname, user, SSH key, network),
   boots, waits for the guest agent, then takes a `clean` snapshot.
3. `guest_base` configures the guest baseline (users, SSH, firewall, updates, chrony).
4. Phase-specific configuration is layered on top per lab set.

## Storage plan (223 GB single disk — the binding constraint)

Actual layout, as installed:

| Volume | Size | Notes |
|--------|------|-------|
| `pve-swap` | 8.00 GB | |
| `pve-root` | 65.64 GB | Debian + `local` storage (`/var/lib/vz`) for ISOs and cloud images |
| **`pve-data`** | **130.27 GB** | **the LVM-thin pool — all VM disks** |
| unallocated | 16.00 GB | reserve; extend the pool into it when needed (`docs/05-runbook.md`) |

The VM inventory below *provisions* roughly 300 GB into a 130 GB pool. That 2.3x over-commit is
the point of thin provisioning, not a mistake — but realistic consumption is what matters:
~13 VMs at ~4 GB actually written, two golden templates, Ceph OSDs (which genuinely write, at
3x replication), and one `clean` snapshot per VM that grows as the VM diverges. That totals
~90–110 GB, uncomfortably close to the 80% gate at 104 GB. Hence the two rules below.

Rules:
- **Thin-provision everything**; only real usage counts. A **full thin pool corrupts data** —
  `pve_base` installs a guard that fails/alerts when `local-lvm` Data% > 80.
- Keep **one `clean` snapshot** per lab VM; prune stale snapshots (they grow with divergence).
- Do **not** run all VM sets at once. RAM (64 GB) is ample; disk churn is the risk.
- **No ZFS on the host** (single disk, no redundancy). Practice ZFS *inside* the storage lab VMs.

## VM inventory

| Set | VMs | vCPU | RAM | Disk (thin) | Extra disks | Phase |
|-----|-----|------|-----|-------------|-------------|-------|
| linux | node1, node2 | 2 | 2 GB | 20 GB | 2x5 GB | 1 — Linux |
| net | net1, net2 (+Containerlab on node1) | 1 | 1 GB | 15 GB | – | 2 — Networking |
| storage | ceph1, ceph2, ceph3 | 2 | 4 GB | 20 GB | 2x10 GB (OSD) | 2 — Ceph/ZFS |
| hpc | hpc-head, hpc-c1, hpc-c2, hpc-c3 | 2 | 2 GB | 20 GB | 1x10 GB on head (parallel FS) | 3 — HPC |

Concurrency: provision all, **power on per lab**. Largest concurrent set ~ Ceph (3x4 GB = 12 GB).

## Networking

See `03-network.md`. Summary: `vmbr0` = management/LAN; `vmbr1` = VLAN-aware isolated lab L2;
a NAT network `10.10.10.0/24` gives lab VMs internet egress without inbound exposure.

## Rebuild / teardown

- Rebuild: `make site` against a fresh Proxmox install reproduces the whole environment.
- Teardown of labs: a guarded `provision_vms.yml` run with state=absent removes lab VMs (never
  the host). Host stays intact.
