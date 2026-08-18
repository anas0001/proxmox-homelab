#!/usr/bin/env bash
#
# topology-scan.sh — fail if tracked files leak real topology.
#
# gitleaks finds credentials. It does not find a real IP address, hostname or
# MAC written into a document, and AGENTS.md section 9 forbids those just as
# firmly: a stranger should be able to reproduce this lab on their own hardware
# while learning nothing that helps them reach this one.
#
# Scans only tracked files, since untracked and gitignored files are exactly
# where real values are supposed to live.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
report() { printf '  ✖ %s\n' "$1"; fail=1; }

# Tailnet CGNAT host addresses (100.64.0.0/10). RFC1918 is permitted: the
# committed examples use it deliberately and it reveals nothing.
#
# The bare range 100.64.0.0/10 is explicitly allowed. It appears throughout the
# firewall rules and documentation as a *range*, names no host, and is identical
# for every Tailscale user on earth. Only a specific address inside it leaks.
while IFS= read -r hit; do
    report "tailnet address: $hit"
done < <(git grep -nIE '\b100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b' -- . 2>/dev/null \
         | grep -vE '100\.64\.0\.0/10')

# Tailnet DNS names. Placeholders using the literal words "tailnet-name" or
# "tailnet" as the subdomain are documentation, not a real tailnet.
while IFS= read -r hit; do
    report "tailnet DNS name: $hit"
done < <(git grep -nIE '[a-z0-9-]+\.ts\.net' -- . 2>/dev/null \
         | grep -vE 'tailnet-name\.ts\.net|<[^>]+>\.ts\.net|tailnet\.ts\.net')

# MAC addresses.
while IFS= read -r hit; do
    report "MAC address: $hit"
done < <(git grep -nIE '\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b' -- . 2>/dev/null)

# Real-looking email addresses. example.com and the GitHub noreply form are
# fine, and so is @openssh.com/@libssh.org — those are RFC 4251 vendor-
# extension suffixes on SSH algorithm names (e.g.
# chacha20-poly1305@openssh.com), not addresses, and this repo names several
# of them in roles/pve_security's KEX/cipher/MAC lists.
while IFS= read -r hit; do
    report "email address: $hit"
done < <(git grep -nIE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' -- . 2>/dev/null \
         | grep -vE 'example\.(com|org)|users\.noreply\.github\.com|@pve|@pam|noreply@anthropic\.com|admin@|you@|git@|@openssh\.com|@libssh\.org')

if [ "$fail" -ne 0 ]; then
    echo
    echo "  Real topology found in TRACKED files. See AGENTS.md section 9." >&2
    echo "  Replace with RFC1918 ranges and placeholder names; keep real" >&2
    echo "  values in the gitignored inventory." >&2
    exit 1
fi
echo "  topology-scan: clean (no real addresses, DNS names, MACs or emails)"
