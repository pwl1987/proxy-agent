#!/usr/bin/env bash
set -euo pipefail

# Managed sing-box backend. sing-box owns its JSON configuration; proxy-agent
# owns process lifecycle, listener ownership, and the stable proxy endpoint.

backend_sing_box_capability() {
  case "$1" in
    socks5|stream_proxy) return 0 ;;
    http_native|dynamic_dns) return 1 ;;
    *) return 1 ;;
  esac
}

backend_sing_box_capabilities() {
  printf '%s\n' socks5 stream_proxy
}

backend_sing_box_pid_file() {
  printf '%s/sing-box.pid' "$PA_STATE_DIR"
}

backend_sing_box_endpoint() {
  printf 'socks5h://%s:%s' "$SOCKS_BIND" "$SOCKS_PORT"
}

backend_sing_box_managed() {
  return 0
}

backend_sing_box_pid() {
  local pid_file pid
  pid_file="$(backend_sing_box_pid_file)"
  [[ -r "$pid_file" ]] || return 1
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ && -d "/proc/$pid" ]] || { rm -f "$pid_file"; return 1; }
  if backend_sing_box_process_matches "$pid"; then
    printf '%s' "$pid"
  else
    rm -f "$pid_file"
    return 1
  fi
}

backend_sing_box_process_matches() {
  local pid="$1" cmdline exe process_uid current_uid
  [[ -r "/proc/$pid/cmdline" && -e "/proc/$pid/exe" ]] || return 1
  cmdline="$(tr '\0' ' ' </proc/"$pid"/cmdline 2>/dev/null || true)"
  [[ "$cmdline" == *"sing-box run"* ]] || return 1
  [[ "$cmdline" == *"-c ${SING_BOX_CONFIG}"* || "$cmdline" == *"-c=${SING_BOX_CONFIG}"* ]] || return 1
  exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  [[ "$exe" == */sing-box ]] || return 1
  process_uid="$(awk '/^Uid:/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
  current_uid="$(id -u)"
  [[ "$process_uid" == "$current_uid" ]] || return 1
  listener_owned "$SOCKS_BIND" "$SOCKS_PORT" "$pid"
}

backend_sing_box_process_identity() {
  local pid exe
  pid="$(backend_sing_box_pid 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  printf 'sing-box:%s exe=%s uid=%s config=%s socks=%s:%s' "$pid" "${exe##*/}" "$(id -u)" "$SING_BOX_CONFIG" "$SOCKS_BIND" "$SOCKS_PORT"
}

backend_sing_box_validate() {
  local binary config
  binary="${SING_BOX_BIN:-sing-box}"
  config="$(expand_home "${SING_BOX_CONFIG:-}")"
  [[ -n "$config" ]] || die 'SING_BOX_CONFIG is required for sing-box'
  [[ -r "$config" ]] || die "sing-box config not readable: $config"
  require_cmd "$binary"
  "$binary" check -c "$config" >/dev/null
}

backend_sing_box_start() {
  backend_sing_box_validate
  mkdir -p "$PA_STATE_DIR" "$PA_LOG_DIR"

  local existing_pid pid_file config binary
  pid_file="$(backend_sing_box_pid_file)"
  existing_pid="$(backend_sing_box_pid 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]]; then
    return 0
  fi
  rm -f "$pid_file"
  if port_listening "$SOCKS_PORT"; then
    die "SOCKS port ${SOCKS_BIND}:${SOCKS_PORT} is already listening and is not owned by this profile"
  fi

  binary="${SING_BOX_BIN:-sing-box}"
  config="$(expand_home "$SING_BOX_CONFIG")"
  "$binary" run -c "$config" >>"$PA_LOG_DIR/sing-box.log" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" >"$pid_file"

  for _ in {1..20}; do
    if backend_sing_box_liveness; then
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pid_file"
      die 'sing-box exited before establishing the SOCKS listener'
    fi
    sleep 0.25
  done
  backend_sing_box_stop
  die "SOCKS listener ${SOCKS_BIND}:${SOCKS_PORT} did not become ready"
}

backend_sing_box_stop() {
  local pid pid_file
  pid_file="$(backend_sing_box_pid_file)"
  pid="$(backend_sing_box_pid 2>/dev/null || true)"
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

backend_sing_box_liveness() {
  local pid
  pid="$(backend_sing_box_pid 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  listener_owned "$SOCKS_BIND" "$SOCKS_PORT" "$pid"
}

backend_sing_box_status() {
  backend_sing_box_liveness
}
