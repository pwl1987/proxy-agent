#!/usr/bin/env bash
set -euo pipefail

audit_dir() { printf '%s/audit' "$PA_STATE_DIR"; }
audit_file() { printf '%s/events.jsonl' "$(audit_dir)"; }

audit_append() {
  local event="${1:?event JSON required}"
  mkdir -p "$(audit_dir)"
  printf '%s\n' "$event" >>"$(audit_file)"
}

audit_list() {
  if [[ -r "$(audit_file)" ]]; then cat "$(audit_file)"; fi
}
