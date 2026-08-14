# Homelab automation — common tasks. Run `make help`.
.DEFAULT_GOAL := help
SHELL := /bin/bash

# Prefer a local virtualenv when one exists, otherwise fall back to whatever is
# on PATH. Lets the same targets work both here and in CI, where the tooling is
# pip-installed globally into the runner.
BIN := $(shell [ -x .venv/bin/ansible ] && echo .venv/bin/)

# Point Ansible at the vault password only when the file is actually present.
# Deliberately not set in ansible.cfg: that path is gitignored, so hardcoding it
# in committed config breaks linting for CI and for anyone else cloning the repo.
VAULT_PASS := $(wildcard .vault_pass)
ifneq ($(VAULT_PASS),)
export ANSIBLE_VAULT_PASSWORD_FILE := $(VAULT_PASS)
endif

.PHONY: help deps lint syntax check ping bootstrap harden provision configure site secrets-scan vault-check

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

deps:  ## Install Galaxy collections + pre-commit hooks
	$(BIN)ansible-galaxy collection install -r requirements.yml
	$(BIN)pre-commit install

lint:  ## Lint everything (yaml + ansible)
	$(BIN)yamllint .
	$(BIN)ansible-lint

syntax:  ## Ansible syntax check
	$(BIN)ansible-playbook playbooks/site.yml --syntax-check

check:  ## Dry-run the whole site (no changes)
	$(BIN)ansible-playbook playbooks/site.yml --check --diff

ping:  ## Connectivity test to all hosts
	$(BIN)ansible all -m ansible.builtin.ping

bootstrap:  ## Base Proxmox config (repos, packages, users)
	$(BIN)ansible-playbook playbooks/pve_bootstrap.yml

harden:  ## Apply Proxmox security hardening
	$(BIN)ansible-playbook playbooks/pve_harden.yml

provision:  ## Create/update lab VMs from templates
	$(BIN)ansible-playbook playbooks/provision_vms.yml

configure:  ## Configure guest VMs (base + per-role)
	$(BIN)ansible-playbook playbooks/configure_guests.yml

site:  ## Full run: bootstrap -> harden -> provision -> configure
	$(BIN)ansible-playbook playbooks/site.yml

secrets-scan:  ## Scan working tree for secrets
	$(BIN)pre-commit run gitleaks --all-files

VAULT_FILE := inventories/homelab/group_vars/all/vault.yml

vault-check:  ## Verify the vault password works and the vault decrypts
	@if [ -z "$(VAULT_PASS)" ]; then \
	  echo "FAIL: .vault_pass not found. See docs/runbook.md."; exit 1; fi
	@if [ ! -f "$(VAULT_FILE)" ]; then \
	  echo "FAIL: $(VAULT_FILE) not found. Copy vault.example.yml and encrypt it."; exit 1; fi
	@$(BIN)ansible-vault view "$(VAULT_FILE)" >/dev/null \
	  && echo "OK: vault decrypts with $(VAULT_PASS)" \
	  || { echo "FAIL: wrong vault password, or the file is not encrypted."; exit 1; }
