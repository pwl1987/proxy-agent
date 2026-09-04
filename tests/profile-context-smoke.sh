#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROFILE_DIR="$TMP/profiles"
BASE_STATE="$TMP/state"
BASE_LOG="$TMP/log"
mkdir -p "$PROFILE_DIR" "$BASE_STATE" "$BASE_LOG"

cat >"$PROFILE_DIR/alpha.conf" <<EOF
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
LOCAL_PROXY_STATUS_TARGET="https://example.com"
PA_STATE_DIR="$BASE_STATE"
PA_LOG_DIR="$BASE_LOG"
EOF
chmod 0600 "$PROFILE_DIR/alpha.conf"

cat >"$PROFILE_DIR/beta.conf" <<EOF
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3129"
LOCAL_PROXY_STATUS_TARGET="https://example.com"
EOF
chmod 0600 "$PROFILE_DIR/beta.conf"

check_explicit_context() {
  PA_PROFILE_DIR="$PROFILE_DIR" PA_STATE_DIR="$BASE_STATE" PA_LOG_DIR="$BASE_LOG" \
    bash -c '
      source "$1/lib/common.sh"
      source "$1/lib/profile.sh"
      source "$1/lib/profile-context.sh"
      profile_apply_context alpha
      printf "%s\n%s\n%s\n%s\n" "$PA_PROFILE" "$PA_CONFIG" "$PA_STATE_DIR" "$PA_LOG_DIR"
    ' _ "$ROOT" >"$TMP/alpha.out"
  mapfile -t values <"$TMP/alpha.out"
  [[ "${values[0]}" == alpha ]]
  [[ "${values[1]}" == "$PROFILE_DIR/alpha.conf" ]]
  [[ "${values[2]}" == "$BASE_STATE" ]]
  [[ "${values[3]}" == "$BASE_LOG" ]]
}

check_default_context() {
  local expected_state expected_log
  if (( EUID == 0 )); then
    expected_state="/run/proxy-agent/beta"
    expected_log="/var/log/proxy-agent/beta"
  else
    expected_state="${XDG_RUNTIME_DIR:-$HOME/.cache/proxy-agent}/run/beta"
    expected_log="${XDG_STATE_HOME:-$HOME/.local/state}/proxy-agent/log/beta"
  fi
  PA_PROFILE_DIR="$PROFILE_DIR" env -u PA_STATE_DIR -u PA_LOG_DIR -u PA_CONFIG \
    bash -c '
      source "$1/lib/common.sh"
      source "$1/lib/profile.sh"
      source "$1/lib/profile-context.sh"
      profile_apply_context beta
      printf "%s\n%s\n%s\n%s\n" "$PA_PROFILE" "$PA_CONFIG" "$PA_STATE_DIR" "$PA_LOG_DIR"
    ' _ "$ROOT" >"$TMP/beta.out"
  mapfile -t values <"$TMP/beta.out"
  [[ "${values[0]}" == beta ]]
  [[ "${values[1]}" == "$PROFILE_DIR/beta.conf" ]]
  [[ "${values[2]}" == "$expected_state" ]]
  [[ "${values[3]}" == "$expected_log" ]]
}

check_explicit_context
check_default_context

printf 'profile context smoke: PASS\n'
