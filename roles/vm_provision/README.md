# `vm_provision`

Clone golden templates into lab VMs, apply cloud-init configuration and snapshot.

Turns templates into running lab VMs.

Clones the template per VM, sizes CPU/memory/disk, attaches the extra disks each lab needs,
configures cloud-init (hostname, admin user, public key, addressing), places the VM in the
`labs` pool, boots it, waits for the guest agent, and takes a `clean` snapshot.

**Guards.** Operates only on VM IDs drawn from inventory, never touches host storage, and keeps
the teardown path behind an explicit flag.

## Tags

`provision`

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
