# `pve_base`

Base Proxmox VE host configuration: APT repositories, packages, time sync, LVM-thin pool guard
and nested virtualisation.

Brings a fresh Proxmox VE host to a known baseline. Runs before hardening, so every task must be
safe on a host still in its post-install state.

## What it does

- **APT repositories.** Disables the subscription-only repositories and ensures
  `pve-no-subscription` is present and enabled. PVE 9 runs on Debian 13 and uses **deb822
  `.sources` files**, not the older one-line `.list` format — guides written before PVE 9 edit
  files that no longer exist. deb822's `Enabled:` field lets a repository be disabled *in place*,
  which makes the desired state a value in a file rather than the absence of one, and absence is
  far harder to converge idempotently.
- **Packages.** A deliberately short list. A hypervisor's job is to run guests; every package on
  the host is attack surface no guest requires.
- **Time sync.** `chrony`, enabled and running. Clock skew breaks TLS validation, API token auth
  and log correlation — and it propagates, since guests take their initial clock from the host.
- **Thin-pool guard.** See below.
- **Nested virtualisation.** Configured via modprobe so lab guests can run their own VMs.
- **sysctl baseline.** File descriptors, ARP table sizing for many bridged guests, and reduced
  swappiness. Security-focused sysctl hardening belongs to `pve_security`; these are correctness
  and capacity settings only.

## The thin-pool guard

The most important task here, and a hard failure rather than a warning.

LVM-thin over-commits: the pool advertises more space than it has, and blocks are allocated only
when a guest writes. A pool that reaches 100% does not refuse writes politely — guests take I/O
errors and their filesystems corrupt. The guest's own filesystem still reports free space, so
nothing warns anyone, and it takes out **every** VM in the pool at once rather than only the one
that filled it.

Data and metadata exhaust independently and either is fatal. Metadata is the one people forget,
so it is checked separately, with its own message naming which limit was breached.

The guard runs in check mode too. A dry run that skips the safety check is backwards.

This role monitors pool *usage*; it deliberately does not manage pool *size*. Capacity is a
one-time decision documented in `docs/05-runbook.md`, not continuously-converged state, and
`lvextend` is one-way.

## What it deliberately does not do

**Remove the subscription nag dialog.** Every method patches a JavaScript file shipped by the
`pve-manager` package. That modifies a vendor-supplied file, which package updates overwrite, so
the change silently reverts and needs re-applying after every upgrade — and the regex matching it
is specific to the version it was written against. A permanently fragile, self-reverting patch on
a vendor file is a poor trade for removing one harmless dialog.

## Tags

`bootstrap`, plus `repos`, `packages`, `time`, `storage`, `guard`, `kvm`, `sysctl` for scoping.

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
