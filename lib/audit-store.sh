#!/usr/bin/env bash
set -euo pipefail

audit_dir() { printf '%s/audit' "$PA_STATE_DIR"; }
audit_file() { printf '%s/events.jsonl' "$(audit_dir)"; }
audit_lock_dir() { printf '%s/.audit.lock' "$(audit_dir)"; }
audit_owner_pid() { printf '%s' "${BASHPID:-$$}"; }
audit_proc_starttime() {
  local pid="$1"
  [[ -r "/proc/$pid/stat" ]] || return 1
  awk '{print $22}' "/proc/$pid/stat"
}
audit_lock_is_stale() {
  local lock="$(audit_lock_dir)" pid start created now current
  [[ -d "$lock" ]] || return 1
  pid="$(cat "$lock/pid" 2>/dev/null || true)"
  start="$(cat "$lock/starttime" 2>/dev/null || true)"
  created="$(cat "$lock/created" 2>/dev/null || true)"
  now="$(date +%s)"
  if [[ -z "$pid" || -z "$start" ]]; then
    [[ "$created" =~ ^[0-9]+$ ]] && (( now - created > 30 ))
    return
  fi
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  if ! current="$(audit_proc_starttime "$pid" 2>/dev/null)"; then return 0; fi
  [[ "$current" != "$start" ]]
}
audit_lock_reclaim() {
  local lock="$(audit_lock_dir)" guard="$(audit_lock_dir).reclaim" stale="${lock}.stale.$(audit_owner_pid).$RANDOM" guard_created guard_now
  if ! mkdir "$guard" 2>/dev/null; then
    guard_created="$(stat -c %Y "$guard" 2>/dev/null || true)"
    guard_now="$(date +%s)"
    if [[ "$guard_created" =~ ^[0-9]+$ ]] && (( guard_now - guard_created > 30 )); then
      rm -rf "$guard" 2>/dev/null || true
    else
      return 1
    fi
    mkdir "$guard" 2>/dev/null || return 1
  fi
  if audit_lock_is_stale; then
    if mv "$lock" "$stale" 2>/dev/null; then
      rm -rf "$stale"
      rm -rf "$guard" 2>/dev/null || true
      return 0
    fi
  fi
  rm -rf "$guard" 2>/dev/null || true
  return 1
}
audit_lock_acquire() {
  local dir="$(audit_dir)" lock="$(audit_lock_dir)" now pid
  mkdir -p "$dir"
  for _ in {1..100}; do
    if mkdir "$lock" 2>/dev/null; then
      now="$(date +%s)"
      pid="${BASHPID:-$$}"
      printf '%s\n' "$pid" >"$lock/pid"
      printf '%s\n' "$(audit_proc_starttime "$pid" 2>/dev/null || printf 0)" >"$lock/starttime"
      printf '%s\n' "$now" >"$lock/created"
      return 0
    fi
    if audit_lock_is_stale; then
      audit_lock_reclaim || true
      continue
    fi
    sleep 0.05
  done
  printf 'audit store is locked: %s\n' "$lock" >&2
  return 1
}
audit_lock_release() {
  local lock="$(audit_lock_dir)" pid start current owner
  [[ -d "$lock" ]] || return 0
  owner="${BASHPID:-$$}"
  pid="$(cat "$lock/pid" 2>/dev/null || true)"
  start="$(cat "$lock/starttime" 2>/dev/null || true)"
  current="$(audit_proc_starttime "$owner" 2>/dev/null || true)"
  [[ "$pid" == "$owner" && -n "$start" && "$start" == "$current" ]] || return 1
  rm -rf "$lock"
}
audit_append() {
  local event="${1:?event JSON required}"
  python3 - "$event" <<'PY'
import json, sys
json.loads(sys.argv[1])
PY
  audit_lock_acquire
  if ! printf '%s\n' "$event" >>"$(audit_file)"; then audit_lock_release; return 1; fi
  audit_lock_release
}
audit_list() { if [[ -r "$(audit_file)" ]]; then cat "$(audit_file)"; fi; }
