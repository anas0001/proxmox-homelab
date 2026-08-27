# `lab_linux`

Phase 1 — Linux fundamentals lab: LVM, filesystems and RAID practice on disposable disks.

## It sets the stage; it does not perform the exercises

This role installs the tooling, proves the spare disks are present and safe to destroy, and
writes a brief onto the guest. It deliberately does **not** create the volume group, assemble the
array or make the filesystems.

That restraint is the design, not an omission. Automating the exercise would leave a working
system and nothing learned. Every role in this repository up to now converges infrastructure to a
desired state; this one deliberately stops at "ready to be worked on by hand".

Layers on top of `guest_base`, which must have run first.

## Disks are identified by SCSI slot, never by kernel name

`vm_provision` attaches the lab disks as `scsi1` and `scsi2`. Linux names block devices in
**discovery order, not slot order**, and on these guests the two disagree:

```
scsi1  ->  /dev/sdc
scsi2  ->  /dev/sdb
```

Exactly backwards from the obvious guess. Anything here that hardcoded `/dev/sdb` would have
operated on the wrong disk while looking entirely correct — and in the reset path, that is the
difference between wiping a spare disk and wiping the wrong one.

So slots are resolved through `/dev/disk/by-path/*-scsi-0:0:0:<slot>`, which is stable across
reboots and maps one-to-one onto what the hypervisor configured. The glob deliberately matches
only the trailing `scsi-0:0:0:<slot>`, because the PCI address earlier in that name is a property
of the guest's virtual controller and is not guaranteed to be identical on every VM.

## The safety check that makes the rest safe

Everything destructive is scoped to the resolved disk list, so the role proves that list cannot
contain the boot disk before anything else runs. It asserts three things together:

- the configured boot slot does not appear in the lab slot list;
- no resolved lab disk matches the device actually carrying `/`, read from facts rather than
  assumed;
- that root device resolved to something at all — an empty comparison must not pass by accident.

If any of them fails, the run stops before a single disk is touched.

## Reset

Wipes the lab disks back to unpartitioned so an exercise can be repeated. Guarded like
`vm_provision`'s teardown, because a destructive path needing only one variable is one typo away
from firing during an ordinary run:

```bash
ansible-playbook playbooks/labs/linux.yml --limit node1 \
  -e lab_linux_reset_disks=true -e lab_linux_allow_destroy=true
```

It refuses if a lab disk currently has something **mounted** — this role does not get to decide
that whatever is using it does not matter.

It also tears the stack down from the top before wiping, which is not optional: `wipefs` on a
member of a *running* md array leaves a disk that md re-adds from its superblock on the next scan,
and a PV in an *active* volume group is busy because its logical volumes still hold
device-mapper entries. Both were found by running this against a real LVM stack rather than by
reasoning about it — the LVM half was missing entirely on the first attempt.

**There is a cheaper reset that this role cannot get wrong:** every lab VM has a `clean` snapshot
from `vm_provision`. `qm rollback <vmid> clean` on the host resets the entire guest and cannot
target the wrong disk. Prefer it; the in-guest reset exists for when you want to keep the rest of
the guest's state.

## Running it

```bash
ansible-playbook playbooks/labs/linux.yml            # both linux_lab guests
ansible-playbook playbooks/labs/linux.yml --limit node1
CHECK=1 make …                                       # or --check for a dry run
```

The brief lands at `/etc/lab-linux.md` on each guest, so the exercises are discoverable from an
SSH session rather than only in this repository.

## Verified

Applied to node1 and node2, idempotent on re-run (`changed=0`). The reset path was exercised
against a real LVM stack — volume group across both disks, XFS filesystem, mounted — and
confirmed to refuse while mounted, then to leave both disks with no signatures, no volume group
and no device-mapper entries, with the boot disk and mounted root untouched.

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.

## Tags

`lab-linux`, plus `packages`, `reset` and `brief` for scoping.
