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
- **Sensor and fan detection (read-only).** Reports every hardware monitoring driver and every
  fan/PWM channel the kernel exposes under `/sys/class/hwmon`. No fan control is configured —
  see below.
- **sysctl baseline.** File descriptors, ARP table sizing for many bridged guests, and reduced
  swappiness. Security-focused sysctl hardening belongs to `pve_security`; these are correctness
  and capacity settings only.
- **A Python venv for `community.proxmox`.** See below — needed by `vm_template`/`vm_provision`,
  not this role's own tasks, but built here since it is host baseline.

## The `community.proxmox` venv

Debian 13's `python3-proxmoxer` package is 2.2.0. Every `community.proxmox` module requires
2.3+ **unconditionally** — a check in the collection's shared base class that runs on every
module call, not gated behind any particular feature — confirmed live against the real host
(`Requires proxmoxer 2.3 or newer; found version 2.2.0`), not assumed from a changelog. No newer
candidate exists in Debian's own repositories at all.

The fix is a plain `python3 -m venv --system-site-packages` at a fixed path
(`pve_base_proxmoxer_venv`), with a compatible `proxmoxer` installed into it via
`ansible.builtin.pip`. **Not `pipx`**: tried first, and `pipx` manages CLI applications with
entry points — it refuses outright to keep a venv for a library with none of its own
(confirmed live: *"No apps associated with package proxmoxer... pipx should not be used"*).
`--system-site-packages` so the venv still sees system-installed libraries the Ansible modules
also need (`requests` etc.) rather than duplicating the whole Python environment for one
package.

`pve_base_proxmoxer_venv` is a `group_vars/all/main.yml` variable, not a role default in this
role, deliberately: `playbooks/provision_vms.yml` needs to read the same path to set
`ansible_python_interpreter`, and that play never invokes `pve_base` — a role's own defaults
only resolve for tasks running inside that role, confirmed directly (a play referencing a
role-default variable without the role present fails with `'<var>' is undefined`) rather than
assumed to "just work" globally.

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

## Sensors and fans: detection only, no control

`sensors-detect` is deliberately not run automatically. It probes hardware over I2C/SMBus with
writes, which on some boards can wedge a peripheral or a bus — an acceptable risk when you are
sitting at the console, not something to do unattended over SSH on a hypervisor. The kernel's
hwmon drivers auto-load regardless, so detection reads what is already exposed rather than
probing for it.

Fan data is read directly from `/sys/class/hwmon/*/fan*_input` and `pwm*`, not through
`fancontrol`. `fancontrol`'s own detection step, `pwmconfig`, is interactive-only by design — it
identifies which PWM output drives which fan by stopping each fan in turn, which is not something
to let automation do to a live host. On this hardware `hwmon0` is `dell_smm`, which already
exposes both fan speed and PWM control as a kernel driver; whether `fancontrol` adds anything on
top of that, or whether control is better implemented as a small role writing to the `dell_smm`
PWM files directly, is an open question for when fan control is actually built. Nothing in this
role writes to a `pwm*` file.

## What it deliberately does not do

**Remove the subscription nag dialog.** Every method patches a JavaScript file shipped by the
`pve-manager` package. That modifies a vendor-supplied file, which package updates overwrite, so
the change silently reverts and needs re-applying after every upgrade — and the regex matching it
is specific to the version it was written against. A permanently fragile, self-reverting patch on
a vendor file is a poor trade for removing one harmless dialog.

## Tags

`bootstrap`, plus `repos`, `packages`, `time`, `storage`, `guard`, `kvm`, `sensors`, `fans`,
`proxmoxer`, `sysctl` for scoping.

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
