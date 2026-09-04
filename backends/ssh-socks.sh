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

backend_ssh_socks_pid_file() {
  printf '%s/ssh-socks.pid' "$PA_STATE_DIR"
}

backend_ssh_socks_endpoint() {
  printf 'socks5h://%s:%s' "$SOCKS_BIND" "$SOCKS_PORT"
}

backend_ssh_socks_managed() {
  return 0
}

backend_ssh_socks_pid() {
  local pid_file pid
  pid_file="$(backend_ssh_socks_pid_file)"
  [[ -r "$pid_file" ]] || return 1
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ && -d "/proc/$pid" ]] || { rm -f "$pid_file"; return 1; }
  if backend_ssh_socks_process_matches "$pid"; then
    printf '%s' "$pid"
  else
    rm -f "$pid_file"
    return 1
  fi
}

backend_ssh_socks_process_matches() {
  local pid="$1" cmdline exe process_uid current_uid
  [[ -r "/proc/$pid/cmdline" && -e "/proc/$pid/exe" ]] || return 1
  cmdline="$(tr '\0' ' ' </proc/"$pid"/cmdline 2>/dev/null || true)"
  [[ "$cmdline" == *autossh* ]] || return 1
  [[ "$cmdline" == *"-D ${SOCKS_BIND}:${SOCKS_PORT}"* || "$cmdline" == *"-D${SOCKS_BIND}:${SOCKS_PORT}"* ]] || return 1
  [[ "$cmdline" == *"${REMOTE_USER}@${REMOTE_HOST}"* ]] || return 1

  exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  [[ "$exe" == */autossh ]] || return 1

  process_uid="$(awk '/^Uid:/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
  current_uid="$(id -u)"
  [[ "$process_uid" == "$current_uid" ]] || return 1

  listener_owned "$SOCKS_BIND" "$SOCKS_PORT" "$pid"
}

backend_ssh_socks_process_identity() {
  local pid exe
  pid="$(backend_ssh_socks_pid 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  printf 'autossh:%s exe=%s uid=%s remote=%s@%s:%s socks=%s:%s' "$pid" "${exe##*/}" "$(id -u)" "$REMOTE_USER" "$REMOTE_HOST" "${REMOTE_PORT:-22}" "$SOCKS_BIND" "$SOCKS_PORT"
}

backend_ssh_socks_validate() {
  : "${REMOTE_HOST:?REMOTE_HOST is required}"
  : "${REMOTE_USER:?REMOTE_USER is required}"
  : "${REMOTE_SSH_KEY:?REMOTE_SSH_KEY is required}"
  require_cmd ssh
  require_cmd autossh
  local key
  key="$(expand_home "$REMOTE_SSH_KEY")"
  [[ -r "$key" ]] || die "SSH key not readable: $key"
  [[ "$SOCKS_BIND" != "0.0.0.0" ]] || warn "SOCKS_BIND=0.0.0.0 exposes the proxy; use loopback unless remote access is intentional"
}

backend_ssh_socks_start() {
  backend_ssh_socks_validate
  mkdir -p "$PA_STATE_DIR" "$PA_LOG_DIR"

  local existing_pid pid_file key pid
  pid_file="$(backend_ssh_socks_pid_file)"
  existing_pid="$(backend_ssh_socks_pid 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]]; then
    return 0
  fi
  rm -f "$pid_file"
  if port_listening "$SOCKS_PORT"; then
    die "SOCKS port ${SOCKS_BIND}:${SOCKS_PORT} is already listening and is not owned by this profile"
  fi

  key="$(expand_home "$REMOTE_SSH_KEY")"
  AUTOSSH_GATETIME=0 autossh -N \
    -M "${AUTOSSH_MONITOR_PORT:-0}" \
    -o BatchMode=yes \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval="${SSH_SERVER_ALIVE_INTERVAL:-30}" \
    -o ServerAliveCountMax="${SSH_SERVER_ALIVE_COUNT_MAX:-3}" \
    -o StrictHostKeyChecking="${SSH_STRICT_HOST_KEY_CHECKING:-yes}" \
    -o UserKnownHostsFile="$(expand_home "${SSH_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}")" \
    -i "$key" -p "${REMOTE_PORT:-22}" \
    -D "${SOCKS_BIND}:${SOCKS_PORT}" \
    "${REMOTE_USER}@${REMOTE_HOST}" >>"$PA_LOG_DIR/ssh-socks.log" 2>&1 &
  pid=$!
  echo "$pid" >"$pid_file"

  for _ in {1..20}; do
    if backend_ssh_socks_liveness; then
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pid_file"
      die 'AutoSSH exited before establishing the SOCKS listener'
    fi
    sleep 0.25
  done
  backend_ssh_socks_stop
  die "SOCKS listener ${SOCKS_BIND}:${SOCKS_PORT} did not become ready"
}

backend_ssh_socks_stop() {
  local pid pid_file
  pid_file="$(backend_ssh_socks_pid_file)"
  pid="$(backend_ssh_socks_pid 2>/dev/null || true)"
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

backend_ssh_socks_liveness() {
  local pid
  pid="$(backend_ssh_socks_pid 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  listener_owned "$SOCKS_BIND" "$SOCKS_PORT" "$pid"
}

backend_ssh_socks_status() {
  backend_ssh_socks_liveness
}
