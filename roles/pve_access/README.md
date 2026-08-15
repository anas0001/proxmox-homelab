# `pve_access`

Least-privilege Proxmox API identity: resource pool, custom roles, automation user and scoped
API token.

Creates the credential that every later API-driven role authenticates with, so that nothing in
this repository ever needs `root@pam`.

- A **resource pool** (`labs`) that owns every lab VM. VM privileges are granted on
  `/pool/labs`, so the token cannot act on a VM created outside the lab.
- Two **custom roles**, split so privileges are granted where they are meaningful: VM rights on
  the pool, storage rights on `/storage/<id>`.
- A dedicated **user** in the `pve` realm, and an **API token** with privilege separation
  enabled.

The token secret is displayed once at creation and cannot be retrieved afterwards; store it in
the vault immediately.

## Why this role uses `pveum` rather than the `community.proxmox` modules

Those modules authenticate against the API, and the credential they would authenticate with is
what this role creates — a circular dependency. `pveum` on the host authenticates through the
local Unix socket, so bootstrapping over SSH avoids storing the Proxmox root password anywhere
at all. Idempotence is therefore implemented explicitly: every task reads current state and
acts only on a real difference.

## Tags

`bootstrap`, `access`

## Variables

See [`defaults/main.yml`](defaults/main.yml). It documents both the privileges granted and,
equally deliberately, the ones withheld and why.
