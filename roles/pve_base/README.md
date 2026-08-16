# `pve_base`

Base Proxmox VE host configuration: APT repositories, packages, time sync, LVM-thin pool guard and nested virtualisation.

Brings a fresh Proxmox VE host to a known baseline.

- Converges the deb822 APT sources: enterprise repositories disabled, `pve-no-subscription`
  enabled, and the subscription nag removed.
- Installs the base package set and enables `chrony` for time sync.
- **Guards the LVM-thin pool.** Fails the run when `local-lvm` data usage exceeds
  `pve_thin_pool_warn_percent`. A thin pool that reaches 100% corrupts guest filesystems, so
  this is a hard gate rather than a warning.
- Enables nested virtualisation (`kvm_intel nested=1`).

This role monitors pool *usage*; it deliberately does not manage pool *size*. Capacity is a
one-time decision documented in `docs/05-runbook.md`, not continuously-converged state.

## Tags

`bootstrap`

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
