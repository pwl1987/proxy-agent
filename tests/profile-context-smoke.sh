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

check_context() {
  local name="$1" expected_state="$2" expected_log="$3" expected_config="$4"
  PA_PROFILE_DIR="$PROFILE_DIR" PA_STATE_DIR="$BASE_STATE" PA_LOG_DIR="$BASE_LOG" \
    bash -c '
      source "$1/lib/common.sh"
      source "$1/lib/profile.sh"
      source "$1/lib/profile-context.sh"
      profile_apply_context "$2"
      printf "%s\n%s\n%s\n%s\n" "$PA_PROFILE" "$PA_CONFIG" "$PA_STATE_DIR" "$PA_LOG_DIR"
    ' _ "$ROOT" "$name" >"$TMP/$name.out"
  mapfile -t values <"$TMP/$name.out"
  [[ "${values[0]}" == "$name" ]]
  [[ "${values[1]}" == "$expected_config" ]]
  [[ "${values[2]}" == "$expected_state" ]]
  [[ "${values[3]}" == "$expected_log" ]]
}

check_context alpha "$BASE_STATE" "$BASE_LOG" "$PROFILE_DIR/alpha.conf"
# Explicit PA_STATE_DIR/PA_LOG_DIR in the profile must not receive a profile suffix.
check_context beta "$BASE_STATE/beta" "$BASE_LOG/beta" "$PROFILE_DIR/beta.conf"

printf 'profile context smoke: PASS\n'
