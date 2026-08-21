# `pve_security`

Security hardening for the Proxmox VE host: SSH, firewall, fail2ban, auditd and sysctl.

Implements the target state in [`docs/04-security.md`](../../docs/04-security.md). This is the
highest-stakes role in the project: it runs over the exact SSH connection it is about to
restrict, and disables root login and password auth on a host whose only recovery path is an
awkward physical console. Read `teach/01-decisions.md` D4 before changing anything here.

## The one rule this role is built around

**Prove the new access path before closing the old one.** `ssh.yml` creates `svc_admin`,
installs its key, grants sudo — then makes a real SSH connection *from the control node* as
`svc_admin` and fails the whole run if it doesn't succeed, before any task touches
`PermitRootLogin` or `PasswordAuthentication`. If that check fails, root/password access is
completely unchanged; the run simply stops.

Everything else follows the same instinct:

- **SSH**: `validate: "sshd -t -f %s"` on the config template, plus a second `sshd -t` in the
  reload handler — belt and braces, since a broken `sshd_config.d` file with no way back in is
  the single worst outcome this role could produce. Reload, not restart: the running daemon
  keeps existing sessions (including Ansible's own) while re-reading config for new ones.
  Handlers are flushed immediately after the render (`meta: flush_handlers`) rather than left
  to the natural end of the play, and the reload's *effect* is then verified with a real SSH
  connection attempt as root — not `sshd -T` (which re-parses the config files fresh regardless
  of whether the running daemon has reloaded) and not a systemd timestamp (unreliable across a
  SIGHUP-based reload). This exists because it happened for real: a completed `--tags ssh` run
  left a correct, hardened file on disk while the *running* `sshd` process kept serving its
  previous config from days earlier — handlers only fire once, at end-of-play by default, and a
  tag-scoped run changes what "end of play" means. Root logins kept succeeding for hours after
  the file was written, with `sshd -T` misleadingly reporting `permitrootlogin no` the whole
  time. See `docs/06-out-of-band.md`.
- **Firewall**: allow rules (`host.fw`) are written and compiled with the firewall **still
  disabled**; the cluster-wide default-deny policy (`cluster.fw`, `enable: 1`) is templated
  **only after**, as a separate task, so "rules exist" and "policy enforced" are two distinct,
  individually observable steps in that order. A run-time assertion confirms
  `pve-firewall status` actually reports enabled afterward.
- **Two independent allow-sources.** Both the Tailscale CIDR and the management LAN CIDR go into
  Proxmox's standard `management` IPSet, so neither path is a single point of failure.

## What was verified against the real host before being written, not assumed

- **KEX/cipher/MAC algorithms** were cross-checked against `ssh -Q kex/cipher/mac` on this
  host's actual OpenSSH 10.0 build, not copied from a generic hardening guide. A test that
  forced the local (older, OpenSSH 9.6) client to explicitly demand
  `mlkem768x25519-sha256` failed outright — OpenSSH clients hard-reject an unknown algorithm
  named in an *explicit* override. Confirmed separately that this does **not** affect normal
  negotiation: a server offering it first and a client with no explicit override negotiate
  correctly by falling back through the list, tested end-to-end against a throwaway `sshd`
  instance on an alternate port.
- **`sshd -t -f <file>` validates a standalone drop-in** without needing the rest of
  `sshd_config` for context — confirmed with both a valid and a deliberately broken file.
- **The rendered `00-hardening.conf`** was `scp`'d to the host and passed `sshd -t` for real.
- **`pve-firewall compile`** was run against the actual rendered `cluster.fw`/`host.fw` staged on
  the host, confirming the generated iptables rules match the intended policy — including
  discovering that naming an IPSet `management` makes Proxmox auto-generate its own GUI/SSH/VNC
  access rules for it, independent of this role's explicit ones (kept anyway, so the access
  policy is legible from `host.fw` alone rather than depending on that undocumented-in-detail
  behaviour).
- **The `proxmox` fail2ban filter** was checked with `fail2ban-regex` against the real
  `/var/log/pveproxy/access.log` (12 genuine matches out of 12,157 lines) rather than trusted on
  regex inspection alone.
