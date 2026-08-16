# Network design

## Bridges on the Proxmox host
| Bridge | Uplink | Purpose | Notes |
|--------|--------|---------|-------|
| `vmbr0` | physical NIC | Management + host + default VM access to home LAN | Web UI 8006 & SSH live here, firewalled to mgmt subnet/VPN |
| `vmbr1` | none (internal) | **VLAN-aware** isolated lab L2 | For Phase 2 switching/VLAN/routing labs; no route to LAN by default |
| NAT net | via host | `10.10.10.0/24` lab egress | Lab VMs get internet for packages; no inbound from LAN/WAN |

## Address plan (all RFC1918 / examples — set real values in the gitignored inventory)
| Purpose | Range (example) |
|---------|-----------------|
| Home LAN / management | `192.168.1.0/24` (your real LAN) |
| Lab NAT network | `10.10.10.0/24` (gw `10.10.10.1` on the host) |
| Lab VLANs (on vmbr1) | `10.20.<vlan>.0/24` per VLAN as labs require |

## Principles
- **Segment the labs from the home LAN.** Lab VMs default to the NAT/VLAN networks. Only put a
  VM on `vmbr0`/LAN deliberately.
- **Management is privileged**: the Proxmox UI/SSH are reachable only from the management subnet
  or over Tailscale — never the internet.
- **Tailscale** provides remote access (WireGuard-based mesh, already deployed): the host joins
  the tailnet, and you reach `8006`/`22` privately over `tailscale0`. No router port-forward.
  Tailnet ACLs limit which devices/ports are reachable (see docs/security.md section 3a).
- cloud-init sets each VM's IP (static from inventory, or DHCP on the NAT net via dnsmasq on the
  host). Keep the mapping in the **gitignored** real inventory, not in examples.

## Reaching lab guests from the workstation

The control node runs on a workstation rather than on the host, because the labs need SSH, VNC
and XRDP into the guests from the desk. That makes guest reachability a design requirement, not
a convenience: an isolated lab network with no route out is unreachable for Ansible too.

The host therefore acts as a **Tailscale subnet router**, advertising the lab subnet onto the
tailnet. Lab guests become reachable from tailnet devices without a single port forward and
without any guest touching the home LAN.

This is deliberately preferred over the alternative of bridging lab guests onto `vmbr0`. The
networking and storage labs involve guests doing genuinely disruptive things — rogue DHCP,
spanning-tree experiments, deliberately corrupted storage — and none of that belongs on the same
layer 2 as real household devices.

An approved subnet route is reachable by **every** device on the tailnet unless an ACL narrows
it, so the tailnet policy is load-bearing here rather than decorative. See
`docs/security.md` section 3a, `docs/tailscale-acl.hujson`, and the procedure in
`docs/out-of-band.md`.

## Firewall intent (enforced by `pve_security`)
- Datacenter + host firewall enabled, **inbound default DROP**.
- Allow `22`/`8006` from the Tailscale interface (`tailscale0` / `100.64.0.0/10`) only (plus the
  local mgmt subnet if you want direct console access).
- Lab networks may reach the internet (egress) but not the management interface.
