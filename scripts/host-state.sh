#!/usr/bin/env bash
#
# host-state.sh — capture a read-only snapshot of the Proxmox host.
#
# STRICTLY READ-ONLY. Every command below queries; none of them modify. Run it
# before and after any change to see exactly what moved:
#
#     ./scripts/host-state.sh > /tmp/before.txt
#     # ... apply a change ...
#     ./scripts/host-state.sh > /tmp/after.txt
#     diff -u /tmp/before.txt /tmp/after.txt
#
# The sections cover everything this project touches: hardware and storage,
# the LVM-thin pool, APT sources, networking, guests, the access plane
# (pools/roles/users/tokens/ACLs), the firewall, and SSH exposure.
#
# Usage:  ./scripts/host-state.sh [ssh-target]        (default: pvelab)

set -uo pipefail

TARGET="${1:-pvelab}"

# Absolute paths: pveum is in /usr/sbin, pvesh in /usr/bin, and a
# non-interactive shell does not always compose PATH the same way.
readonly PVESH=/usr/bin/pvesh

remote() {
    # shellcheck disable=SC2029  # deliberate client-side expansion of $1
    ssh -o BatchMode=yes -o ConnectTimeout=15 "$TARGET" "$1" 2>&1
}

section() {
    printf '\n═══════════════════════════════════════════════════════════════\n'
    printf '  %s\n' "$1"
    printf '═══════════════════════════════════════════════════════════════\n'
}

printf 'Proxmox host state snapshot\n'
printf 'target : %s\n' "$TARGET"
printf 'taken  : %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

section "IDENTITY & VERSION"
remote 'hostname; pveversion; cat /etc/os-release | head -3; uptime'

section "CPU & MEMORY"
remote 'lscpu | grep -E "^(Model name|Socket|Core|Thread|CPU\(s\)|Virtualization)"; echo; free -h'

section "DISKS & LVM  (the binding constraint — watch Data%)"
remote 'lsblk -o NAME,SIZE,TYPE,MOUNTPOINT; echo; vgs; echo; lvs -o lv_name,vg_name,lv_size,data_percent,metadata_percent; echo; df -h / /var/lib/vz'

section "STORAGE CONFIGURATION"
remote "cat /etc/pve/storage.cfg; echo; $PVESH get /storage --output-format json"

section "APT SOURCES  (deb822 on PVE 9 — note the Enabled: fields)"
remote 'for f in /etc/apt/sources.list.d/*; do echo "### $f"; cat "$f"; echo; done'

section "NETWORK"
remote 'cat /etc/network/interfaces; echo "--- live ---"; ip -br a; echo "--- routes ---"; ip r'

section "TAILSCALE"
remote 'tailscale status; echo "--- this node ---"; tailscale ip -4'

section "GUESTS  (VMs and containers)"
remote 'qm list; echo "--- containers ---"; pct list'

section "ACCESS PLANE  (pools, roles, users, tokens, ACLs)"
# `special: 1` marks Proxmox's own built-in roles. Filtering them out leaves
# only roles this project created, which is what a diff should show.
remote "echo '--- pools ---';  $PVESH get /pools        --output-format json
        echo '--- users ---';  $PVESH get /access/users --output-format json
        echo '--- custom roles ---'
        $PVESH get /access/roles --output-format json |
          python3 -c 'import json,sys; [print(\"  \", r[\"roleid\"], \"=>\", r.get(\"privs\",\"\")) for r in json.load(sys.stdin) if not r.get(\"special\")]'
        echo '--- tokens (ansible@pve) ---'
        $PVESH get /access/users/ansible@pve/token --output-format json 2>&1 | head -5
        echo '--- ACLs ---'; $PVESH get /access/acl --output-format json"

section "FIREWALL"
remote 'echo "--- cluster ---"; cat /etc/pve/firewall/cluster.fw 2>&1
        echo "--- node ---";    cat /etc/pve/nodes/*/host.fw 2>&1
        echo "--- service ---"; systemctl is-active pve-firewall 2>&1'

section "SSH EXPOSURE  (pre-hardening baseline)"
remote 'sshd -T 2>/dev/null | grep -iE "^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|maxauthtries|allowgroups)"'

section "SECURITY SERVICES"
remote 'for s in fail2ban auditd chrony pve-firewall; do printf "  %-14s %s\n" "$s" "$(systemctl is-active $s 2>&1)"; done'

printf '\nSnapshot complete.\n'
