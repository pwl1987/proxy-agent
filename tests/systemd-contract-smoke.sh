#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local file="$1" expected="$2"
  grep -Fqx "$expected" "$ROOT/$file" || {
    echo "systemd contract mismatch: $file: missing exact line: $expected" >&2
    return 1
  }
}

for unit in "$ROOT"/systemd/*.service "$ROOT"/systemd/*.timer "$ROOT"/systemd-user/*.service "$ROOT"/systemd-user/*.timer; do
  grep -Eq '^\[(Unit|Service|Timer|Install)\]$' "$unit" || {
    echo "systemd contract mismatch: invalid section header: $unit" >&2
    exit 1
  }
done

assert_contains systemd/proxy-agent.service 'Type=simple'
assert_contains systemd/proxy-agent.service 'ExecStartPre=/bin/bash @PREFIX@/bin/proxy-agent-reconcile --bootstrap'
assert_contains systemd/proxy-agent.service 'ExecStart=/bin/bash @PREFIX@/bin/proxy-ctl run'
assert_contains systemd/proxy-agent.service 'Environment=PA_CONFIG=/run/proxy-agent/runtime/proxy-agent.conf'
assert_contains systemd/proxy-agent.service 'Environment=PA_BOOTSTRAP_CONFIG=/etc/proxy-agent/proxy-agent.conf'
assert_contains systemd/proxy-agent.service 'User=@SERVICE_USER@'
assert_contains systemd/proxy-agent.service 'Group=@SERVICE_GROUP@'
assert_contains systemd/proxy-agent.service 'NoNewPrivileges=true'
assert_contains systemd/proxy-agent.service 'ProtectSystem=strict'
assert_contains systemd/proxy-agent.service 'ProtectHome=read-only'

assert_contains systemd/proxy-agent@.service 'Type=simple'
assert_contains systemd/proxy-agent@.service 'Environment=PA_PROFILE=%i'
assert_contains systemd/proxy-agent@.service 'Environment=PA_STATE_DIR=/run/proxy-agent/%i'
assert_contains systemd/proxy-agent@.service 'Environment=PA_CONFIG=/run/proxy-agent/%i/runtime/proxy-agent.conf'
assert_contains systemd/proxy-agent@.service 'Environment=PA_BOOTSTRAP_CONFIG=/etc/proxy-agent/profiles/%i.conf'
assert_contains systemd/proxy-agent@.service 'ExecStartPre=/bin/bash @PREFIX@/bin/proxy-agent-reconcile --bootstrap'
assert_contains systemd/proxy-agent@.service 'ExecStart=/bin/bash @PREFIX@/bin/proxy-ctl --profile %i run'
assert_contains systemd/proxy-agent@.service 'User=@SERVICE_USER@'

assert_contains systemd/proxy-agent-api.service 'Type=simple'
assert_contains systemd/proxy-agent-api.service 'ExecStart=/usr/bin/python3 @PREFIX@/bin/proxy-agent-api-auth --socket /run/proxy-agent/control.sock'
assert_contains systemd/proxy-agent-api.service 'Environment=PA_STATE_DIR=/run/proxy-agent'
assert_contains systemd/proxy-agent-api.service 'Environment=PA_CONFIG=/etc/proxy-agent/proxy-agent.conf'
assert_contains systemd/proxy-agent-api.service 'User=@SERVICE_USER@'
assert_contains systemd/proxy-agent-api.service 'Group=@SERVICE_GROUP@'
assert_contains systemd/proxy-agent-api.service 'NoNewPrivileges=true'
assert_contains systemd/proxy-agent-api.service 'ProtectSystem=strict'
assert_contains systemd/proxy-agent-api.service 'ProtectHome=read-only'

assert_contains systemd/proxy-agent-health.service 'User=@SERVICE_USER@'
assert_contains systemd/proxy-agent-health@.service 'User=@SERVICE_USER@'
assert_contains systemd/proxy-agent-health@.service 'Requires=proxy-agent@%i.service'
assert_contains systemd/proxy-agent-health@.service 'ExecStart=/bin/bash @PREFIX@/bin/proxy-agent-health --profile %i'

assert_contains systemd/proxy-agent-reconcile.service 'Type=oneshot'
assert_contains systemd/proxy-agent-reconcile.service 'ExecStart=/bin/bash @PREFIX@/bin/proxy-agent-reconcile'
assert_contains systemd/proxy-agent-reconcile.service 'User=@SERVICE_USER@'
assert_contains systemd/proxy-agent-reconcile.service 'Environment=PA_STATE_DIR=/run/proxy-agent'
assert_contains systemd/proxy-agent-reconcile.timer 'Unit=proxy-agent-reconcile.service'
assert_contains systemd/proxy-agent-reconcile.timer 'OnUnitActiveSec=30s'

assert_contains systemd-user/proxy-agent.service 'Type=simple'
assert_contains systemd-user/proxy-agent.service 'ExecStart=@BIN@/proxy-ctl run'
assert_contains systemd-user/proxy-agent.service 'Environment=PA_STATE_DIR=%t/proxy-agent/run'
assert_contains systemd-user/proxy-agent.service 'Environment=PA_LOG_DIR=%t/proxy-agent/log'
assert_contains systemd-user/proxy-agent.service 'ProtectHome=read-only'

assert_contains systemd-user/proxy-agent@.service 'ExecStart=@BIN@/proxy-ctl --profile %i run'
assert_contains systemd-user/proxy-agent@.service 'Environment=PA_STATE_DIR=%t/proxy-agent/run/%i'

assert_contains systemd-user/proxy-agent-health@.service 'ExecStart=@BIN@/proxy-agent-health --profile %i'
assert_contains systemd-user/proxy-agent-health@.timer 'Unit=proxy-agent-health@%i.service'

echo 'systemd contract smoke: PASS'
