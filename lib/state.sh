#!/usr/bin/env bash
set -euo pipefail

state_dir() {
  printf '%s' "$PA_STATE_DIR"
}

state_file() {
  printf '%s/runtime.json' "$(state_dir)"
}

state_marker() {
  local name="$1"
  printf '%s/%s' "$(state_dir)" "$name"
}

state_epoch() {
  local name="$1" value
  if [[ -r "$(state_marker "$name")" ]]; then
    value="$(cat "$(state_marker "$name")" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-9]+$ ]] && { printf '%s' "$value"; return; }
  fi
  printf 'null'
}

state_set_marker() {
  local name="$1" value="${2:-$(date +%s)}"
  mkdir -p "$(state_dir)"
  printf '%s\n' "$value" >"$(state_marker "$name")"
}

state_clear_marker() {
  rm -f "$(state_marker "$1")"
}

state_json_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

state_sync() {
  local backend_state='stopped' managed='false' pid='null' identity='' endpoint='' adapter_state='disabled' adapter_type='none'
  local started_at last_transition last_healthy last_unhealthy last_recovered

  if backend_status >/dev/null 2>&1; then backend_state='ready'; fi
  if backend_managed >/dev/null 2>&1; then managed='true'; fi
  if [[ "$managed" == true ]]; then
    pid="$(backend_pid 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] || pid='null'
    identity="$(backend_process_identity 2>/dev/null || true)"
  fi
  endpoint="$(backend_endpoint 2>/dev/null || true)"
  if [[ "${HTTP_ENABLED:-false}" == true ]]; then
    adapter_type='privoxy'
    if adapter_privoxy_status >/dev/null 2>&1; then adapter_state='ready'; else adapter_state='stopped'; fi
  fi

  started_at="$(state_epoch started_at)"
  last_transition="$(state_epoch last_transition)"
  last_healthy="$(state_epoch healthy)"
  last_unhealthy="$(state_epoch unhealthy)"
  last_recovered="$(state_epoch recovered)"

  mkdir -p "$(state_dir)"
  local tmp
  tmp="$(mktemp "$(state_dir)/runtime.json.XXXXXX")"
  printf '{"schema_version":2,"profile":%s,"backend":{"name":%s,"status":%s,"endpoint":%s,"managed":%s,"pid":%s,"identity":%s},"adapter":{"type":%s,"enabled":%s,"status":%s},"health":{"last_healthy":%s,"last_unhealthy":%s,"last_recovered":%s},"lifecycle":{"started_at":%s,"last_transition":%s}}\n' \
    "$(state_json_quote "${PA_ACTIVE_PROFILE:-default}")" \
    "$(state_json_quote "$BACKEND")" "$(state_json_quote "$backend_state")" "$(state_json_quote "$endpoint")" \
    "$managed" "$pid" "$(state_json_quote "$identity")" \
    "$(state_json_quote "$adapter_type")" "${HTTP_ENABLED:-false}" "$(state_json_quote "$adapter_state")" \
    "$last_healthy" "$last_unhealthy" "$last_recovered" "$started_at" "$last_transition" >"$tmp"
  mv -f "$tmp" "$(state_file)"
}

state_mark_started() {
  state_set_marker started_at
  state_set_marker last_transition
}

state_mark_stopped() {
  state_set_marker last_transition
}
