# `vm_template`

Build cloud-init golden templates from upstream cloud images.

Produces the reusable golden templates that `vm_provision` clones.

Downloads the upstream cloud image, imports it as a disk, attaches a cloud-init drive, enables
the guest agent and serial console, then converts the VM to a template.

Cloud images are used rather than ISO installs because they are already minimal, already
cloud-init aware, and require no interactive installer — which is what makes the whole
provisioning path reproducible.

## Tags

`provision`

## Variables

See [`defaults/main.yml`](defaults/main.yml); every variable is documented there.
