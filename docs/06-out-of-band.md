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

### 3a. TOTP 2FA on `root@pam` — *done, manually, 2026-08-20*

**Why not Ansible.** Enrolling a TOTP device is inherently interactive — scanning a QR code
with an authenticator app — with no safe unattended equivalent. `pve_security` reports this as
a required manual step at the end of every run rather than attempting it.

**What was done.** Datacenter → Permissions → Two Factor → Add, for `root@pam` (the only human
login that exists today; `ansible@pve` is API-token-only and has no interactive session for
TOTP to protect). Recovery keys saved outside the repo.

**Outstanding, not yet done:** `docs/04-security.md` §1 calls for a dedicated human admin
account in the `pve` realm for interactive GUI/console use, with `root@pam` reserved for
emergencies only and 2FA moved to that account. No such account exists yet, and creating one is
not part of any role built so far.

**Verify:** Datacenter → Permissions → Two Factor lists a TOTP entry for `root@pam`.

---

### 3b. `ansible_user: root` → `svc_admin` in `hosts.yml` — *required after `ssh.yml` runs*

**Why not Ansible.** `pve_security/tasks/ssh.yml` disables `PermitRootLogin` and
`PasswordAuthentication` once the `svc_admin` login is verified from the control node. The run
applying that change keeps working afterward — `ControlPersist` holds the already-authenticated
connection open for the rest of that invocation — but `root` stops being a valid credential for
every **subsequent, separate** `ansible-playbook` invocation. Ansible cannot safely rewrite the
inventory it is currently connected with mid-run, so this is a deliberate manual edit rather
than something the role does to itself.

```bash
# In the real (gitignored) inventories/homelab/hosts.yml:
#   ansible_user: root
# becomes:
#   ansible_user: svc_admin
```

**Verify before editing:**

```bash
ssh -i ~/.ssh/id_ed25519_homelab svc_admin@<host>   # must succeed
ssh root@<host>                                      # must now fail/refuse
```

**Status:** `ssh.yml` has run and hardening is now confirmed genuinely active — root SSH login
refused, `svc_admin` working — after a `systemctl reload ssh` was needed by hand to apply it
(see the Incidents entry below). Confirm the checks above still hold, then make the edit — see
`roles/pve_security/tasks/main.yml` and the role README for the full rationale.

---

### 4. Tailscale subnet router for the lab network — *pending, not yet run*

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

### 2026-08-22 — host.fw backed up by hand, and a test package installed in a lab guest, while fixing lab DNS

Before changing the host firewall over the SSH connection that firewall governs, the live rules
were copied aside so a bad rule could be reverted without console access:

```bash
cp /etc/pve/nodes/pve/host.fw /root/host.fw.bak-$(date +%Y%m%d-%H%M%S)
```

The change applied cleanly (`pve-firewall status` → `Status: enabled/running`, and the new rules
appear in `pve-firewall compile` above the `DROP`), so the backup was removed afterwards. The
rules themselves are codified in `pve_security`, not applied by hand.

To prove the fix actually worked rather than trusting the compiled chain, a package was installed
in lab guest `node1` and then removed:

```bash
sudo dnf -y install tree     # exit 0 after the fix; exit 124 (hung) before it
sudo dnf -y remove tree
```

**Net state:** the backup file is gone, `tree` is not installed, and `node1` is back to what it
was apart from dnf's metadata cache. `node1` carries a `clean` snapshot predating both, so any
residue can be rolled back at will.

### 2026-08-22 — probe VMs and guest-disk inspection while diagnosing why no cloned VM would boot

`vm_provision`'s first real run provisioned `node1` correctly and then failed, as designed, on
its "wait for SSH" gate: the guest never answered. The VM was running but had written 1 KB in ten
minutes. Diagnosing that needed several one-off actions against the host, none of which are
codified anywhere:

```bash
# Capture the VM's VGA console through the QEMU monitor (screendump writes a PPM)
echo 'screendump /tmp/vm111.ppm' | qm monitor 111

# Clone the template by hand, twice, to isolate whether the fault was in
# vm_provision's changes (resize, extra disks, cloud-init) or in the template
# itself. It was the template: a clone with NOTHING changed hung identically.
qm clone 9000 991 --name probe-plain --full 1 --storage local-lvm
qm set 991 --bios ovmf --efidisk0 local-lvm:0,efitype=4m,pre-enrolled-keys=0
qm set 991 --cpu host

# Read the guest's /boot read-only, to check the image imported intact
losetup -r -o 108003328 --sizelimit 1048576000 "$LO" /dev/pve/vm-991-disk-0
mount -o ro,norecovery "$LO" /mnt/probe-boot
xfs_db -r -c version "$LO"
umount /mnt/probe-boot && losetup -d "$LO" && rmdir /mnt/probe-boot

# Capture the guest's SERIAL console across a reboot — the step that actually
# found the answer. A short Python script connected to
# /var/run/qemu-server/991.serial0, then issued `qm reset 991` and recorded.
```