- **auditd rules** were loaded live with `auditctl -R` in both the initial `-w`/`-p` watch form
  (accepted, but flagged "Old style watch rules are slower") and the modern
  `-F path=... -F perm=...` syscall-rule form that replaced it, confirming the second loads
  cleanly and expands to the expected syscall set.

Every host-affecting command run during this verification is logged in
[`docs/06-out-of-band.md`](../../docs/06-out-of-band.md) under Incidents, reverted immediately
after each check.

## Nothing here depends on `ansible_facts`

`firewall.yml` originally used `ansible_facts['hostname']` to build the `host.fw` path. Under a
`--tags firewall` run this failed with a confusing `object of type 'dict' has no attribute
'hostname'` rather than a clear "facts not gathered" error — reproduced down to a two-line
throwaway role: **when a role is invoked from a `roles:` list with no tag of its own, inside a
play carrying only a play-level tag, running with `--tags <scoped-to-one-task>` makes Ansible
skip both the implicit "Gathering Facts" step and every untagged task in the role.** Tagging the
task `always` does not override this — confirmed by testing that too. `pve_base`'s
`os_family`-based host-identity check had the identical exposure.

Neither role guesses around the exact tag combination that triggers this. Both were rewritten to
not depend on gathered facts at all: `firewall.yml` reads the real Proxmox node name straight
from `/etc/pve/local` (a symlink Proxmox itself maintains — confirmed live,
`readlink /etc/pve/local` → `nodes/pve`), and `pve_base`'s host check relies solely on `/etc/pve`
existing as a directory, which is already load-bearing on its own.

## `/etc/pve` cannot be written with `ansible.builtin.template`/`copy` directly

`/etc/pve` is **pmxcfs**, a FUSE filesystem backed by a replicated SQLite database, not a real
disk-backed filesystem (`mount` shows `/dev/fuse on /etc/pve type fuse`). `template`'s and
`copy`'s atomic-replace machinery tries `os.link()` first when moving a rendered temp file into
place — a normal optimisation, avoiding a full copy when a hardlink-then-rename will do — and
pmxcfs does not support hardlinks at all. `os.link()` against it fails with `EPERM`, confirmed
directly with a Python one-liner over the connection, independent of Ansible. `unsafe_writes:
true` does not help either: it still routes through a copy-then-preserve-permissions step that
hits the same error. A plain `cp` (a real copy, no linking) succeeds cleanly.

So `cluster.fw` and `host.fw` are never targeted by `template`/`copy` directly. Each is rendered
to a normal-filesystem staging path (`/tmp`, where `template`'s atomic-move machinery works
fine), then copied into `/etc/pve` with `ansible.builtin.command: cp`, only when its checksum
differs from what is already live — comparing `template`'s own `is changed` against the staging
path would be wrong, since a stale leftover staging file from an earlier run could report
unchanged even when the real `/etc/pve` content differs. `owner`/`group`/`mode` are never set on
anything under `/etc/pve` either: pmxcfs assigns `root:www-data 0640` to every file natively
regardless of what is requested, confirmed by inspecting a file written with no explicit
attributes at all.

Verified end-to-end against the real host, not just reasoned about: a full render → stage →
checksum-compare → copy → re-run cycle correctly reported `changed` on the first apply and
`changed=False` on an identical second one.

## A gap this role does not close on its own

`inventories/homelab/hosts.yml` (gitignored, real values) sets `ansible_user: root` for the
`pve` group. Once this role disables `PermitRootLogin`, that stops being valid for every
**future** Ansible connection — the run that applies the change keeps working
(`ControlPersist` holds the already-authenticated connection open for the rest of that
invocation), but the next separate `ansible-playbook` invocation will try `root` and be
refused. This is a required **manual** edit after the role's first successful, verified run —
deliberately not something the role does to its own inventory mid-run. See the note at the top
of `tasks/main.yml`.

## What is deliberately left manual, and reported as such at the end of every run

TOTP 2FA (inherently interactive — no safe unattended equivalent), TLS/ACME (needs a DNS-01
provider or exposed HTTP-01, a decision this role cannot make for you), and backups (needs a
real target that doesn't exist yet). Each is a `debug` message naming the exact manual step,
not a silent omission.

## Tags

`ssh`, `firewall`, `fail2ban`, `auditd`, `sysctl`.

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
