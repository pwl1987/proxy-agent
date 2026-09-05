#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -a "$ROOT/lib" "$TMP/lib"
cp -a "$ROOT/adapters" "$TMP/adapters"
cp -a "$ROOT/backends" "$TMP/backends"
mkdir -p "$TMP/bin"
cp "$ROOT/bin/proxy-ctl" "$TMP/bin/proxy-ctl"
chmod 0755 "$TMP/bin/proxy-ctl"

STATE="$TMP/state"
CONFIG="$TMP/proxy-agent.conf"
PROFILES="$TMP/profiles"
mkdir -p "$STATE" "$PROFILES"

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
export PA_STATE_DIR="$STATE"
export PA_PROFILE_DIR="$PROFILES"

probe_blocking() {
  local label="$1" command_line="$2"
  ( "$TMP/bin/proxy-ctl" $command_line ) >"$TMP/${label}.log" 2>&1 &
  PROBE_PID=$!
  sleep 0.15
  if ! kill -0 "$PROBE_PID" 2>/dev/null; then
    echo "$label lifecycle command did not block behind run" >&2
    cat "$TMP/${label}.log" >&2 || true
    return 1
  fi
}

"$TMP/bin/proxy-ctl" run >"$TMP/run.log" 2>&1 & run_pid=$!
sleep 0.15
[[ -f "$STATE/.lifecycle.lock" ]] || { echo 'run did not create lifecycle lock' >&2; exit 1; }

probe_blocking start start
start_pid="$PROBE_PID"
kill -TERM "$run_pid" 2>/dev/null || true
sleep 0.15
kill -KILL "$run_pid" 2>/dev/null || true
wait "$run_pid" 2>/dev/null || true
wait "$start_pid" || {
  echo 'blocked start did not complete after run released lifecycle lock' >&2
  cat "$TMP/start.log" >&2 || true
  exit 1
}

[[ -f "$STATE/.lifecycle.lock" ]] || { echo 'lifecycle lock file missing after start' >&2; exit 1; }
"$TMP/bin/proxy-ctl" restart >/dev/null
"$TMP/bin/proxy-ctl" stop >/dev/null

"$TMP/bin/proxy-ctl" --profile demo run >"$TMP/profile-run.log" 2>&1 & profile_run_pid=$!
sleep 0.15
[[ -f "$STATE/.lifecycle.lock" ]] || { echo 'profile run did not use explicit runtime lifecycle lock' >&2; exit 1; }

probe_blocking profile-stop '--profile demo stop'
stop_pid="$PROBE_PID"
kill -KILL "$profile_run_pid" 2>/dev/null || true
wait "$profile_run_pid" 2>/dev/null || true
wait "$stop_pid" || {
  echo 'blocked profile stop did not complete after run release' >&2
  cat "$TMP/profile-stop.log" >&2 || true
  exit 1
}

rm -f "$STATE/.lifecycle.lock"
"$TMP/bin/proxy-ctl" status >/dev/null
[[ ! -e "$STATE/.lifecycle.lock" ]] || { echo 'read-only status unexpectedly created lifecycle lock' >&2; exit 1; }

echo 'cli lifecycle lock smoke: PASS'
