#!/usr/bin/env bash
set -euo pipefail

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
      ;;
    unhealthy)
      rm -f "$dir/healthy" "$dir/recovered"
      printf '%s\n' "$ts" >"$dir/unhealthy"
      ;;
    recovered)
      rm -f "$dir/unhealthy"
      printf '%s\n' "$ts" >"$dir/healthy"
      printf '%s\n' "$ts" >"$dir/recovered"
      ;;
    *)
      return 2
      ;;
  esac
}

health_probe_target() {
  local target="$1" timeout="${HEALTH_TIMEOUT:-5}"
  command -v curl >/dev/null 2>&1 || return 127
  curl -fsS --max-time "$timeout" --connect-timeout "$timeout" -o /dev/null "$target"
}

health_probe_backend() {
  local target="${LOCAL_PROXY_STATUS_TARGET:-}"
  [[ -n "$target" ]] || return 2
  curl -fsS --proxy "${LOCAL_PROXY_URL:?LOCAL_PROXY_URL is required}" \
    --max-time "${HEALTH_TIMEOUT:-5}" --connect-timeout "${HEALTH_TIMEOUT:-5}" \
    -o /dev/null "$target"
}

health_probe_network() {
  local target
  [[ -n "${HEALTH_TARGETS:-}" ]] || return 2
  IFS=',' read -r -a targets <<< "$HEALTH_TARGETS"
  for target in "${targets[@]}"; do
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
