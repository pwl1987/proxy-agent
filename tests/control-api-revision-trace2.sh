#!/usr/bin/env bash
set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
SOCKET="$TMP/control.sock"
CONFIG="$TMP/proxy-agent.conf"
trap '[[ -z "${PID:-}" ]] || kill "$PID" >/dev/null 2>&1 || true; [[ -z "${WATCH_PID:-}" ]] || kill "$WATCH_PID" >/dev/null 2>&1 || true; wait "$WATCH_PID" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

cat >"$CONFIG" <<'EOF'
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
LOCAL_PROXY_STATUS_TARGET=""
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
SSH_STRICT_HOST_KEY_CHECKING="yes"
DIRECT_CIDRS="127.0.0.0/8"
DIRECT_DOMAINS="localhost"
NO_PROXY_EXTRA=""
ROUTE_RULES=""
HEALTH_TARGETS=""
HEALTH_NETWORK_REQUIRED="false"
HEALTH_TIMEOUT="10"
HEALTH_RETRIES="1"
HEALTH_BACKOFF="1"
HEALTH_AUTO_RECOVER="true"
INTEGRATE_GIT="false"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="false"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$CONFIG"
mkdir -p "$TMP/state"

inotifywait -m -r -e create,open,close_write,moved_to,delete --format '%T|%e|%w%f' --timefmt '%s.%N' "$TMP/state" >"$TMP/inotify.log" 2>"$TMP/inotify.err" &
WATCH_PID=$!

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" env -i PATH="$PATH" HOME="$HOME" PA_CONFIG="$CONFIG" PA_API_SOCKET="$SOCKET" PA_STATE_DIR="$TMP/state" PA_LOG_DIR="$TMP/log" /usr/bin/python3 "$ROOT/bin/proxy-agent-api" --socket "$SOCKET" >"$TMP/api.out" 2>"$TMP/api.err" &
PID=$!
for _ in {1..100}; do [[ -S "$SOCKET" ]] && break; sleep 0.05; done
printf '%s\n' '=== preflight before revision_current ==='
find "$TMP/state" -maxdepth 3 -print | sort
printf '%s\n' '=== initialize revision store exactly like control-api-smoke ==='
PA_STATE_DIR="$TMP/state" bash -c 'source "$1"; printf "current=%s desired=%s\n" "$(revision_current)" "$(revision_desired_revision)"' _ "$ROOT/lib/revision-store.sh"
printf '%s\n' '=== state after revision_current ==='
find "$TMP/state" -maxdepth 3 -print | sort
for f in "$TMP/state"/revisions/*; do
  [[ -f "$f" ]] || continue
  printf '%s\n' "--- $f ---"
  cat "$f"
done
printf '%s\n' '=== health request ==='
curl --silent --show-error --unix-socket "$SOCKET" -D "$TMP/headers" http://localhost/api/v1/health >"$TMP/health.json" 2>&1 || true
cat "$TMP/headers" 2>/dev/null || true
cat "$TMP/health.json" 2>/dev/null || true
sleep 0.2
printf '%s\n' '=== state after health ==='
find "$TMP/state" -maxdepth 3 -type f -printf '%P\n' 2>/dev/null | sort
for f in "$TMP/state"/revisions/* "$TMP/state"/runtime/*; do
  [[ -f "$f" ]] || continue
  printf '%s\n' "--- $f ---"
  cat "$f"
done
printf '%s\n' '=== events ==='
cat "$TMP/inotify.log" 2>/dev/null || true
printf '%s\n' '=== api stderr ==='
cat "$TMP/api.err" 2>/dev/null || true
printf '%s\n' '=== api stdout ==='
cat "$TMP/api.out" 2>/dev/null || true
printf '%s\n' '=== processes ==='
ps -eo pid,ppid,args | grep -E 'proxy-agent-api|proxy-agent-reconcile|proxy-ctl' | grep -v grep || true
exit 0
