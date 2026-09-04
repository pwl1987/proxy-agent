#!/usr/bin/env bash
set -euo pipefail

revision_dir() {
  printf '%s/revisions' "$PA_STATE_DIR"
}

revision_head_file() {
  printf '%s/head' "$(revision_dir)"
}

revision_lock_dir() {
  printf '%s/.revision.lock' "$PA_STATE_DIR"
}

revision_next_id() {
  local current=0
  if [[ -r "$(revision_head_file)" ]]; then
    current="$(cat "$(revision_head_file)")"
  fi
  [[ "$current" =~ ^[0-9]+$ ]] || current=0
  printf '%d' "$((current + 1))"
}

revision_init() {
  mkdir -p "$(revision_dir)"
  if [[ ! -e "$(revision_head_file)" ]]; then
    printf '0\n' >"$(revision_head_file)"
  fi
}

revision_file() {
  printf '%s/%010d.json' "$(revision_dir)" "$1"
}

revision_current() {
  revision_init
  cat "$(revision_head_file)"
}

revision_record() {
  local config_json="$1" actor="${2:-local}" summary="${3:-configuration change}" validation="${4:-passed}" health="${5:-pending}"
  revision_init
  local id="$(revision_next_id)" timestamp file tmp previous
  previous="$(revision_current)"
  timestamp="$(date +%s)"
  file="$(revision_file "$id")"
  tmp="${file}.tmp.$$"
  python3 - "$config_json" "$actor" "$summary" "$validation" "$health" "$id" "$previous" "$timestamp" >"$tmp" <<'PY'
import json
import sys

config = json.loads(sys.argv[1])
payload = {
    "schema_version": 1,
    "revision": int(sys.argv[6]),
    "previous_revision": int(sys.argv[7]),
    "timestamp": int(sys.argv[8]),
    "actor": sys.argv[2],
    "change_summary": sys.argv[3],
    "validation_result": sys.argv[4],
    "health_result": sys.argv[5],
    "config": config,
}
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
PY
  mv -f "$tmp" "$file"
  printf '%s\n' "$id" >"$(revision_head_file)"
  printf '%s' "$id"
}

revision_get() {
  local id="$1" file
  [[ "$id" =~ ^[0-9]+$ ]] || return 1
  file="$(revision_file "$id")"
  [[ -r "$file" ]] || return 1
  cat "$file"
}

revision_list() {
  revision_init
  find "$(revision_dir)" -maxdepth 1 -type f -name '[0-9]*.json' -printf '%f\n' | sort -r
}
