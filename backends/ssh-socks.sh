#!/usr/bin/env bash
set -euo pipefail

# SSH -> local SOCKS5 backend. Intended to be sourced by proxy-ctl.

backend_ssh_socks_capability() {
  case "$1" in
    socks5|dynamic_dns|stream_proxy) return 0 ;;
    http_native) return 1 ;;
    *) return 1 ;;
  esac
}

backend_ssh_socks_capabilities() {
  printf '%s\n' socks5 dynamic_dns stream_proxy
}

backend_ssh_socks_endpoint() {
  printf 'socks5h://%s:%s' "$SOCKS_BIND" "$SOCKS_PORT"
}

backend_ssh_socks_validate() {
  : "${REMOTE_HOST:?REMOTE_HOST is required}"
  : "${REMOTE_USER:?REMOTE_USER is required}"
  require_cmd ssh
  require_cmd autossh
  [[ "$SOCKS_BIND" != "0.0.0.0" ]] || warn "SOCKS_BIND=0.0.0.0 exposes the proxy; use loopback unless remote access is intentional"
}

backend_ssh_socks_start() {
  backend_ssh_socks_validate
  mkdir -p "$PA_STATE_DIR"
  local key
  key="$(expand_home "$REMOTE_SSH_KEY")"
  [[ -r "$key" ]] || die "SSH key not readable: $key"

  local monitor=()
  if [[ "${AUTOSSH_MONITOR_PORT:-0}" != "0" ]]; then
    monitor=(-M "$AUTOSSH_MONITOR_PORT")
  else
    monitor=(-M 0)
  fi

  AUTOSSH_GATETIME=0 autossh -f -N \
    "${monitor[@]}" \
    -o BatchMode=yes \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval="${SSH_SERVER_ALIVE_INTERVAL:-30}" \
    -o ServerAliveCountMax="${SSH_SERVER_ALIVE_COUNT_MAX:-3}" \
    -o StrictHostKeyChecking="${SSH_STRICT_HOST_KEY_CHECKING:-yes}" \
    -o UserKnownHostsFile="${SSH_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}" \
    -i "$key" -p "${REMOTE_PORT:-22}" \
    -D "${SOCKS_BIND}:${SOCKS_PORT}" \
    "${REMOTE_USER}@${REMOTE_HOST}"
}

backend_ssh_socks_stop() {
  pkill -f -- "ssh.*-D[ =]${SOCKS_BIND}:${SOCKS_PORT}" 2>/dev/null || true
  pkill -f -- "autossh.*-D[ =]${SOCKS_BIND}:${SOCKS_PORT}" 2>/dev/null || true
}

backend_ssh_socks_status() {
  port_listening "$SOCKS_PORT"
}
