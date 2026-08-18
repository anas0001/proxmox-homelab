# `pve_network`

Network bridges and the isolated NAT lab network on a Proxmox VE host.

Creates `vmbr1`, a VLAN-aware bridge with no uplink, plus egress-only NAT and DHCP/DNS for the
`10.10.10.0/24` lab subnet that rides on it.

## The one rule this role is built around

**`vmbr0` — the management bridge — is never edited by this role, under any condition.** The
base `/etc/network/interfaces` already carries `source /etc/network/interfaces.d/*`, so every
change here lands in a new drop-in file (`/etc/network/interfaces.d/20-vmbr1-lab.conf`).
Applying it can only ever add `vmbr1`; there is no code path in this role capable of rewriting
`vmbr0`'s stanza — the very thing that could sever the Ansible connection mid-run.

That claim is checked, not just asserted: the role stats `/etc/network/interfaces` before and
after templating the drop-in and fails loudly if its checksum changed.

## What it does

- **`vmbr1`**: VLAN-aware (`bridge-vlan-aware yes`, `bridge-vids 2-4094`), `bridge-ports none`
  (no uplink — isolation comes from there being no physical port here, not from a firewall rule
  that could be misconfigured), applied via `ifreload -a` (ifupdown2) rather than a full
  networking restart.
- **NAT**: `iptables` MASQUERADE for `10.10.10.0/24` egress through `vmbr0`, checked with `-C`
  before adding so re-runs do not duplicate the rule, and persisted via an `if-up.d` hook rather
  than a separate persistence package.
- **DHCP/DNS**: `dnsmasq`, bound to `vmbr1` only via `bind-interfaces` + `interface=` — without
  both, dnsmasq listens on the wildcard address across every interface regardless of what
  `listen-address` says, which would make the host an unintended DHCP/DNS server on the LAN or
  the tailnet. Dropped into `/etc/dnsmasq.d/`, which the stock `dnsmasq.conf` includes once its
  `conf-dir` directive — commented out by default — is enabled.

## A note on `ifquery -c`

ifupdown2's `-c`/`--check` compares a file against **live running state**, not just its syntax —
confirmed interactively before writing any task, including against a deliberately correct config
that still reported `[fail]` because the interface wasn't up yet. That makes it a post-apply
verifier, not a pre-apply `validate:` gate, which is how it's used here: after `ifreload -a`
brings `vmbr1` up, `-c` then confirms the live bridge matches the file.

## Tags

`network`, plus `nat` and `dhcp` for scoping.

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
