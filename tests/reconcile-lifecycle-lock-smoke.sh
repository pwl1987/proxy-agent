#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STATE="$TMP/state"
LOG="$TMP/log"
CONFIG="$TMP/proxy-agent.conf"
mkdir -p "$STATE" "$LOG"

cat >"$CONFIG" <<'EOF'
BACKEND=local-endpoint
LOCAL_PROXY_URL=socks5://192.0.2.1:1080
SOCKS_BIND=127.0.0.1
SOCKS_PORT=1080
HTTP_ENABLED=false
HTTP_BIND=127.0.0.1
HTTP_PORT=8118
HEALTH_NETWORK_REQUIRED=false
HEALTH_TIMEOUT=1
HEALTH_RETRIES=0
HEALTH_BACKOFF=0
HEALTH_AUTO_RECOVER=true
SSH_STRICT_HOST_KEY_CHECKING=yes
INTEGRATE_GIT=false
INTEGRATE_DOCKER=false
INTEGRATE_PIP=false
INTEGRATE_NPM=false
EOF
chmod 0600 "$CONFIG"

export PA_CONFIG="$CONFIG"
export PA_STATE_DIR="$STATE"
export PA_LOG_DIR="$LOG"

# Bootstrap the canonical desired revision, then activate through the real
# reconciler. Before the lifecycle-FD handoff fix, this second command deadlocked
# because reconciler held the lock while proxy-ctl opened the same lock again.
timeout 8s bash "$ROOT/bin/proxy-agent-reconcile" --bootstrap
timeout 8s bash "$ROOT/bin/proxy-agent-reconcile" --activate --revision 1 >/"$TMP/result.json"

grep -q '"status":"activated"' "$TMP/result.json"
grep -q '"desired_revision":1' "$TMP/result.json"
test -s "$STATE/runtime/runtime.json"
test -s "$STATE/runtime/reconcile-state.json"

# A direct CLI operation must still acquire the same lock after reconciliation.
bash "$ROOT/bin/proxy-ctl" stop >/dev/null

echo 'reconciler lifecycle lock smoke: PASS'
