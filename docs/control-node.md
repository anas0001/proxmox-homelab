# Control node setup

Everything needed to go from a bare workstation to a working Ansible control node for this
repository. The control node is wherever you run `make` from — it never needs to be the Proxmox
host, and deliberately is not.

If you only want to read the code, skip to [Linting without a host](#linting-without-a-host):
the repository lints cleanly with no host, no inventory and no vault.

---

## 1. Requirements

| Component | Version | Why |
|---|---|---|
| Python | 3.11+ | `ansible-core` 2.19 dropped support for older releases |
| `ansible-core` | 2.19+ | Modern module signatures, native `result_format` |
| `ansible-lint` | 26.x | Enforces the `production` profile this repo requires |
| `yamllint` | 1.35+ | |
| `pre-commit` | 3.5+ | Runs gitleaks and the linters before every commit |
| `git` | 2.30+ | |

On the Proxmox side you need SSH access as a user who can `become` root, and nothing else — the
API token is created *by* this repository, not required before it.

## 2. Install into a virtualenv

A virtualenv, not a system-wide install. Ansible releases move quickly and a distro-packaged
`ansible` will fight the versions this repo expects. The `Makefile` looks for `.venv/bin` and
falls back to `PATH`, so the same targets work here and in CI.

```bash
git clone git@github.com:anas0001/proxmox-homelab.git
cd proxmox-homelab

python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install ansible-core ansible-lint yamllint pre-commit

make deps          # Galaxy collections + pre-commit hooks
```

`.venv/` is gitignored. There is no need to `activate` it — every `make` target resolves the
binaries itself.

Verify:

```bash
.venv/bin/ansible --version      # expect core 2.19+
make lint                        # expect: Passed ... Profile 'production' ... passed
```

## 3. SSH access to the host

Use a **dedicated key**, not the one that authenticates you to GitHub. If a lab guest is ever
compromised, the blast radius should stop at the lab.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_homelab -C "homelab-admin"
ssh-copy-id -i ~/.ssh/id_ed25519_homelab.pub root@<host>
```

A `~/.ssh/config` entry keeps the address out of your shell history and gives the inventory a
stable name to refer to:

```
Host pvelab
    Hostname      100.x.x.x            # the host's tailnet address
    User          root                 # svc_admin once pve_security has run
    IdentityFile  ~/.ssh/id_ed25519_homelab
```

Note this is an **SSH alias**, not DNS. `ssh pvelab` works; `ping pvelab` does not.

## 4. Inventory and vault

Both real files are gitignored; the committed `*.example.yml` files are sanitised templates.

```bash
cp inventories/homelab/hosts.example.yml inventories/homelab/hosts.yml
$EDITOR inventories/homelab/hosts.yml            # real addresses and users

cp inventories/homelab/group_vars/all/vault.example.yml \
   inventories/homelab/group_vars/all/vault.yml
$EDITOR inventories/homelab/group_vars/all/vault.yml
.venv/bin/ansible-vault encrypt inventories/homelab/group_vars/all/vault.yml
```

The vault password goes in `.vault_pass` (gitignored, mode 600):

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(32))" > .vault_pass
chmod 600 .vault_pass
make vault-check                                  # expect: OK: vault decrypts
```

### Why the vault path is not in `ansible.cfg`

`ansible.cfg` deliberately does **not** set `vault_password_file`. That file is gitignored, so
naming its path in committed configuration makes the repository unusable to anyone who does not
already have it — `ansible-lint` and `--syntax-check` both fail hard when the configured path is
missing, even though neither ever decrypts anything. It broke CI on this repo's first push.

The `make` targets export `ANSIBLE_VAULT_PASSWORD_FILE` when `.vault_pass` exists. Calling
`ansible-playbook` directly bypasses that, so either use `make` or export it yourself:

```bash
export ANSIBLE_VAULT_PASSWORD_FILE=.vault_pass
```

## 5. First run

```bash
make ping                              # connectivity (guests fail until provisioned — expected)
./scripts/host-state.sh > /tmp/before.txt

CHECK=1 make bootstrap                 # dry run, changes nothing
make bootstrap                         # apply

./scripts/host-state.sh > /tmp/after.txt
diff -u /tmp/before.txt /tmp/after.txt  # exactly what moved
make bootstrap                         # idempotence: expect changed=0
```

`TAGS=` scopes a run to one role, and composes with `CHECK=`:

```bash
CHECK=1 TAGS=access make bootstrap
```

## 6. Linting without a host

Useful for CI, for reviewers, and for anyone reading the repository:

```bash
python3 -m venv .venv && .venv/bin/pip install ansible-core ansible-lint yamllint
.venv/bin/ansible-galaxy collection install -r requirements.yml
.venv/bin/yamllint . && .venv/bin/ansible-lint
```

No inventory, no vault, no Proxmox host required.

---

## Running from WSL2

Workable, with two wrinkles worth knowing.

**DNS does not inherit Tailscale.** WSL2 does not pick up the Windows Tailscale resolver, so
MagicDNS names (`host.tailnet-name.ts.net`) fail with *"Temporary failure in name resolution"*.
Use the tailnet IP directly in `~/.ssh/config` and the inventory. Everything works; only name
resolution is missing.

**Latency is inherited, not caused.** WSL2 routes through the Windows host's Tailscale, adding
one NAT hop — visible as `ttl=63` from WSL2 against `TTL=64` from Windows. That hop costs
essentially nothing. If runs are slow, compare against a ping from Windows PowerShell before
blaming WSL2; a matching pattern means the problem is upstream.

## When the link to the host is slow

Ansible is latency-bound: every task is at least one SSH round-trip. On a congested link, runs
crawl or appear to hang.

Diagnose before tuning. `ping -c 60 <host>` over a full minute distinguishes the two cases:

- **Loss** — packets missing. Suspect MTU (WireGuard reduces it to 1280) or a genuinely bad link.
- **Latency spikes with ~0% loss** — replies arriving seconds late, each roughly one ping
  interval below the last, with `pipe N` in the summary. That is a *draining queue*:
  **bufferbloat**, an oversized buffer on a congested link absorbing packets rather than
  dropping them. TCP relies on loss as its congestion signal, so a buffer that never drops
  destroys latency while reporting perfect delivery.

Bufferbloat is fixed at the router with SQM/CAKE queue management, not in Ansible.
[waveform.com/tools/bufferbloat](https://www.waveform.com/tools/bufferbloat) grades it directly.

What helps on this side is connection reuse: `ansible.cfg` sets `ControlMaster=auto` with
`ControlPersist`, so a whole run shares one SSH connection instead of paying setup per task.
Raise `ControlPersist` if runs are long and the link is slow.

## Reaching the lab VMs

Lab guests sit on an isolated network, not the home LAN, so they are not reachable from your
workstation by default. Two options, in `docs/architecture.md`:

- **Tailscale subnet router** — the host advertises the lab subnet
  (`tailscale up --advertise-routes=...`), you approve the route, and lab VMs become reachable
  over the tailnet for SSH, VNC and XRDP. Gate it with tailnet ACLs, or every device on the
  tailnet reaches every lab VM.
- **Run Ansible on the host** — simplest, but gives you no path to the guests from your desk.

The subnet-router route requires `tailscale up`, which re-authenticates and drops the tunnel
Ansible runs over. Record it in `docs/out-of-band.md` first, and have console access to hand.
