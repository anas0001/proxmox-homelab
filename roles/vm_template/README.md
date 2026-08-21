# `vm_template`

Build cloud-init golden templates from upstream cloud images.

Produces the reusable golden templates that `vm_provision` clones from: downloads the upstream
cloud image, creates a minimal VM shell, imports the image as its boot disk, attaches a
cloud-init drive, enables the guest agent and serial console, then converts the VM to a
template. Idempotent — re-running after a successful build for the same `vmid` does nothing.

Cloud images are used rather than ISO installs because they are already minimal, already
cloud-init aware, and require no interactive installer — which is what makes the whole
provisioning path reproducible.

## API-only, deliberately

Every task authenticates through the least-privilege API token `pve_access` created
(`pve_api_host`/`pve_api_user`/`pve_api_token_id` from inventory), never SSH or `root@pam`.
Where a design question could have been answered by shelling into the host, it wasn't — see
"Sizing the imported disk" below, the case that most tempted it.

## Idempotence: checked before building, not caught after failing

The first real task checks whether a VM already exists at the configured `vmid` via
`community.proxmox.proxmox_vm_info` and skips the rest of the build entirely if so
(`meta: end_task`). Confirmed directly against that module's source rather than assumed: its own
documentation states a nonexistent `vmid` returns an empty list, not an error, which is what
makes this a clean existence check rather than something that needs a `failed_when` workaround.

## Sizing the imported disk

`community.proxmox.proxmox_disk`'s `resized` state can only **grow** a disk — confirmed in its
own docs ("As of Proxmox 7.2 you can only increase the disk size"). The image import creates the
boot disk at the source qcow2's own virtual size, which for Rocky's current cloud image is
exactly 10 GiB — verified directly with `qemu-img info` against the real downloaded file, not
assumed from documentation — and happens to equal this role's `disk_gb` default. Resizing
unconditionally would attempt a same-size (or eventually, once an image changes, a shrink)
"resize" every single run, an edge case the module's docs don't describe the behaviour of.

Rather than shell into the host to check the disk's real size with `qemu-img` (the obvious,
fastest way to answer this, and the way it was actually verified during development), the role
reads it back through the API instead — `proxmox_vm_info` with `config: current` returns the
VM's live config, including the `scsi0` disk string (`local-lvm:vm-9000-disk-0,size=10G`), which
is parsed and compared before the resize task runs at all. Keeping this role API-only throughout
was worth the extra task over the SSH shortcut.

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.

## Tags

`template`
