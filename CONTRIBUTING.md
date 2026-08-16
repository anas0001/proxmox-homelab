# Contributing / working conventions

Even as a solo project, this repo follows team conventions so it reads like production work.

## Branching
- `main` is protected and always green. Never commit directly to `main`.
- Short-lived branches, one feature each:
  `feat/<thing>`, `fix/<thing>`, `docs/<thing>`, `chore/<thing>`, `refactor/<thing>`, `ci/<thing>`.

## Commits — Conventional Commits
```
<type>(<optional scope>): <imperative summary>

<why + what, wrapped ~72 cols>
```
Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `ci`, `test`, `perf`, `build`.
Keep commits small and logical; each should build/lint on its own.

## Pull requests
- Open a PR per branch with a short what/why.
- CI (yamllint, ansible-lint, gitleaks) must pass before merge.
- Rebase or squash-merge to keep history linear and readable.

## Before every commit
```
make lint            # yamllint + ansible-lint (production profile)
make secrets-scan    # gitleaks
```
`pre-commit install` runs these automatically. Do not bypass hooks to commit secrets.

## Ansible standards
See `AGENTS.md` section 6. FQCN, idempotent, roles with documented `defaults`, Vault for all
secrets with `no_log: true`, tags for scoping, least-privilege connections.

## Definition of done
Idempotent (2nd run `changed=0`), linted, no secrets, documented, `CHANGELOG.md` updated,
merged via PR.

## Security disclosure
Found something sensitive committed? Rotate the credential first, then open an issue/PR to scrub
history. See `docs/04-security.md` section 8.
