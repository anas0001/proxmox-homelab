# Runbook — first run & day-2 ops

## Prerequisites (on your workstation)
- Proxmox VE installed on the host, reachable over SSH from your workstation.
- `ansible-core`, `ansible-lint`, `yamllint`, `pre-commit`, `git` installed.
- An ed25519 SSH keypair for the admin user.
- A Proxmox **API token** created for automation (see below).
- Tailscale already installed on the host (you joined it manually) — no auth key needed unless
  you automate enrolment. See the optional section below.

## One-time: create the least-privilege API token (on the host UI or CLI)
```
# Create a pool, a role, a user, grant, and a token (adjust names).
pveum pool add labs
pveum role add Ansible -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU \
  VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network \
  VM.Config.Options VM.PowerMgmt VM.Snapshot VM.Monitor Datastore.AllocateSpace \
  Datastore.Audit SDN.Use VM.Audit"
pveum user add ansible@pve
pveum aclmod /pool/labs -user ansible@pve -role Ansible
pveum user token add ansible@pve automation --privsep 1
# Copy the token secret ONCE into your Vault as vault_pve_api_token_secret. Never commit it.
```

## (Optional) Tailscale auth key (tagged) — only for unattended enrolment
1. Access Controls: ensure `tag:homelab` is in `tagOwners` (see `docs/tailscale-acl.hujson`).
2. Settings -> Keys -> Generate auth key: **non-ephemeral**, single-use (or reusable),
   **pre-approved** (if device approval is on), **Tags: `tag:homelab`**.
   (If the tag isn't in the dropdown, it isn't in `tagOwners` yet.)
3. Store the key ONCE in Vault as `vault_tailscale_auth_key`. Never commit it.
4. After enrolment: Machines -> the host -> **Disable key expiry** so it never drops off.
> Manual keys need no API scope. Only if you auto-generate via an OAuth client do you need the
> `Auth Keys: Write` scope (and the client must carry `tag:homelab`).

## First run
```
git clone <your-repo> && cd homelab
cp inventories/homelab/hosts.example.yml inventories/homelab/hosts.yml      # edit real values
cp inventories/homelab/group_vars/all/vault.example.yml \
   inventories/homelab/group_vars/all/vault.yml
ansible-vault encrypt inventories/homelab/group_vars/all/vault.yml          # fill secrets first
echo "<your-vault-password>" > .vault_pass && chmod 600 .vault_pass         # gitignored

# The vault password path is NOT in ansible.cfg — that file is committed, and
# .vault_pass is not, so hardcoding it there breaks linting for CI and for
# anyone else who clones this repo. The `make` targets export this for you;
# set it yourself only when calling ansible-playbook directly.
export ANSIBLE_VAULT_PASSWORD_FILE=.vault_pass

make deps            # collections + pre-commit hooks
make ping            # connectivity
make check           # dry-run everything
make site            # bootstrap -> harden -> network -> provision -> configure
make site            # run again: expect changed=0 (idempotence)
```

## Day-2
- Add/remove a lab VM: edit inventory, `make provision` (guarded; state from inventory).
- Reset a lab VM: roll back to its `clean` snapshot (Proxmox UI/`qm rollback`).
- Watch storage: `make check` includes the thin-pool guard; keep `local-lvm` Data% < 80.
- Update host: patch during a maintenance window; reboot manually (it's a hypervisor).

## Storage capacity (manual, not automated — and deliberately so)

Ansible **monitors** thin-pool usage and fails above `pve_thin_pool_warn_percent`. It does not
**manage** pool size. Capacity is a one-time decision rather than continuously-converged desired
state, and `lvextend` is one-way — a thin pool cannot be shrunk — so a config-management loop
that "corrects" pool size could only ever ratchet upward.

Extend the pool into the unallocated 16 GB. Online, no downtime, no VM disruption:

```bash
vgs                                 # confirm free extents exist
lvextend -l +100%FREE /dev/pve/data
lvs -o lv_name,lv_size,data_percent,metadata_percent
```

If the labs later outgrow that, `pve-root` is 65 GB holding ~8 GB and can be shrunk to reclaim
~33 GB more. That requires live media (ext4 cannot shrink mounted, and `/boot` is on the same
volume) — shrink the **filesystem before** the logical volume, never the reverse.

## Recovery
- Host config lives in `/etc/pve` + this repo. Restore = reinstall Proxmox, restore `/etc/pve`
  from backup, `make site`.
- VM configs are backed up via vzdump; restore from the backup target.
- **Test a restore before you rely on it.**
