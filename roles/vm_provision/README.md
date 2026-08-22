# `vm_provision`

Clone golden templates into lab VMs, apply cloud-init configuration and snapshot.

Turns the templates `vm_template` built into running lab VMs. Clones the template per VM, sizes
CPU/memory/disk, attaches the extra disks each lab needs, configures cloud-init (hostname, admin
user, public key, static addressing), places the VM in the `labs` pool, boots it, waits for the
guest to actually answer, and takes a `clean` snapshot.

**Guards.** Operates only on VM IDs drawn from its own catalogue, never touches host storage, and
keeps the teardown path behind two separate switches.

## Cloning is two tasks, not one — and that is not a style choice

`proxmox_kvm` passes only six parameters to the API on a clone: `format`, `full`, `pool`,
`snapname`, `storage`, `target`. This is not in the module's prose documentation; it is the
`valid_clone_params` list in its source, confirmed by reading it. Every other parameter — cores,
memory, `ciuser`, `sshkeys`, `ipconfig` — is accepted by the module and **silently dropped**. On
top of that, `clone` and `update` are declared mutually exclusive in the argument spec, so a
single "clone and configure" task is impossible even in principle.

So the role clones first, then applies everything else in a separate `update: true` task. A
version of this role that looked correct and set nothing would have been very easy to write.

Two related traps in the same module, both confirmed by reading the source rather than by
guessing after the fact:

- `net` and `pool` are dropped on an `update`. `pool` genuinely cannot be set that way (the
  `qemu/<vmid>/config` endpoint does not accept it), which is why the pool is passed at clone
  time — and the pool is the boundary the API token's privileges are scoped to, so a clone that
  landed outside it would produce a VM this automation could no longer manage. `net` is dropped
  as a deliberate safety feature unless `update_unsafe` is set; the clone inherits the template's
  `net0` with a fresh MAC, which is what is wanted, so it is never set here.
- `state: absent` against a **running** VM without `force: true` exits `changed=false` with
  "Stop it before deletion or use force=true" — a no-op that reads as success in a play recap.
  The teardown path therefore stops the VM in its own explicit task first.

## Full clones, not linked

`full: true`, deliberately. A linked clone keeps every lab VM permanently dependent on template
9000, which makes rebuilding that template — the thing `vm_template` exists to let you do freely
— impossible while any lab VM survives. On LVM-thin a full clone still occupies only the blocks
actually written, so that independence costs close to nothing here.

## Addresses come from inventory, not from this role

The VM catalogue in `defaults/main.yml` carries sizing, disks and vmid. It deliberately does not
carry addresses: each guest's static IP is read from its `ansible_host` in the **gitignored** real
inventory, which is the same entry `guest_base` and every later play reach that VM through. One
copy of the mapping cannot drift from another, and `docs/03-network.md` requires the real mapping
stay out of committed files.

vmids encode the address rather than being allocated arbitrarily — `node1` at `10.10.10.11` is
vmid 111, `ceph2` at `10.10.10.22` is vmid 122 — so "which VM is this" is answerable from either
direction, and every lab VM stays clear of the 9000 range Proxmox convention reserves for
templates.

Addresses sit below the dnsmasq pool (`10.10.10.100-200`) on purpose: a lab guest's address is
decided by this repository, not by lease order.

## Readiness is SSH, not the guest agent

The role waits for **port 22 on the guest**, from the Proxmox host, rather than pinging the QEMU
guest agent. SSH answering proves the guest booted, cloud-init applied the static address, and
sshd is serving the injected key — precisely the state `guest_base` needs next. An agent ping
proves only that the agent started.

It runs from the Proxmox host because that is where this play already is, and the host is the lab
subnet's gateway. The control node cannot reach `10.10.10.0/24` at all until the Tailscale subnet
route in `docs/06-out-of-band.md` is advertised and approved, so a wait that ran from the
workstation would hang on a perfectly healthy guest.

The guest agent is still enabled at template level — it is what makes clean shutdowns and
`qm guest exec` work — it is just not the readiness gate.

## Disk sizing, and why the order matters

The boot disk is grown **before first boot**. Rocky's cloud image runs cloud-init's
`growpart`/`resizefs` at boot, so a disk enlarged beforehand is a filesystem the guest has already
expanded into by the time it is reachable. Enlarging it afterwards leaves the space unclaimed
until something inside the guest grows the partition by hand.

The resize is conditional on the disk's real current size, read back through the API — same
pattern and same reason as `vm_template`: `proxmox_disk`'s `resized` state can only grow a disk,
so an unconditional resize would attempt a no-op or a shrink on every subsequent run.

Extra disks use `create: regular` (the module default), which creates a missing disk and updates
options on an existing one. Explicitly **not** `forced`, which detaches the existing disk and
allocates a new one — on a re-run that would silently orphan whatever the lab had written.

## Convergent, not one-shot

Every step re-reads real state and is safe to re-run, so a run interrupted halfway is finished by
running it again. This is a deliberate difference from `vm_template`, which fails loudly on a
partial build because converting a VM to a template is a one-way step that cannot be re-applied.
Nothing here is terminal in that way.

The role still refuses to touch a vmid occupied by a VM whose name does not match the catalogue
entry, rather than reconfiguring, resizing and snapshotting something it did not create.

## Snapshots

One snapshot per VM, named `clean`, taken once the guest genuinely answers — so it captures the
pristine post-cloud-init state a lab can be reset to. Taken once and never refreshed: re-taking it
would quietly redefine the state the lab expects to roll back to.

Disk-only (`vmstate: false`). A RAM image would add the VM's full memory to the thin pool per
snapshot, and rolling back to a stopped VM that then boots clean is the wanted behaviour anyway.
Kept to a single snapshot deliberately — snapshots grow as the VM diverges, and the storage plan
in `docs/02-architecture.md` has no room for a chain.

## Teardown

Guarded by two independent switches, because a teardown one typo away from an ordinary
provisioning run is not guarded at all:

```bash
ansible-playbook playbooks/provision_vms.yml --tags provision-vms \
  -e vm_provision_state=absent -e vm_provision_allow_destroy=true
```

Before deleting anything, each VM must independently clear: the opt-in flag is set, the vmid
resolves to a real VM, that VM is inside the `labs` pool, its name matches the catalogue entry
being torn down, and it is **not** a template. A VM already gone is reported and skipped rather
than treated as an error, so `absent` is usable for cleaning up a partially-provisioned set.

`destroy_unreferenced_disks` is never set — it reaches beyond the VM's own config to any volume on
the storage that looks unreferenced, far too broad a blast radius for a routine lab teardown.

## Which VMs get built

`vm_provision_vms` is the full catalogue, mirroring the VM inventory table in
`docs/02-architecture.md`. `vm_provision_build` selects which of them to act on, and defaults to
the Linux lab only — matching Phase 1 and the explicit guidance in that document not to run every
lab set at once. RAM is ample on this host; disk churn is the constraint. Widen it per phase.

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.

## Tags

`provision-vms`
