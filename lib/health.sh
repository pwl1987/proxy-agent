#!/usr/bin/env bash
set -euo pipefail

health_markers_dir() {
  printf '%s' "$(state_dir)"
}

health_history_file() {
  printf '%s/health-history.jsonl' "$(health_markers_dir)"
}

health_recovery_state_file() {
  printf '%s/health-recovery.json' "$(health_markers_dir)"
}

health_recovery_lock_file() {
  printf '%s/.health-recovery.lock' "$(health_markers_dir)"
}

health_recovery_lock_acquire() {
  mkdir -p "$(health_markers_dir)"
  command -v flock >/dev/null 2>&1 || die '缺少 flock，无法保证健康恢复预算并发锁'
  exec {PA_HEALTH_RECOVERY_FD}>"$(health_recovery_lock_file)"
  chmod 0600 "$(health_recovery_lock_file)"
  flock -x "$PA_HEALTH_RECOVERY_FD"
}

health_recovery_lock_release() {
  [[ -n "${PA_HEALTH_RECOVERY_FD:-}" ]] || return 0
  flock -u "$PA_HEALTH_RECOVERY_FD" 2>/dev/null || true
  eval "exec ${PA_HEALTH_RECOVERY_FD}>&-"
  unset PA_HEALTH_RECOVERY_FD
}

health_json_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

health_record_event() {
  local result="$1" network="$2" detail="${3:-}" ts
  ts="$(date +%s)"
  mkdir -p "$(health_markers_dir)"
  printf '{"timestamp":%s,"profile":%s,"backend":%s,"result":%s,"network":%s,"detail":%s}\n' \
    "$ts" \
    "$(health_json_quote "${PA_ACTIVE_PROFILE:-default}")" \
    "$(health_json_quote "${BACKEND:-unknown}")" \
    "$(health_json_quote "$result")" \
    "$(health_json_quote "$network")" \
    "$(health_json_quote "$detail")" >>"$(health_history_file)"
}

health_recovery_read_state() {
  local file="$(health_recovery_state_file)"
  if [[ -r "$file" ]]; then
    python3 - "$file" <<'PY'
import json
import sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    print(int(data.get("window_started", 0)))
    print(int(data.get("attempts", 0)))
    print(int(data.get("cooldown_until", 0)))
except (OSError, ValueError, TypeError, json.JSONDecodeError):
    print(0)
    print(0)
    print(0)
PY
  else
    printf '0\n0\n0\n'
  fi
}

health_recovery_write_state() {
  local window_started="$1" attempts="$2" cooldown_until="$3" file tmp
  file="$(health_recovery_state_file)"
  mkdir -p "$(health_markers_dir)"
  tmp="${file}.tmp.$$"
  printf '{"window_started":%s,"attempts":%s,"cooldown_until":%s}\n' \
    "$window_started" "$attempts" "$cooldown_until" >"$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$file"
}

health_recovery_reset() {
  health_recovery_lock_acquire
  health_recovery_write_state 0 0 0
  health_recovery_lock_release
}

health_recovery_allowed() {
  local now="$(date +%s)" window_started attempts cooldown_until
  local max_attempts="${HEALTH_RECOVERY_MAX_ATTEMPTS:-3}"
  local window="${HEALTH_RECOVERY_WINDOW:-900}"
  local cooldown="${HEALTH_RECOVERY_COOLDOWN:-300}"
  health_recovery_lock_acquire
  mapfile -t state < <(health_recovery_read_state)
  window_started="${state[0]:-0}"
  attempts="${state[1]:-0}"
  cooldown_until="${state[2]:-0}"

  if (( window_started == 0 || now - window_started >= window )); then
    window_started="$now"
    attempts=0
    cooldown_until=0
    health_recovery_write_state "$window_started" "$attempts" "$cooldown_until"
  fi

  if (( cooldown_until > now )); then
    health_record_event recovery_cooldown skipped "automatic recovery cooldown active until $cooldown_until"
    health_recovery_lock_release
    return 1
  fi

  if (( attempts >= max_attempts )); then
    health_record_event recovery_exhausted blocked "automatic recovery budget exhausted ($attempts/$max_attempts in ${window}s)"
    health_recovery_lock_release
    return 1
  fi

  attempts=$((attempts + 1))
  cooldown_until=$((now + cooldown))
  health_recovery_write_state "$window_started" "$attempts" "$cooldown_until"
  health_recovery_lock_release
  return 0
}

health_clear_markers() {
  local dir
  dir="$(health_markers_dir)"
  rm -f "$dir/healthy" "$dir/unhealthy" "$dir/recovered"
}

health_mark() {
  local state="$1" dir ts
  dir="$(health_markers_dir)"
  mkdir -p "$dir"
  ts="$(date +%s)"
  case "$state" in
    healthy)
      rm -f "$dir/unhealthy" "$dir/recovered"
      printf '%s\n' "$ts" >"$dir/healthy"
      health_record_event healthy checked 'liveness/network check passed'
      ;;
    unhealthy)
      rm -f "$dir/healthy" "$dir/recovered"
      printf '%s\n' "$ts" >"$dir/unhealthy"
      health_record_event unhealthy failed 'health check failed'
      ;;
    recovered)
      rm -f "$dir/unhealthy"
      printf '%s\n' "$ts" >"$dir/healthy"
      printf '%s\n' "$ts" >"$dir/recovered"
      health_record_event recovered checked 'automatic backend recovery succeeded'
      ;;
    *)
      return 2
      ;;
  esac
}

health_probe_target() {
  local target="$1" timeout="${HEALTH_TIMEOUT:-5}" proxy
  command -v curl >/dev/null 2>&1 || return 127
  if [[ "${HTTP_ENABLED:-false}" == true ]]; then
    proxy="http://${HTTP_BIND}:${HTTP_PORT}"
  else
    proxy="$(backend_endpoint)"
  fi
  curl -fsS --proxy "$proxy" --max-time "$timeout" --connect-timeout "$timeout" -o /dev/null "$target"
}

health_probe_backend() {
  local target="${LOCAL_PROXY_STATUS_TARGET:-}"
  [[ -n "$target" ]] || return 2
  health_probe_target "$target"
}

health_probe_network() {
  local target
  [[ -n "${HEALTH_TARGETS:-}" ]] || return 2
  IFS=',' read -r -a targets <<< "$HEALTH_TARGETS"
  for target in "${targets[@]}"; do
    [[ -n "$target" ]] || continue
    health_probe_target "$target" || return 1
  done
}

health_liveness() {
  local prefix="$1"
  "${prefix}_liveness"
}

health_network_status() {
  if [[ -n "${HEALTH_TARGETS:-}" ]]; then
    health_probe_network
  elif [[ "$BACKEND" == local-endpoint && -n "${LOCAL_PROXY_STATUS_TARGET:-}" ]]; then
    health_probe_backend
  else
    return 2
  fi
}
