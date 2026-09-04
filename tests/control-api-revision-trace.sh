#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
SOCKET="$TMP/control.sock"
CONFIG="$TMP/proxy-agent.conf"
trap '[[ -z "${PID:-}" ]] || kill "$PID" >/dev/null 2>&1 || true; [[ -z "${WATCH_PID:-}" ]] || kill "$WATCH_PID" >/dev/null 2>&1 || true; wait "$WATCH_PID" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

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

inotifywait -m -r -e create,open,close_write,moved_to,delete --format '%T|%e|%w%f' --timefmt '%s.%N' "$TMP/state" >"$TMP/inotify.log" 2>"$TMP/inotify.err" &
WATCH_PID=$!

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" env -i PATH="$PATH" HOME="$HOME" PA_CONFIG="$CONFIG" PA_API_SOCKET="$SOCKET" PA_STATE_DIR="$TMP/state" PA_LOG_DIR="$TMP/log" /usr/bin/python3 "$ROOT/bin/proxy-agent-api" --socket "$SOCKET" >"$TMP/api.out" 2>"$TMP/api.err" &
PID=$!
for _ in {1..100}; do [[ -S "$SOCKET" ]] && break; sleep 0.05; done
[[ -S "$SOCKET" ]]

curl --silent --show-error --fail --unix-socket "$SOCKET" http://localhost/api/v1/health >"$TMP/health.json"
sleep 0.2

printf '%s\n' '=== health ==='
cat "$TMP/health.json"
printf '%s\n' '=== revision tree ==='
find "$TMP/state/revisions" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
printf '%s\n' '=== revision events ==='
cat "$TMP/inotify.log"
printf '%s\n' '=== api stderr ==='
cat "$TMP/api.err"
printf '%s\n' '=== api pid ==='
ps -o pid,ppid,args -p "$PID"
printf '%s\n' '=== revision writer process snapshots ==='
while IFS='|' read -r _ event path; do
  case "$path" in
    *desired_revision*|*/revisions/[0-9]*.json)
      for p in /proc/[0-9]*; do
        pid="${p##*/}"
        [[ "$pid" == "$PID" ]] && continue
        [[ -r "$p/cmdline" ]] || continue
        cmd="$(tr '\0' ' ' <"$p/cmdline" 2>/dev/null || true)"
        [[ "$cmd" == *revision-store.sh* || "$cmd" == *proxy-agent-api* || "$cmd" == *proxy-agent-reconcile* ]] || continue
        printf '%s|%s|%s|%s\n' "$event" "$path" "$pid" "$cmd"
      done
      ;;
  esac
done <"$TMP/inotify.log"

[[ "$(python3 -c 'import json; print(json.load(open("'"$TMP/health.json"'"))["data"]["desired_revision"])')" == 1 ]]
