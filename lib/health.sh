#!/usr/bin/env bash
set -euo pipefail

health_markers_dir() {
  printf '%s' "$(state_dir)"
}

health_history_file() {
  printf '%s/health-history.jsonl' "$(health_markers_dir)"
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

health_markers_dir() {
  printf '%s' "$(state_dir)"
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
