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

## Firewall intent (enforced by `pve_security`)
- Datacenter + host firewall enabled, **inbound default DROP**.
- Allow `22`/`8006` from the Tailscale interface (`tailscale0` / `100.64.0.0/10`) only (plus the
  local mgmt subnet if you want direct console access).
- Lab networks may reach the internet (egress) but not the management interface.
