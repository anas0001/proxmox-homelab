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

`pve_tailscale_enabled` is therefore `false` by default. See `docs/04-security.md` §3a.

```bash
# For reference only — how the host was enrolled. Do not run this while Tailscale
# is carrying your only connection to the host.
tailscale up
```

**Current state:** the host is enrolled under a user identity and is **untagged**. Its tailnet
address is in the gitignored inventory, not here. Tagging it
(`--advertise-tags=tag:homelab`, per `docs/tailscale-acl.hujson`) is outstanding hardening and
must be done with console access available.

**Verify:** `tailscale status` lists the host; `tailscale ip -4` returns its tailnet address.

---

### 3. Tailscale subnet router for the lab network — *pending, not yet run*

**Why it is needed.** The control node runs on a workstation, not on the Proxmox host, because
the labs require SSH, VNC and XRDP access to the guests from the desk. Lab guests sit on an
isolated network that is reachable only from the host, so without a route they are unreachable
from anywhere else — which makes both Ansible and interactive access impossible.

Advertising the lab subnet over the tailnet solves both at once, with no port forwards and no
guest exposed to the home LAN.

**Why not Ansible.** Same reason as entry 2: `tailscale up` re-authenticates and drops the
tunnel Ansible connects over.

```bash
# On the Proxmox host. Have console access available — this drops the tunnel.
tailscale up --advertise-routes=10.10.10.0/24
```

Then, in the Tailscale admin console, **approve the advertised route** (Machines -> the host ->
Route settings). Advertising alone does nothing until the route is approved.

**Gate it with ACLs before relying on it.** An approved subnet route is reachable by every device
on the tailnet unless a rule says otherwise. `docs/tailscale-acl.hujson` carries a commented
example scoping it to the admin workstation:

```
{ "action": "accept", "src": ["tag:admin-workstation"], "dst": ["10.10.10.0/24:*"] },
```

**Verify:** from a tailnet device other than the host,
`ping 10.10.10.11` reaches a provisioned lab guest; `tailscale status` on the host shows the
route as advertised and approved.

**Ordering:** only meaningful once `pve_network` has created the lab network and `vm_provision`
has placed a guest on it. Until then there is nothing at the far end of the route.

---

## Superseded

*(none yet)*

---

## Deliberately not applied

### `pve-root` shrink

Would reclaim ~33 GB for the thin pool by shrinking `pve-root` from 65.64 GB to 32 GB. Deferred:
ext4 cannot shrink while mounted, `/` cannot be unmounted on a running system, and `/boot` sits
on the same volume, so a failure means an unbootable host. The full procedure is in
`docs/05-runbook.md`. Revisit only when the labs actually need the space.

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

### 2026-08-18 — auditd rules test-loaded (`auditctl -R`) during pve_security recon

Before writing `pve_security`'s audit rules, an initial draft using the older `-w`/`-p` watch
syntax was loaded with `auditctl -R` to confirm it was accepted — it was, but with the warning
"Old style watch rules are slower". `audit.rules(7)` confirms `-w` is deprecated in favour of
syscall-rule form (`-F path=... -F perm=...`). The rules were rewritten in the modern form and
reloaded to confirm they load without the warning and expand to the expected syscall set
(`auditctl -l` after loading showed the full expanded `-S open,bind,truncate,...` list per
rule). `auditd` was installed for this test and purged afterward:

```bash
apt-get install -y auditd
auditctl -R /tmp/test-rules   # loaded and inspected twice, once per syntax form
auditctl -D                   # clear loaded rules
systemctl stop auditd
systemctl disable auditd
apt-get purge -y auditd
```

**Net state:** auditd not installed, no rules loaded — the same state as before recon. Confirmed
via `dpkg -l auditd` showing no `ii`/`rc` entry after the purge.

### 2026-08-18 — cluster firewall briefly enabled to confirm `pve-firewall status` output format

Before writing `pve_security`'s assertion that the firewall came up enabled after being
configured, the real output of `pve-firewall status` needed confirming rather than guessed —
the Proxmox man page does not document the exact string. The following was run:

```bash
cat > /etc/pve/firewall/cluster.fw <<EOF
[OPTIONS]
enable: 1
policy_in: ACCEPT
EOF
```

`policy_in: ACCEPT` was used deliberately — this briefly enabled the firewall daemon with a
permissive default policy, not a default-deny one, so no inbound traffic was actually blocked
during the test. Confirmed `Status: enabled/running (pending changes)`, then reverted
immediately:

```bash
rm -f /etc/pve/firewall/cluster.fw
```

Confirmed back to `Status: disabled/running` afterward — the pre-hardening baseline. **Net
state: firewall disabled, same as before the test**, and at no point was inbound traffic
actually restricted.

### 2026-08-18 — fail2ban test-installed and purged twice during pve_security recon

Before writing the `pve_security` fail2ban tasks, the package was installed to check whether it
ships a `pveproxy` filter by default (it does not — one had to be written) and to confirm the
`backend = auto` default correctly targets journald on a host with no `/var/log/auth.log`
(Debian 13 ships no `rsyslog` by default; confirmed absent). Installed and purged once for that
recon, then installed a second time to run `fail2ban-regex` against the real
`/var/log/pveproxy/access.log` and confirm the hand-written `proxmox` filter actually matches
real 401 lines (it matched 12 of 12157 real log lines) rather than trusting the regex
unverified. Both times:

```bash
apt-get install -y --no-install-recommends fail2ban
# ... verification ...
systemctl stop fail2ban
systemctl disable fail2ban
apt-get purge -y fail2ban
rm -f /etc/fail2ban/filter.d/proxmox.conf
```

**Net state:** fail2ban not installed — the same state as before recon. Confirmed via
`dpkg -l fail2ban` showing no `ii`/`rc` entry after each purge.

### 2026-08-XX — dnsmasq left running wildcard-bound during pve_network development

While verifying dnsmasq configuration syntax for `pve_network` (checking `conf-dir` defaults and
`no-dhcp-interface` behaviour against the real package before writing the role), the following
was run against the host:

```bash
apt-get install -y dnsmasq
```

Installing the package starts and enables its systemd unit with the stock `dnsmasq.conf`, which
listens on the **wildcard address** (`0.0.0.0:53` and `[::]:53`, TCP and UDP) across every
interface — including the tailnet and the management LAN — until a scoped `interface=` +
`bind-interfaces` config is applied. No `dhcp-range` was configured, so it was not issuing DHCP
leases, but it was answering DNS queries on interfaces it had no business reachable on.

Reverted immediately on discovery:

```bash
systemctl stop dnsmasq
systemctl disable dnsmasq
```

Confirmed nothing listening on port 53 afterward (`ss -tulnp`). **Net state:** dnsmasq is
installed but stopped and disabled — the same state a fresh `apt install` without starting the
service would leave it in. `pve_network`'s `dhcp.yml` tasks re-enable it only after the scoped
`/etc/dnsmasq.d/lab-network.conf` is in place, so the wildcard-bound window does not recur when
the role itself runs.

Recorded here rather than silently fixed because the working agreement for this project is that
every host-affecting command gets disclosed, not just the ones that turn out to matter.

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
