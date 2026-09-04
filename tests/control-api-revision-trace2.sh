#!/usr/bin/env bash
set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
SOCKET="$TMP/control.sock"
CONFIG="$TMP/proxy-agent.conf"
trap '[[ -z "${PID:-}" ]] || kill "$PID" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

cat >"$CONFIG" <<'EOF'
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
LOCAL_PROXY_STATUS_TARGET="https://example.com"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
SSH_STRICT_HOST_KEY_CHECKING="yes"
DIRECT_CIDRS="127.0.0.0/8"
DIRECT_DOMAINS="localhost"
NO_PROXY_EXTRA=""
ROUTE_RULES=$'100|DIRECT|suffix|.internal.example'
HEALTH_TARGETS="https://example.com"
HEALTH_NETWORK_REQUIRED="false"
HEALTH_TIMEOUT="10"
HEALTH_RETRIES="2"
HEALTH_BACKOFF="2"
HEALTH_AUTO_RECOVER="true"
INTEGRATE_GIT="true"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="true"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$CONFIG"
mkdir -p "$TMP/state"

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" env -i PATH="$PATH" HOME="$HOME" PA_CONFIG="$CONFIG" PA_API_SOCKET="$SOCKET" PA_STATE_DIR="$TMP/state" PA_LOG_DIR="$TMP/log" /usr/bin/python3 "$ROOT/bin/proxy-agent-api" --socket "$SOCKET" >"$TMP/api.out" 2>"$TMP/api.err" &
PID=$!
for _ in {1..100}; do [[ -S "$SOCKET" ]] && break; sleep 0.05; done
[[ -S "$SOCKET" ]]

PA_STATE_DIR="$TMP/state" bash -c 'source "$1"; printf "initial current=%s desired=%s\n" "$(revision_current)" "$(revision_desired_revision)"' _ "$ROOT/lib/revision-store.sh"

call() {
  local name="$1" path="$2"
  printf '%s\n' "=== $name ==="
  curl --silent --show-error --fail --unix-socket "$SOCKET" "http://localhost$path" >"$TMP/$name.json"
  cat "$TMP/$name.json"
  printf '%s\n' '--- revisions ---'
  find "$TMP/state/revisions" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
  for f in "$TMP/state/revisions"/*; do [[ -f "$f" ]] || continue; printf '%s: ' "$(basename "$f")"; cat "$f"; done
  printf '\n'
}

call health /api/v1/health
call status /api/v1/status
call capabilities /api/v1/capabilities
call config /api/v1/config
call revisions /api/v1/revisions
call metrics /api/v1/metrics

printf '%s\n' '=== API STDERR ==='
cat "$TMP/api.err"
printf '%s\n' '=== PROCESSES ==='
ps -eo pid,ppid,args | grep -E 'proxy-agent-api|proxy-agent-reconcile|proxy-ctl' | grep -v grep || true
exit 0
