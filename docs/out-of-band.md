# Out-of-band changes register

Every change to the Proxmox host that is **not** applied by Ansible is recorded here, with the
exact command and enough context to reapply it. The goal is that a rebuilt host can be returned
to the current state from this repository alone: `make site` for everything codified, plus this
file for everything that is not.

**The default is Ansible.** An entry belongs here only when a change genuinely cannot be
codified — a chicken-and-egg bootstrap, a one-shot capacity decision, or a step that must
happen at a physical console. Anything else is a gap to close, not an entry to write.

## How to use this file

- Add an entry **before** running the command, not after.
- Record the command verbatim, including flags.
- State what it changes and how to verify the result.
- If a change later becomes codified in a role, move it to **Superseded** rather than deleting
  it, so the history of the host stays readable.

---

## Active entries

### 1. Thin-pool extension — *pending, not yet run*

**Why not Ansible.** Storage capacity is a one-time decision, not continuously-converged state.
An `ensure pool size == N` task would fight a later deliberate resize, and `lvextend` is
one-way: a thin pool cannot be shrunk. Ansible therefore *monitors* pool usage (the 80% guard in
`pve_base`) but never *manages* pool size.

```bash
# Extends the LVM-thin pool into the 16 GB of unallocated space in the volume
# group. Online, non-destructive, no VM disruption.
vgs                                     # confirm free extents exist
lvextend -l +100%FREE /dev/pve/data
lvs -o lv_name,lv_size,data_percent,metadata_percent
```

**Verify:** `lvs` shows `pve/data` at roughly 146 GB, up from 130.27 GB.

---

### 2. Tailscale enrolment — *already done manually, before this repository existed*

**Why not Ansible.** The host was joined to the tailnet interactively via SSO. Re-running
`tailscale up` re-authenticates and **drops the tunnel** — the same tunnel Ansible connects
over. Automating this would mean automating the severing of the control channel mid-run.

`pve_tailscale_enabled` is therefore `false` by default. See `docs/security.md` §3a.

```bash
# For reference only — how the host was enrolled. Do not run this while Tailscale
# is carrying your only connection to the host.
tailscale up
```

**Current state:** node `pve`, address `100.116.48.34`, joined under a user identity and
**untagged**. Tagging it (`--advertise-tags=tag:homelab`, per `docs/tailscale-acl.hujson`) is
outstanding hardening and must be done with console access available.

**Verify:** `tailscale status` lists the host; `tailscale ip -4` returns its tailnet address.

---

## Superseded

*(none yet)*

---

## Deliberately not applied

### `pve-root` shrink

Would reclaim ~33 GB for the thin pool by shrinking `pve-root` from 65.64 GB to 32 GB. Deferred:
ext4 cannot shrink while mounted, `/` cannot be unmounted on a running system, and `/boot` sits
on the same volume, so a failure means an unbootable host. The full procedure is in
`docs/runbook.md`. Revisit only when the labs actually need the space.

---

## Verifying the host against this repository

`scripts/host-state.sh` captures a strictly read-only snapshot of everything this project
touches — hardware, LVM-thin usage, APT sources, networking, guests, the access plane
(pools/roles/users/tokens/ACLs), the firewall, and SSH exposure.

```bash
./scripts/host-state.sh                       # print a snapshot

./scripts/host-state.sh > /tmp/before.txt     # capture, apply a change, compare
TAGS=access make bootstrap
./scripts/host-state.sh > /tmp/after.txt
diff -u /tmp/before.txt /tmp/after.txt        # exactly what moved
```

Keeping a `before`/`after` pair around any change is the cheapest way to confirm that a role did
what it claimed and nothing else — and it makes an unrecorded change obvious rather than
invisible.

### Expected state before any role has run

A host that has only been installed and joined to Tailscale should show:

| Section | Expected |
|---|---|
| Guests | `qm list` and `pct list` both empty |
| Access plane | pools `[]`, ACLs `[]`, users only `root@pam`, no custom roles, no tokens |
| Firewall | `cluster.fw` and `host.fw` absent (Proxmox firewall never enabled) |
| SSH | `permitrootlogin yes`, `passwordauthentication yes`, `maxauthtries 6` |
| Services | `chrony` active; `fail2ban` and `auditd` inactive |
| LVM | `pve/data` 130.27 GB at 0.00% used, 16 GB unallocated in the volume group |

Anything else means something has been applied. `pve_access` is the first role that changes the
access-plane row.

---

## Incidents

### 2026-08-15 — stray ACL probe

While determining the correct `pveum acl modify` syntax, the following was run against the host:

```bash
pveum acl modify /pool/nope --roles Administrator --users 'root@pam'
```

It exited successfully. It was reverted immediately with:

```bash
pveum acl delete /pool/nope --roles Administrator --users 'root@pam'
```

`pvesh get /access/acl` returned `[]` both before and after the delete, indicating Proxmox never
persisted an ACL against a non-existent pool path. **Net state change: none.** Recorded here
because an unrecorded write is worse than an unnecessary entry, and because a future reader
comparing host state to this repository deserves to know it happened.
