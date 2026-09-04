#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/config" <<'EOF'
BACKEND="ssh-socks"
REMOTE_HOST="proxy.example.com"
REMOTE_USER="proxy"
REMOTE_PORT="22"
REMOTE_SSH_KEY="~/.ssh/id_ed25519"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
DIRECT_CIDRS="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
DIRECT_DOMAINS="localhost,.local,.cn"
NO_PROXY_EXTRA="internal.example"
HEALTH_TIMEOUT="1"
EOF

run() { PA_CONFIG="$TMP/config" bash "$ROOT/bin/proxy-ctl" "$@"; }

test -x "$ROOT/bin/proxy-ctl" || test -f "$ROOT/bin/proxy-ctl"
bash -n "$ROOT/bin/proxy-ctl"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/adapters/privoxy.sh"
bash -n "$ROOT/backends/ssh-socks.sh"
bash -n "$ROOT/lib/common.sh"

[[ "$(run route example.cn)" == DIRECT* ]]
[[ "$(run route foo.local)" == DIRECT* ]]
[[ "$(run route 10.12.34.56)" == DIRECT* ]]
[[ "$(run route 8.8.8.8)" == PROXY* ]]
[[ "$(run env | grep -c '^unset HTTP_PROXY')" -eq 1 ]]
[[ "$(run env | grep -c '^export ALL_PROXY=')" -eq 1 ]]
! run doctor

echo 'PASS smoke tests'
