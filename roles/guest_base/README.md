# `guest_base`

Baseline configuration applied to every lab guest over SSH.

Runs against a guest `vm_provision` has already created, addressed and booted. Installs the base
package set, pins time and timezone, hardens SSH, brings up a default-deny host firewall, and
enables unattended **security** updates.

Distribution-aware via `ansible_facts['os_family']`, with names split into `vars/RedHat.yml` and
`vars/Debian.yml` — `sshd` vs `ssh` and `chronyd` vs `chrony` are the usual way a role like this
silently works on one family and breaks on the other.

## These guests have no console fallback

This shapes the whole role. `vm_provision` injects an SSH key via cloud-init, and the image
leaves both `svc_admin` and `root` with **locked passwords** — verified, not assumed:

```
svc_admin  LK  (Password locked.)
root       LK  (Password locked.)
```

So a Proxmox console session cannot log in. If this role breaks SSH or the firewall, the guest is
unreachable, and the only recovery is rolling back to the `clean` snapshot `vm_provision` took.

Everything risky is therefore ordered and validated accordingly:

- The **firewall runs last**, after everything that would be annoying to redo.
- The sshd drop-in is validated with `sshd -t -f %s` **before it is ever written**.
- The handler **reloads** rather than restarts, so established sessions — including Ansible's own
  — survive.
- Handlers are **flushed immediately** rather than left to end-of-play, so a later failure cannot
  leave a hardening file on disk that the running daemon never read. That exact silent no-op cost
  this project hours on the host (`docs/06-out-of-band.md`, 2026-08-20).
- Both the SSH and firewall steps **assert the resulting live state**, because "the play said
  changed=true" is not the same claim as "SSH still works".

## Firewall ordering is the point

```
1. install firewalld — but do NOT start it
2. write the SSH allow into the PERMANENT config, daemon still stopped (offline: true)
3. only then start and enable it
```

Starting first and allowing SSH second happens to work, because RHEL's default `public` zone
already includes the `ssh` service. "Happens to" is doing far too much work in a sentence about
whether the box stays reachable. Doing it in this order means the rule is on disk before anything
enforces anything, regardless of what the shipped default zone contains.

`offline: true` is what makes step 2 possible — it writes permanent config directly instead of
through the running daemon's D-Bus interface. Without it the task fails on a first run with
"Firewalld daemon must be running", which is precisely the run where the SSH rule matters most.

firewalld on **both** families rather than firewalld-on-Rocky and ufw-on-Ubuntu: one abstraction,
one set of tasks, one thing to debug. Ubuntu packages firewalld perfectly well.

## SSH drop-in ordering

Written to `/etc/ssh/sshd_config.d/10-guest-hardening.conf`. sshd takes the **first** value it
sees for a keyword, so a lower-numbered drop-in wins. Verified on the real image rather than
assumed: the only drop-ins present are `50-cloud-init.conf` and `50-redhat.conf`, and
`sshd_config`'s `Include` sits at line 15 — above the main file's own keywords. So `10-` genuinely
wins over all of it.

The one thing this actually changes on a stock Rocky cloud image is `PermitRootLogin`, which ships
as `without-password` (key-based root login permitted). `svc_admin` has passwordless sudo, so
nothing needs it.

## Security updates only, and no automatic reboots

`upgrade_type=security`, not full unattended upgrades. A lab exists to be a known quantity, and a
kernel or Ceph version changing under you between two runs of the same experiment makes results
unreproducible.

`reboot=never`, set explicitly rather than left to the package default. A guest rebooting
mid-experiment is worse than one waiting for a manual reboot to pick up a kernel patch — and
every guest can be rolled back to `clean` at any time anyway.

`dnf-automatic.conf` is edited key-by-key with `ini_file` rather than templated wholesale, so a
future package version adding settings does not get silently discarded.

## Running it

Guests are provisioned per phase (`vm_provision_build`), so the whole `guests` group includes VMs
that do not exist yet and will report UNREACHABLE. Scope with `LIMIT`:

```bash
LIMIT=linux_lab make configure          # the guests that exist today
LIMIT=node1 make configure              # one guest
CHECK=1 LIMIT=linux_lab make configure  # dry run
```

## What is not verified

The Debian/Ubuntu path is **written but never exercised against a real guest** — no Ubuntu
template exists yet (`vm_template_images` carries `rocky9` only; `ubuntu2404` is commented out as
build-on-demand). The names in `vars/Debian.yml` come from the packages' own documentation, not
from a live run. Treat it as unverified until an Ubuntu guest exists.

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.

## Tags

`configure`, plus `packages`, `time`, `ssh`, `firewall`, `updates` for scoping.

Scoping needs **both** halves, and missing either one fails in a different, confusing way:

- a tag on the `include_tasks` statement, or `--tags ssh` never selects the include at all and the
  run does nothing while reporting success;
- a tag on a `block` wrapping the tasks *inside* each file, because tags on a dynamic include do
  not propagate to the tasks it pulls in.

A tag-scoped run also skips Ansible's implicit fact gathering, since that step inherits the
**play's** tags (`configure`) rather than the role's. `tasks/main.yml` therefore gathers facts
itself when they are absent — without it, `--tags time` dies on `object of type 'dict' has no
attribute 'os_family'`.
