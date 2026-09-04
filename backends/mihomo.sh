#!/usr/bin/env bash
set -euo pipefail

# Managed Mihomo backend. Mihomo owns its YAML configuration; proxy-agent
# owns process lifecycle, listener ownership, and the stable SOCKS endpoint.

backend_mihomo_capability() {
  case "$1" in
    socks5|stream_proxy) return 0 ;;
    http_native|dynamic_dns) return 1 ;;
    *) return 1 ;;
  esac
}

backend_mihomo_capabilities() {
  printf '%s\n' socks5 stream_proxy
}

backend_mihomo_pid_file() {
  printf '%s/mihomo.pid' "$PA_STATE_DIR"
}

backend_mihomo_endpoint() {
  printf 'socks5h://%s:%s' "$SOCKS_BIND" "$SOCKS_PORT"
}

backend_mihomo_managed() {
  return 0
}

backend_mihomo_binary() {
  printf '%s' "${MIHOMO_BIN:-mihomo}"
}

backend_mihomo_config() {
  expand_home "${MIHOMO_CONFIG:-}"
}

backend_mihomo_expected_exe() {
  local binary
  binary="$(backend_mihomo_binary)"
  readlink -f "$(command -v "$binary")" 2>/dev/null || true
}

backend_mihomo_pid() {
  local pid_file pid
  pid_file="$(backend_mihomo_pid_file)"
  [[ -r "$pid_file" ]] || return 1
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ && -d "/proc/$pid" ]] || { rm -f "$pid_file"; return 1; }
  if backend_mihomo_process_matches "$pid"; then
    printf '%s' "$pid"
  else
    rm -f "$pid_file"
    return 1
  fi
}

backend_mihomo_process_matches() {
  local pid="$1" cmdline exe expected process_uid current_uid config
  [[ -r "/proc/$pid/cmdline" && -e "/proc/$pid/exe" ]] || return 1
  config="$(backend_mihomo_config)"
  expected="$(backend_mihomo_expected_exe)"
  [[ -n "$config" && -n "$expected" ]] || return 1
  cmdline="$(tr '\0' ' ' </proc/"$pid"/cmdline 2>/dev/null || true)"
  [[ "$cmdline" == *"-f $config"* || "$cmdline" == *"-f=$config"* ]] || return 1
  exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  [[ "$exe" == "$expected" ]] || return 1
  process_uid="$(awk '/^Uid:/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
  current_uid="$(id -u)"
  [[ "$process_uid" == "$current_uid" ]] || return 1
  listener_owned "$SOCKS_BIND" "$SOCKS_PORT" "$pid"
}

backend_mihomo_process_identity() {
  local pid exe
  pid="$(backend_mihomo_pid 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  printf 'mihomo:%s exe=%s uid=%s config=%s socks=%s:%s' "$pid" "${exe##*/}" "$(id -u)" "$(backend_mihomo_config)" "$SOCKS_BIND" "$SOCKS_PORT"
}

backend_mihomo_validate() {
  local config binary
  config="$(backend_mihomo_config)"
  binary="$(backend_mihomo_binary)"
  [[ -n "$config" ]] || die 'MIHOMO_CONFIG is required for mihomo'
  [[ -r "$config" ]] || die "mihomo config not readable: $config"
  config_file_secure "$config" || die "MIHOMO_CONFIG must be owner-readable with no group/other write or other-read access: $config"
  require_cmd "$binary"
  "$binary" -t -f "$config" >/dev/null
}

backend_mihomo_start() {
  backend_mihomo_validate
  mkdir -p "$PA_STATE_DIR" "$PA_LOG_DIR"

  local existing_pid pid_file config binary pid
  pid_file="$(backend_mihomo_pid_file)"
  existing_pid="$(backend_mihomo_pid 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]]; then
    return 0
  fi
  rm -f "$pid_file"
  if port_listening "$SOCKS_PORT"; then
    die "SOCKS port ${SOCKS_BIND}:${SOCKS_PORT} is already listening and is not owned by this profile"
  fi

  binary="$(backend_mihomo_binary)"
  config="$(backend_mihomo_config)"
  "$binary" -f "$config" >>"$PA_LOG_DIR/mihomo.log" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" >"$pid_file"

  for _ in {1..20}; do
    if backend_mihomo_liveness; then
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pid_file"
      die 'mihomo exited before establishing the SOCKS listener'
    fi
    sleep 0.25
  done
  backend_mihomo_stop
  die "SOCKS listener ${SOCKS_BIND}:${SOCKS_PORT} did not become ready"
}

backend_mihomo_stop() {
  local pid pid_file
  pid_file="$(backend_mihomo_pid_file)"
  pid="$(backend_mihomo_pid 2>/dev/null || true)"
  rm -f "$pid_file"
  [[ -n "$pid" ]] || {
    port_listening "$SOCKS_PORT" && warn "SOCKS port ${SOCKS_BIND}:${SOCKS_PORT} is listening but is not owned by this profile; refusing to kill it"
    return 0
  }
  kill "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.25
  done
  kill -9 "$pid" 2>/dev/null || true
}

backend_mihomo_liveness() {
  local pid
  pid="$(backend_mihomo_pid 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  listener_owned "$SOCKS_BIND" "$SOCKS_PORT" "$pid"
}

backend_mihomo_status() {
  backend_mihomo_liveness
}
