# `guest_base`

Baseline configuration applied to every lab guest over SSH.

Configures each guest to a common baseline once it is reachable.

Admin user and key-only SSH, a default-deny host firewall permitting SSH, the base package set,
time sync, timezone, and unattended security updates.

Distribution-aware via `ansible_facts['os_family']`, since the lab runs both Rocky and Ubuntu
guests.

## Tags

`configure`

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
