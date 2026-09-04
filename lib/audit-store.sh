#!/usr/bin/env bash
set -euo pipefail

audit_dir() { printf '%s/audit' "$PA_STATE_DIR"; }
audit_file() { printf '%s/events.jsonl' "$(audit_dir)"; }
audit_lock_dir() { printf '%s/.audit.lock' "$(audit_dir)"; }

audit_lock_acquire() {
  local dir="$(audit_dir)" lock="$(audit_lock_dir)"
  mkdir -p "$dir"
  for _ in {1..100}; do
    if mkdir "$lock" 2>/dev/null; then
      printf '%s\n' "$$" >"$lock/pid"
      return 0
    fi
    if [[ -r "$lock/pid" ]]; then
      local pid
      pid="$(cat "$lock/pid" 2>/dev/null || true)"
      if [[ ! "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
        rm -rf "$lock"
        continue
      fi
    else
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
import json
import sys
json.loads(sys.argv[1])
PY
  audit_lock_acquire
  if ! printf '%s\n' "$event" >>"$(audit_file)"; then
    audit_lock_release
    return 1
  fi
  audit_lock_release
}

audit_list() {
  if [[ -r "$(audit_file)" ]]; then cat "$(audit_file)"; fi
}