**Why the serial capture mattered.** The VGA console showed a GRUB banner and then nothing, which
looked exactly like a bootloader hang and cost real time chasing GRUB, XFS feature flags and
BIOS-versus-UEFI. None of that was the fault. The image's kernel command line carries
`console=ttyS0,115200n8` and **no** `console=tty0`, so everything after GRUB — including the
panic — printed only to the serial port. Reading it gave the answer immediately:

```
Run /init as init process
Fatal glibc error: CPU does not support x86-64-v2
Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00
```

Proxmox's default CPU model (`kvm64`) does not provide the x86-64-v2 baseline that Rocky 9 — and
every EL9 distribution — requires, so glibc aborts before init starts. Confirmed by setting
`--cpu host` on the probe VM and nothing else: the same disk went from 1 KB written to 97 MB and
a fully booted guest.

**Also found, separately:** the template's cloud-init drive was created on `local`, which does not
carry the `images` content type on this host. Any VM using it refuses to start with "storage
'local' does not support content-type 'images'". `vm_provision` passes an explicit `storage:` on
its clone and so silently relocated the drive, which is why this only surfaced on a hand-made
`qm clone`.

Both are fixed in `vm_template` (`vm_template_cpu`, and the cloud-init drive now on
`vm_template_vm_storage`), so this is recorded as diagnosis, not as a manual change to reapply.

**Net state:** probe VM 991 destroyed, the loop device detached and `/mnt/probe-boot` removed,
`node1`/`node2` and template 9000 destroyed for a clean rebuild against the fixed role. Confirmed
with `qm list` empty and `lvs` showing no `vm-*` volumes left behind.

### 2026-08-22 — VM 9000 destroyed a second time after an SSH timeout mid-build, then rebuilt successfully

