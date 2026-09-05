#!/usr/bin/env bash
set -euo pipefail

adapter_privoxy_config() {
  printf '%s' "${PRIVOXY_CONFIG:-$PA_STATE_DIR/privoxy.conf}"
}

adapter_privoxy_pid_file() {
  printf '%s/privoxy.pid' "$PA_STATE_DIR"
}

adapter_privoxy_process_matches() {
  local pid="$1" cmdline exe process_uid current_uid cfg
  [[ -r "/proc/$pid/cmdline" && -e "/proc/$pid/exe" ]] || return 1
  cfg="$(adapter_privoxy_config)"
  cmdline="$(tr '\0' ' ' </proc/"$pid"/cmdline 2>/dev/null || true)"
  [[ "$cmdline" == *"privoxy"* ]] || return 1
  [[ "$cmdline" == *"--no-daemon"* ]] || return 1
  [[ "$cmdline" == *"$cfg"* ]] || return 1
  exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  [[ "$exe" == */privoxy ]] || return 1
  process_uid="$(awk '/^Uid:/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
  current_uid="$(id -u)"
  [[ "$process_uid" == "$current_uid" ]] || return 1
  listener_owned "$HTTP_BIND" "$HTTP_PORT" "$pid"
}

adapter_privoxy_pid() {
  local pid_file pid
  pid_file="$(adapter_privoxy_pid_file)"
  [[ -r "$pid_file" ]] || return 1
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ && -d "/proc/$pid" ]] || { rm -f "$pid_file"; return 1; }
  if adapter_privoxy_process_matches "$pid"; then
    printf '%s' "$pid"
  else
    rm -f "$pid_file"
    return 1
  fi
}

adapter_privoxy_validate() {
  require_cmd privoxy
  require_cmd curl
}

adapter_privoxy_write_config() {
  mkdir -p "$PA_STATE_DIR" "$PA_LOG_DIR"
  local cfg
  cfg="$(adapter_privoxy_config)"
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
  local existing_pid pid cfg
  existing_pid="$(adapter_privoxy_pid 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]]; then
    return 0
  fi
  if port_listening "$HTTP_PORT"; then
    die "HTTP port ${HTTP_BIND}:${HTTP_PORT} is already listening and is not owned by this profile"
  fi
  cfg="$(adapter_privoxy_config)"
  privoxy --no-daemon "$cfg" >>"$PA_LOG_DIR/privoxy.log" 2>&1 &
  pid=$!
  echo "$pid" >"$(adapter_privoxy_pid_file)"
  for _ in {1..20}; do
    if adapter_privoxy_process_matches "$pid"; then
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$(adapter_privoxy_pid_file)"
      warn "Privoxy exited before establishing the HTTP listener"
      return 1
    fi
    sleep 0.25
  done
  warn "Privoxy failed to listen on ${HTTP_BIND}:${HTTP_PORT}"
  return 1
}

adapter_privoxy_stop() {
  local pid
  pid="$(adapter_privoxy_pid 2>/dev/null || true)"
  [[ -n "$pid" ]] || {
    port_listening "$HTTP_PORT" && warn "HTTP port ${HTTP_BIND}:${HTTP_PORT} is listening but is not owned by this profile; refusing to kill it"
    return 0
  }
  rm -f "$(adapter_privoxy_pid_file)"
  kill "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.25
  done
  kill -9 "$pid" 2>/dev/null || true
}

adapter_privoxy_status() {
  adapter_privoxy_pid >/dev/null 2>&1
}
