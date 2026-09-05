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

state_lock_dir() {
  printf '%s/.state.lock' "$(state_dir)"
}

state_lifecycle_lock_file() {
  printf '%s/.lifecycle.lock' "$(state_dir)"
}

state_proc_starttime() {
  local pid="$1"
  [[ -r "/proc/$pid/stat" ]] || return 1
  awk '{print $22}' "/proc/$pid/stat"
}

state_lock_is_stale() {
  local lock_dir holder_pid holder_start created now current_start
  lock_dir="$(state_lock_dir)"
  [[ -d "$lock_dir" ]] || return 1
  holder_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  holder_start="$(cat "$lock_dir/starttime" 2>/dev/null || true)"
  created="$(cat "$lock_dir/created" 2>/dev/null || true)"
  now="$(date +%s)"
  if [[ -z "$holder_pid" || -z "$holder_start" ]]; then
    [[ "$created" =~ ^[0-9]+$ ]] && (( now - created > 30 ))
    return
  fi
  [[ "$holder_pid" =~ ^[0-9]+$ ]] || return 0
  if ! current_start="$(state_proc_starttime "$holder_pid" 2>/dev/null)"; then return 0; fi
  [[ "$current_start" != "$holder_start" ]]
}

state_lock_acquire() {
  mkdir -p "$(state_dir)"
  local lock_dir="$(state_lock_dir)" now quarantine
  for _ in {1..100}; do
    now="$(date +%s)"
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" >"$lock_dir/pid"
      printf '%s\n' "$(state_proc_starttime "$$" 2>/dev/null || printf 0)" >"$lock_dir/starttime"
      printf '%s\n' "$now" >"$lock_dir/created"
      return 0
    fi
    if state_lock_is_stale; then
      quarantine="${lock_dir}.stale.$$.$now"
      if mv "$lock_dir" "$quarantine" 2>/dev/null; then
        rm -rf -- "$quarantine"
      fi
      continue
    fi
    sleep 0.05
  done
  die "runtime state is locked: $lock_dir"
}

state_lock_release() {
  local lock_dir="$(state_lock_dir)" quarantine holder_pid holder_start current_start
  [[ -d "$lock_dir" ]] || return 0
  holder_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  holder_start="$(cat "$lock_dir/starttime" 2>/dev/null || true)"
  current_start="$(state_proc_starttime "$$" 2>/dev/null || true)"
  [[ "$holder_pid" == "$$" && -n "$holder_start" && "$holder_start" == "$current_start" ]] || return 0
  quarantine="${lock_dir}.release.$$"
  if mv "$lock_dir" "$quarantine" 2>/dev/null; then
    rm -rf -- "$quarantine"
  fi
}

state_lifecycle_lock_acquire() {
  mkdir -p "$(state_dir)"
  if [[ "${PA_LIFECYCLE_FD_INHERITED:-false}" == true && "${PA_LIFECYCLE_FD:-}" =~ ^[0-9]+$ ]]; then
    local inherited_target
    inherited_target="$(readlink "/proc/$$/fd/${PA_LIFECYCLE_FD}" 2>/dev/null || true)"
    if [[ "$inherited_target" == "$(state_lifecycle_lock_file)" ]]; then
      return 0
    fi
  fi
  exec {PA_LIFECYCLE_FD}>"$(state_lifecycle_lock_file)"
  chmod 0600 "$(state_lifecycle_lock_file)"
  if ! command -v flock >/dev/null 2>&1; then
    die '缺少 flock，无法保证生命周期并发锁'
  fi
  flock -x "$PA_LIFECYCLE_FD"
}

state_lifecycle_lock_release() {
  if [[ "${PA_LIFECYCLE_FD_INHERITED:-false}" == true ]]; then
    return 0
  fi
  if [[ -n "${PA_LIFECYCLE_FD:-}" ]]; then
    flock -u "$PA_LIFECYCLE_FD" || true
    eval "exec ${PA_LIFECYCLE_FD}>&-"
    unset PA_LIFECYCLE_FD
  fi
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
  state_lock_acquire
  printf '%s\n' "$value" >"$(state_marker "$name")"
  state_lock_release
}

state_clear_marker() {
  state_lock_acquire
  rm -f "$(state_marker "$1")"
  state_lock_release
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

  state_lock_acquire
  started_at="$(state_epoch started_at)"
  last_transition="$(state_epoch last_transition)"
  last_healthy="$(state_epoch healthy)"
  last_unhealthy="$(state_epoch unhealthy)"
  last_recovered="$(state_epoch recovered)"

  local tmp
  tmp="$(mktemp "$(state_dir)/runtime.json.XXXXXX")"
  printf '{"schema_version":2,"profile":%s,"backend":{"name":%s,"status":%s,"endpoint":%s,"managed":%s,"pid":%s,"identity":%s},"adapter":{"type":%s,"enabled":%s,"status":%s},"health":{"last_healthy":%s,"last_unhealthy":%s,"last_recovered":%s},"lifecycle":{"started_at":%s,"last_transition":%s}}\n' \
    "$(state_json_quote "${PA_ACTIVE_PROFILE:-default}")" \
    "$(state_json_quote "$BACKEND")" "$(state_json_quote "$backend_state")" "$(state_json_quote "$endpoint")" \
    "$managed" "$pid" "$(state_json_quote "$identity")" \
    "$(state_json_quote "$adapter_type")" "${HTTP_ENABLED:-false}" "$(state_json_quote "$adapter_state")" \
    "$last_healthy" "$last_unhealthy" "$last_recovered" "$started_at" "$last_transition" >"$tmp"
  mv -f "$tmp" "$(state_file)"
  state_lock_release
}

state_mark_started() {
  state_set_marker started_at
  state_set_marker last_transition
}

state_mark_stopped() {
  state_set_marker last_transition
}
