#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PA_STATE_DIR="$TMP/state"
mkdir -p "$PA_STATE_DIR"
source "$ROOT/lib/audit-store.sh"

event='{"event":"test","ok":true}'
audit_append "$event"
[[ "$(audit_list)" == "$event" ]]

lock="$(audit_lock_dir)"
mkdir -p "$lock"
if audit_lock_is_stale; then
  echo 'fresh ownerless audit lock incorrectly marked stale' >&2; exit 1
fi
printf '%s\n' "$(( $(date +%s) - 31 ))" >"$lock/created"
if ! audit_lock_is_stale; then
  echo 'old ownerless audit lock was not marked stale' >&2; exit 1
fi
rm -rf "$lock"

mkdir -p "$lock"
printf '%s\n' "$$" >"$lock/pid"
printf '%s\n' "$(audit_proc_starttime "$$")" >"$lock/starttime"
printf '%s\n' "$(date +%s)" >"$lock/created"
if audit_lock_is_stale; then
  echo 'live audit lock incorrectly marked stale' >&2; exit 1
fi
printf '%s\n' 1 >"$lock/starttime"
if ! audit_lock_is_stale; then
  echo 'PID-reused audit lock was not marked stale' >&2; exit 1
fi
rm -rf "$lock"

echo 'audit lock smoke: PASS'