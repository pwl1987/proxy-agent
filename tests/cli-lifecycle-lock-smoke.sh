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

run_pair() {
  local label="$1" first_cmd="$2" second_cmd="$3" a_rc b_rc
  set +e
  ( "$TMP/bin/proxy-ctl" $first_cmd ) >"$TMP/${label}-a.log" 2>&1 & pid_a=$!
  sleep 0.03
  ( "$TMP/bin/proxy-ctl" $second_cmd ) >"$TMP/${label}-b.log" 2>&1 & pid_b=$!
  wait "$pid_a"; a_rc=$?
  wait "$pid_b"; b_rc=$?
  set -e
  if (( a_rc != 0 || b_rc != 0 )); then
    echo "${label}: first_rc=${a_rc} second_rc=${b_rc}" >&2
    cat "$TMP/${label}-a.log" >&2 || true
    cat "$TMP/${label}-b.log" >&2 || true
    return 1
  fi
}

run_pair plain start start
[[ -f "$STATE/.lifecycle.lock" ]] || { echo 'plain lifecycle lock file missing' >&2; exit 1; }

run_pair profile '--profile demo start' '--profile demo start'
[[ -f "$STATE/demo/.lifecycle.lock" ]] || { echo 'profile lifecycle lock file missing' >&2; exit 1; }

rm -f "$STATE/.lifecycle.lock"
"$TMP/bin/proxy-ctl" status >/dev/null
[[ ! -e "$STATE/.lifecycle.lock" ]] || { echo 'read-only status unexpectedly created lifecycle lock' >&2; exit 1; }

echo 'cli lifecycle lock smoke: PASS'
