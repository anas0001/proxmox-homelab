# `pve_network`

Network bridges and the isolated NAT lab network on a Proxmox VE host.

Defines the lab's layer-2 and layer-3 topology.

- `vmbr0` — management bridge carrying the host and web UI. Guarded: the role must never
  reconfigure this in a way that interrupts the Ansible connection.
- `vmbr1` — VLAN-aware bridge with no uplink, providing an isolated layer-2 domain for the
  networking labs.
- A NAT network giving lab guests outbound internet access for package installation without
  any inbound exposure.

## Tags

`network`

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
