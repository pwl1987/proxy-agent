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
assert_contains systemd/proxy-agent.service 'ExecStart=/bin/bash @PREFIX@/bin/proxy-ctl run'
assert_contains systemd/proxy-agent.service 'User=@SERVICE_USER@'
assert_contains systemd/proxy-agent.service 'Group=@SERVICE_GROUP@'
assert_contains systemd/proxy-agent.service 'NoNewPrivileges=true'
assert_contains systemd/proxy-agent.service 'ProtectSystem=strict'
assert_contains systemd/proxy-agent.service 'ProtectHome=read-only'

assert_contains systemd/proxy-agent@.service 'Type=simple'
assert_contains systemd/proxy-agent@.service 'ExecStart=/bin/bash @PREFIX@/bin/proxy-ctl --profile %i run'
assert_contains systemd/proxy-agent@.service 'User=@SERVICE_USER@'

assert_contains systemd/proxy-agent-health.service 'User=@SERVICE_USER@'
assert_contains systemd/proxy-agent-health@.service 'User=@SERVICE_USER@'
assert_contains systemd/proxy-agent-health@.service 'Requires=proxy-agent@%i.service'
assert_contains systemd/proxy-agent-health@.service 'ExecStart=/bin/bash @PREFIX@/bin/proxy-agent-health --profile %i'

assert_contains systemd-user/proxy-agent.service 'Type=simple'
assert_contains systemd-user/proxy-agent.service 'ExecStart=@BIN@/proxy-ctl run'
assert_contains systemd-user/proxy-agent.service 'Environment=PA_STATE_DIR=%t/proxy-agent/run'
assert_contains systemd-user/proxy-agent.service 'Environment=PA_LOG_DIR=%t/proxy-agent/log'
assert_contains systemd-user/proxy-agent.service 'ProtectHome=read-only'

assert_contains systemd-user/proxy-agent@.service 'ExecStart=@BIN@/proxy-ctl --profile %i run'
assert_contains systemd-user/proxy-agent@.service 'Environment=PA_STATE_DIR=%t/proxy-agent/run/%i'

assert_contains systemd-user/proxy-agent-health@.service 'ExecStart=@BIN@/proxy-agent-health --profile %i'
assert_contains systemd-user/proxy-agent-health@.timer 'Unit=proxy-agent-health@%i.service'

printf 'systemd contract smoke: PASS\n'
