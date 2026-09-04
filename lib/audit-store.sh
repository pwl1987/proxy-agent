#!/usr/bin/env bash
set -euo pipefail

audit_dir() { printf '%s/audit' "$PA_STATE_DIR"; }
audit_file() { printf '%s/events.jsonl' "$(audit_dir)"; }
audit_lock_dir() { printf '%s/.audit.lock' "$(audit_dir)"; }
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
audit_lock_acquire() {
  local dir="$(audit_dir)" lock="$(audit_lock_dir)" now
  mkdir -p "$dir"
  for _ in {1..100}; do
    if mkdir "$lock" 2>/dev/null; then
      now="$(date +%s)"
      printf '%s\n' "$$" >"$lock/pid"
      printf '%s\n' "$(audit_proc_starttime "$$" 2>/dev/null || printf 0)" >"$lock/starttime"
      printf '%s\n' "$now" >"$lock/created"
      return 0
    fi
    if audit_lock_is_stale; then
      rm -rf "$lock"
      continue
    fi
    sleep 0.05
  done
  printf 'audit store is locked: %s\n' "$lock" >&2
  return 1
}
audit_lock_release() { rm -rf "$(audit_lock_dir)"; }
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
