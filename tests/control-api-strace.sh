#!/usr/bin/env bash
set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
SOCKET="$TMP/control.sock"
CONFIG="$TMP/proxy-agent.conf"
LOCAL_PROXY_PORT="$(python3 - <<'PY'
import socket
s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
s.bind(('127.0.0.1',0))
print(s.getsockname()[1])
s.close()
PY
)"
cleanup() {
  rc=$?
  [[ -z "${PID:-}" ]] || kill "$PID" >/dev/null 2>&1 || true
  sleep 0.2
  printf '%s\n' '=== API ENV ==='
  [[ -r "${PID:-}/environ" ]] && tr '\0' '\n' <"/proc/$PID/environ" | grep '^PA_' | sort || true
  printf '%s\n' '=== STATE TREE ==='
  find "$TMP/state" -maxdepth 4 -print 2>/dev/null | sort || true
  printf '%s\n' '=== REVISION FILES ==='
  for f in "$TMP/state"/revisions/* "$TMP/state"/runtime/*; do
    [[ -f "$f" ]] || continue
    printf '%s\n' "--- $f ---"
    cat "$f"
  done
  printf '%s\n' '=== API STDERR ==='
  cat "$TMP/api.err" 2>/dev/null || true
  printf '%s\n' '=== STRACE REVISION WRITES ==='
  grep -hE 'revisions|reconcile-state|rename\(|renameat|renameat2|openat\(' "$TMP"/strace* 2>/dev/null || true
  printf '%s\n' '=== PROCESSES ==='
  ps -eo pid,ppid,args | grep -E 'proxy-agent|proxy-ctl|strace' | grep -v grep || true
  rm -rf "$TMP"
  exit "$rc"
}
trap cleanup EXIT

cat >"$CONFIG" <<EOF
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:${LOCAL_PROXY_PORT}"
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

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" env -i PATH="$PATH" HOME="$HOME" PA_CONFIG="$CONFIG" PA_API_SOCKET="$SOCKET" PA_STATE_DIR="$TMP/state" PA_LOG_DIR="$TMP/log" strace -ff -e trace=file -o "$TMP/strace" /usr/bin/python3 "$ROOT/bin/proxy-agent-api" --socket "$SOCKET" >"$TMP/api.out" 2>"$TMP/api.err" &
PID=$!
for _ in {1..100}; do [[ -S "$SOCKET" ]] && break; sleep 0.05; done
[[ -S "$SOCKET" ]]
PA_STATE_DIR="$TMP/state" bash -c 'source "$1"; printf "pre current=%s desired=%s\n" "$(revision_current)" "$(revision_desired_revision)"' _ "$ROOT/lib/revision-store.sh"
printf '%s\n' '=== HEALTH ==='
curl --silent --show-error --fail --unix-socket "$SOCKET" http://localhost/api/v1/health || true
printf '%s\n' '=== POST HEALTH SNAPSHOT ==='
find "$TMP/state" -maxdepth 4 -print 2>/dev/null | sort
for f in "$TMP/state"/revisions/* "$TMP/state"/runtime/*; do [[ -f "$f" ]] || continue; printf '%s\n' "--- $f ---"; cat "$f"; done
exit 0