After the `ide2`/`update_unsafe` and template-conversion (`update: true`) fixes below were both
in place, a full clean rebuild of `tmpl-rocky9` was re-run in the background (no artificial
timeout wrapper, after an earlier attempt was killed by one of my own 300s wrappers that was too
short for this session's slow/unstable link mid-download). The VM shell and disk-import steps
both succeeded (`changed: true`), but the next task — a pure API read
(`community.proxmox.proxmox_vm_info`) — failed with `Timeout (12s) waiting for privilege
escalation prompt`, marking the host `UNREACHABLE`. `provision_vms.yml` sets `become: true` at
the play level for every task in the role, including ones that only need the API token, not
root; this one hit a real `sudo` prompt that never got answered in time, most likely a transient
blip on the same link that made the earlier download take 618s. `ansible ... -m ping` succeeded
immediately afterward, confirming the host was reachable again and this was not a persistent
break.

This left VM 9000 partially built again (shell + 10G disk imported, no cloud-init drive, no
template flag) — a different root cause than the previous incident, but the same resulting
state. The idempotence guard added after the first incident was confirmed working a second time,
against this new cause, before anything was touched: re-running `vm_template` unmodified failed
loudly with the same actionable message rather than silently skipping or recreating.

```bash
qm destroy 9000
```

**Net state:** vmid 9000 freed, its LVM disk removed, confirmed via `qm list` showing nothing —
the same reset pattern as the first incident, and again a deliberate choice of full rebuild over
the cheaper `qm template 9000` shortcut.

**Outcome:** the subsequent clean rebuild completed successfully end-to-end. Confirmed directly
on the host, not from Ansible's own report alone: `qm config 9000` shows `ide2:
local:9000/vm-9000-cloudinit.qcow2,media=cdrom`, `boot: order=scsi0`, and `template: 1`. The
`vm_template` role is now confirmed working against the real host from a clean state.

### 2026-08-21 — VM 9000 destroyed manually after a partial `vm_template` build

`vm_template`'s "Attach a cloud-init drive" task failed live with `Unable to update vm None
with vmid 9000: 'ide2'` — `proxmox_kvm`'s `update: true` deliberately disables updates to
`ide`/`net`/`virtio`/`sata`/`scsi` as a safety feature (confirmed in the module's own docs);
the fix is `update_unsafe: true`, scoped narrowly since this call only ever sets a new `ide2`
cloud-init drive and never touches `scsi0` in the same call. This left VM 9000 in a real
partial state: shell created, disk imported (confirmed exactly 10G, matching the source
image), never converted to a template — which also surfaced a genuine gap in the role's
idempotence check (it tested "does a VM exist at this vmid", not "is it a finished template"),
fixed alongside the `ide2` bug.

Confirmed the new guard against this exact state before destroying anything: re-running
`vm_template` against the still-partial VM 9000 correctly failed loudly with a clear message
naming the problem, rather than silently skipping it as "already built".

```bash
qm destroy 9000
```

**Net state:** vmid 9000 free again, its LVM disk (`vm-9000-disk-0`) removed. Confirmed via
`qm list` showing nothing. Not a revert of unwanted state — a deliberate reset so the fixed
role could rebuild the template cleanly end-to-end, confirmed with the user before running.

### 2026-08-21 — `pipx`/`python3-venv` test-installed and removed while diagnosing the `proxmoxer` version gap

`vm_template`'s first real `--check` run against the host failed: `Requires proxmoxer 2.3 or
newer; found version 2.2.0` — a hard floor in every `community.proxmox` module's shared base
class, not specific to one module or feature. Debian 13's own repo has no newer candidate
(`apt-cache policy python3-proxmoxer` shows only `2.2.0-1` available).

While diagnosing the fix, both `pipx` and `python3-venv` were installed to test isolated-venv
approaches, and `proxmoxer` was installed into two throwaway environments:

```bash
sudo apt-get install -y pipx
pipx install --system-site-packages proxmoxer          # rejected: proxmoxer has no CLI
                                                          # entry point, so pipx refused to
                                                          # keep the venv at all
sudo apt-get install -y python3-venv
python3 -m venv --system-site-packages /tmp/proxmoxer-test-venv
/tmp/proxmoxer-test-venv/bin/pip install "proxmoxer>=2.3"   # confirmed: 2.3.0, and
                                                              # --system-site-packages
                                                              # correctly inherits `requests`
```

Reverted immediately after confirming the approach:

```bash
rm -rf /tmp/proxmoxer-test-venv
pipx uninstall proxmoxer   # no-op — nothing was ever actually installed under pipx
rm -rf ~/.local/share/pipx
sudo apt-get purge -y pipx python3-venv
```

**Net state: `pipx` and `python3-venv` not installed** — the same state as before this
diagnosis. Confirmed via `which pipx python3-venv` returning nothing after the purge.

**Real fix, codified in `pve_base`:** a plain `python3 -m venv --system-site-packages` (not
`pipx`, which is for CLI applications with entry points and refuses to manage a pure library
like `proxmoxer`) at a fixed path, with `pip install "proxmoxer>=2.3"` inside it, and
`ansible_python_interpreter` pointed at that venv's `python3` for the plays that use
`community.proxmox.*` modules. See `roles/pve_base/README.md` and `playbooks/provision_vms.yml`.

### 2026-08-20 — `sshd` never reloaded after `ssh.yml`'s first real run; fixed by hand, then closed in the role

`TAGS=ssh make harden` completed and wrote a correct, fully-hardened
`/etc/ssh/sshd_config.d/00-hardening.conf` (`PermitRootLogin no`, `PasswordAuthentication no`).
`sshd -T` correctly reported the new values. **Root SSH logins kept succeeding for hours
afterward.**

Root cause: the *running* `sshd` process (`ps` showed it started 2026-08-14, six days before the
file was written) never received the `Reload sshd` handler's SIGHUP. `sshd -T` re-parses config
files fresh on every invocation regardless of the running daemon's state, so it reported the
correct target values while the live listener kept enforcing whatever it had loaded at its last
actual start. Ansible handlers fire once, at the end of the play, by default — under a
`--tags ssh` scoped run this can behave differently than expected, and the notified reload
appears not to have fired.

Diagnosed and fixed live, over the existing (still-permissive) root SSH session:

```bash
systemctl reload ssh
```

Confirmed via `journalctl -u ssh`: `Received SIGHUP; restarting` / `Server listening on ...`.
Verified immediately after: three consecutive round-trip tests, root refused
(`Permission denied (publickey)`) and `svc_admin` succeeding, every time.

**This was then closed in the role, not left as a one-off fix.** `roles/pve_security/tasks/ssh.yml`
now flushes handlers immediately after rendering the config (rather than at end-of-play) and
follows with a real SSH connection attempt as root, asserting it is refused — the same
verify-the-actual-effect pattern `firewall.yml` already used for `pve-firewall status`. See the
role README for the full detail.

**Net state:** intentional — the host is now correctly hardened, root refused, `svc_admin`
working. Recorded because the hardening was silently inert for a real, non-trivial window on a
production apply, not because anything here needs reverting.

### 2026-08-20 — `sudo` installed manually to unblock a real `pve_security` run, then codified

`TAGS=ssh make harden` failed on "Grant passwordless sudo to the admin group" with `[Errno 2]
No such file or directory: b'visudo'`. Proxmox's base install does not pull in the `sudo`
package — confirmed via `dpkg -l sudo` showing nothing installed. The `sudo` **group** (gid 27)
is a separate, reserved base-system group that exists regardless, so `svc_admin` had already
been correctly added to it by the preceding task; only the package providing the `sudo`/`visudo`
*commands* was missing.

```bash
apt-get install -y sudo
```

This is real, permanent state, not a reverted test: `svc_admin` genuinely needs the `sudo`
command to be useful. `roles/pve_security/tasks/ssh.yml` now installs it explicitly as its own
task before granting the sudoers rule, so a rebuilt host converges to the same state without
this manual step. Recorded here because it was applied by hand before the role was fixed to
cover it, not because it remains a gap.

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
