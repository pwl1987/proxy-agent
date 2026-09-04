#!/usr/bin/env bash
set -euo pipefail

adapter_privoxy_validate() {
  require_cmd privoxy
  require_cmd curl
  : "${PRIVOXY_CONFIG:?PRIVOXY_CONFIG is required when HTTP_ENABLED=true}"
}

adapter_privoxy_write_config() {
  mkdir -p "$PA_STATE_DIR" "$PA_LOG_DIR"
  local cfg="${PRIVOXY_CONFIG}"
  install -d -m 0755 "$(dirname "$cfg")"
  cat >"$cfg" <<EOF
confdir /etc/privoxy
logdir $PA_LOG_DIR
logfile privoxy.log
pidfile $PA_STATE_DIR/privoxy.pid
listen-address ${HTTP_BIND}:${HTTP_PORT}
toggle 1
accept-intercepted-requests 0
enable-remote-toggle 0
enable-remote-http-toggle 0
forward-socks5t / ${SOCKS_BIND}:${SOCKS_PORT} .
EOF
}

adapter_privoxy_start() {
  adapter_privoxy_validate
  adapter_privoxy_write_config
  if port_listening "$HTTP_PORT"; then
    return 0
  fi
  privoxy --no-daemon "$PRIVOXY_CONFIG" >>"$PA_LOG_DIR/privoxy.log" 2>&1 &
  echo $! >"$PA_STATE_DIR/privoxy.pid"
  for _ in {1..20}; do
    port_listening "$HTTP_PORT" && return 0
    sleep 0.25
  done
  warn "Privoxy failed to listen on ${HTTP_BIND}:${HTTP_PORT}"
  return 1
}

adapter_privoxy_stop() {
  local pid_file="$PA_STATE_DIR/privoxy.pid"
  if [[ -r "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      kill "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  fi
}

adapter_privoxy_status() {
  port_listening "$HTTP_PORT"
}
