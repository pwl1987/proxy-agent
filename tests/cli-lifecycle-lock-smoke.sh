#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
run_pid=''
cleanup() {
  if [[ -n "$run_pid" ]]; then
    kill -KILL -- "-$run_pid" 2>/dev/null || true
    wait "$run_pid" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

cp -a "$ROOT/lib" "$TMP/lib"
cp -a "$ROOT/adapters" "$TMP/adapters"
cp -a "$ROOT/backends" "$TMP/backends"
mkdir -p "$TMP/bin"
cp "$ROOT/bin/proxy-ctl" "$TMP/bin/proxy-ctl"
chmod 0755 "$TMP/bin/proxy-ctl"

XDG_RUNTIME_DIR="$TMP/xdg"
STATE="$XDG_RUNTIME_DIR/run"
CONFIG="$TMP/proxy-agent.conf"
PROFILES="$TMP/profiles"
mkdir -p "$STATE" "$PROFILES" "$XDG_RUNTIME_DIR"

cat >"$CONFIG" <<EOF
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
cp "$CONFIG" "$PROFILES/demo.conf"
chmod 0600 "$PROFILES/demo.conf"

export PA_CONFIG="$CONFIG"
unset PA_STATE_DIR PA_STATE_DIR_EXPLICIT
export XDG_RUNTIME_DIR
export PA_PROFILE_DIR="$PROFILES"

assert_blocked() {
  local label="$1"
  shift
  set +e
  timeout --signal=TERM --kill-after=1s 1s "$TMP/bin/proxy-ctl" "$@" >"$TMP/${label}.log" 2>&1
  local rc=$?
  set -e
  if (( rc != 124 )); then
    echo "$label lifecycle command was not blocked (rc=$rc)" >&2
    cat "$TMP/${label}.log" >&2 || true
    return 1
  fi
}

bounded() {
  local label="$1"
  shift
  timeout --signal=TERM --kill-after=1s 5s "$@" >"$TMP/${label}.log" 2>&1
}

wait_group_exit() {
  local pid="$1" state
  for _ in {1..40}; do
    state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    if [[ -z "$state" || "$state" == Z* ]]; then
      wait "$pid" 2>/dev/null || true
      return 0
    fi
    sleep 0.05
  done
  echo "process group leader $pid did not terminate (state=$state)" >&2
  return 1
}

setsid "$TMP/bin/proxy-ctl" run >"$TMP/run.log" 2>&1 & run_pid=$!
sleep 0.15
[[ -f "$STATE/.lifecycle.lock" ]] || { echo 'run did not create lifecycle lock' >&2; cat "$TMP/run.log" >&2 || true; env | grep -E '^(PA_|XDG_RUNTIME_DIR=)' >&2 || true; exit 1; }
assert_blocked plain-start start

kill -KILL -- "-$run_pid" 2>/dev/null || true
wait_group_exit "$run_pid"
run_pid=''

bounded recovered-start "$TMP/bin/proxy-ctl" start
bounded recovered-restart "$TMP/bin/proxy-ctl" restart
bounded recovered-stop "$TMP/bin/proxy-ctl" stop

setsid "$TMP/bin/proxy-ctl" --profile demo run >"$TMP/profile-run.log" 2>&1 & run_pid=$!
sleep 0.15
[[ -f "$STATE/demo/.lifecycle.lock" ]] || { echo 'profile run did not use profile runtime lifecycle lock' >&2; cat "$TMP/profile-run.log" >&2 || true; exit 1; }
assert_blocked profile-stop --profile demo stop
kill -KILL -- "-$run_pid" 2>/dev/null || true
wait_group_exit "$run_pid"
run_pid=''
bounded profile-recovered-stop "$TMP/bin/proxy-ctl" --profile demo stop

rm -f "$STATE/.lifecycle.lock" "$STATE/demo/.lifecycle.lock"
bounded status "$TMP/bin/proxy-ctl" status >/dev/null
[[ ! -e "$STATE/.lifecycle.lock" ]] || { echo 'read-only status unexpectedly created lifecycle lock' >&2; exit 1; }
[[ ! -e "$STATE/demo/.lifecycle.lock" ]] || { echo 'read-only profile status unexpectedly created lifecycle lock' >&2; exit 1; }

echo 'cli lifecycle lock smoke: PASS'
