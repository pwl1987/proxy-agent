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

inotifywait -m -e create,open,close_write,moved_to,delete,attrib --format '%T|%e|%w%f' --timefmt '%s.%N' "$TMP" >"$TMP/inotify.log" 2>"$TMP/inotify.err" &
WATCH_PID=$!

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" env -i PATH="$PATH" HOME="$HOME" PA_CONFIG="$CONFIG" PA_API_SOCKET="$SOCKET" PA_STATE_DIR="$TMP/state" PA_LOG_DIR="$TMP/log" /usr/bin/python3 "$ROOT/bin/proxy-agent-api" --socket "$SOCKET" >"$TMP/api.out" 2>"$TMP/api.err" &
PID=$!
for _ in {1..100}; do [[ -S "$SOCKET" ]] && break; sleep 0.05; done
[[ -S "$SOCKET" ]]

PA_STATE_DIR="$TMP/state" bash -c 'source "$1"; printf "initial current=%s desired=%s\n" "$(revision_current)" "$(revision_desired_revision)"' _ "$ROOT/lib/revision-store.sh"

printf '%s\n' '=== health ==='
curl --silent --show-error --fail --unix-socket "$SOCKET" http://localhost/api/v1/health >"$TMP/health.json"
cat "$TMP/health.json"
stat -c 'after health: inode=%i size=%s mtime=%Y sha=%n' "$TMP/health.json"
sha256sum "$TMP/health.json"

for spec in 'status:/api/v1/status' 'capabilities:/api/v1/capabilities' 'config:/api/v1/config' 'revisions:/api/v1/revisions' 'metrics:/api/v1/metrics'; do
  name="${spec%%:*}"; path="${spec#*:}"
  printf '%s\n' "=== $name ==="
  curl --silent --show-error --fail --unix-socket "$SOCKET" "http://localhost$path" >"$TMP/$name.json"
  stat -c "after $name: health_inode=%i health_size=%s health_mtime=%Y" "$TMP/health.json"
  sha256sum "$TMP/health.json"
  case "$name" in
    status|capabilities|config|revisions|metrics) cat "$TMP/$name.json" ;;
  esac
  printf '%s\n' '--- health now ---'
  cat "$TMP/health.json"
  printf '%s\n' '--- state revision files ---'
  find "$TMP/state/revisions" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
  for f in "$TMP/state/revisions"/*; do [[ -f "$f" ]] || continue; printf '%s: ' "$(basename "$f")"; cat "$f"; done
  printf '\n'
done

printf '%s\n' '=== filesystem events ==='
cat "$TMP/inotify.log" 2>/dev/null || true
printf '%s\n' '=== API STDERR ==='
cat "$TMP/api.err"
printf '%s\n' '=== PROCESSES ==='
ps -eo pid,ppid,args | grep -E 'proxy-agent-api|proxy-agent-reconcile|proxy-ctl' | grep -v grep || true
exit 0
