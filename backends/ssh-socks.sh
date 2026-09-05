#!/usr/bin/env bash
set -euo pipefail

# SSH -> local SOCKS5 backend. Intended to be sourced by proxy-ctl.
# shellcheck source=../lib/ssh-reference.sh
source "$ROOT/lib/ssh-reference.sh"

backend_ssh_socks_capability() {
  case "$1" in
    socks5|dynamic_dns|stream_proxy|supports_egress_path|supports_jump|supports_remote_dns) return 0 ;;
    http_native) return 1 ;;
    *) return 1 ;;
  esac
}

backend_ssh_socks_capabilities() {
  printf '%s\n' socks5 dynamic_dns stream_proxy supports_egress_path supports_jump supports_remote_dns
}

backend_ssh_socks_pid_file() { printf '%s/ssh-socks.pid' "$PA_STATE_DIR"; }

backend_ssh_socks_endpoint() {
  if [[ "${SSH_DNS_MODE:-remote}" == local ]]; then
    printf 'socks5://%s:%s' "$SOCKS_BIND" "$SOCKS_PORT"
  else
    printf 'socks5h://%s:%s' "$SOCKS_BIND" "$SOCKS_PORT"
  fi
}

backend_ssh_socks_managed() { return 0; }

backend_ssh_socks_pid() {
  local pid_file pid
  pid_file="$(backend_ssh_socks_pid_file)"
  [[ -r "$pid_file" ]] || return 1
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ && -d "/proc/$pid" ]] || { rm -f "$pid_file"; return 1; }
  if backend_ssh_socks_process_matches "$pid"; then printf '%s' "$pid"; else rm -f "$pid_file"; return 1; fi
}

backend_ssh_socks_process_matches() {
  local pid="$1" cmdline exe process_uid current_uid
  [[ -r "/proc/$pid/cmdline" && -e "/proc/$pid/exe" ]] || return 1
  cmdline="$(tr '\0' ' ' </proc/"$pid"/cmdline 2>/dev/null || true)"
  [[ "$cmdline" == *autossh* ]] || return 1
  [[ "$cmdline" == *"-D ${SOCKS_BIND}:${SOCKS_PORT}"* || "$cmdline" == *"-D${SOCKS_BIND}:${SOCKS_PORT}"* ]] || return 1
  if [[ "${SSH_EGRESS_MODE:-direct}" == jump ]]; then
    [[ "$cmdline" == *"__proxy_agent_target"* ]] || return 1
  else
    [[ "$cmdline" == *"${REMOTE_USER}@${REMOTE_HOST}"* ]] || return 1
  fi
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
  if [[ "${SSH_EGRESS_MODE:-direct}" == jump ]]; then
    printf 'autossh:%s exe=%s uid=%s mode=jump target=%s@%s:%s jump=%s@%s:%s socks=%s:%s' "$pid" "${exe##*/}" "$(id -u)" "$REMOTE_USER" "$REMOTE_HOST" "${REMOTE_PORT:-22}" "$SSH_JUMP_USER" "$SSH_JUMP_HOST" "${SSH_JUMP_PORT:-22}" "$SOCKS_BIND" "$SOCKS_PORT"
  else
    printf 'autossh:%s exe=%s uid=%s mode=direct remote=%s@%s:%s socks=%s:%s' "$pid" "${exe##*/}" "$(id -u)" "$REMOTE_USER" "$REMOTE_HOST" "${REMOTE_PORT:-22}" "$SOCKS_BIND" "$SOCKS_PORT"
  fi
}

backend_ssh_socks_validate() {
  : "${REMOTE_HOST:?REMOTE_HOST is required}"
  : "${REMOTE_USER:?REMOTE_USER is required}"
  : "${REMOTE_SSH_KEY:?REMOTE_SSH_KEY is required}"
  require_cmd ssh
  require_cmd autossh
  local key="$(expand_home "$REMOTE_SSH_KEY")"
  [[ -r "$key" ]] || die "SSH key not readable: $key"
  [[ "$SOCKS_BIND" != "0.0.0.0" ]] || warn "SOCKS_BIND=0.0.0.0 exposes the proxy; use loopback unless remote access is intentional"
  case "${SSH_EGRESS_MODE:-direct}" in
    direct) return 0 ;;
    jump)
      : "${SSH_JUMP_HOST:?SSH_JUMP_HOST is required for jump mode}"
      : "${SSH_JUMP_USER:?SSH_JUMP_USER is required for jump mode}"
      : "${SSH_JUMP_PORT:?SSH_JUMP_PORT is required for jump mode}"
      : "${SSH_JUMP_KEY:?SSH_JUMP_KEY is required for jump mode}"
      : "${SSH_JUMP_KNOWN_HOSTS:?SSH_JUMP_KNOWN_HOSTS is required for jump mode}"
      : "${SSH_TARGET_KEY:?SSH_TARGET_KEY is required for jump mode}"
      : "${SSH_TARGET_KNOWN_HOSTS:?SSH_TARGET_KNOWN_HOSTS is required for jump mode}"
      [[ "${SSH_DNS_MODE:-remote}" == local || "${SSH_DNS_MODE:-remote}" == remote ]] || die "SSH_DNS_MODE must be local or remote"
      ssh_identity_resolve "$SSH_JUMP_KEY" >/dev/null
      ssh_identity_resolve "$SSH_TARGET_KEY" >/dev/null
      ssh_known_hosts_resolve "$SSH_JUMP_KNOWN_HOSTS" >/dev/null
      ssh_known_hosts_resolve "$SSH_TARGET_KNOWN_HOSTS" >/dev/null
      ;;
    *) die "SSH_EGRESS_MODE must be direct or jump" ;;
  esac
}

backend_ssh_socks_runtime_ssh_config() { printf '%s/ssh-socks-runtime.conf' "$PA_STATE_DIR"; }

ssh_config_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

backend_ssh_socks_write_jump_config() {
  local file="$1" jump_key jump_known target_key target_known tmp
  local jump_host jump_user target_host target_user jump_known_quoted target_known_quoted jump_key_quoted target_key_quoted
  jump_key="$(ssh_identity_resolve "$SSH_JUMP_KEY")"; jump_known="$(ssh_known_hosts_resolve "$SSH_JUMP_KNOWN_HOSTS")"
  target_key="$(ssh_identity_resolve "$SSH_TARGET_KEY")"; target_known="$(ssh_known_hosts_resolve "$SSH_TARGET_KNOWN_HOSTS")"
  jump_host="$(ssh_config_quote "$SSH_JUMP_HOST")"; jump_user="$(ssh_config_quote "$SSH_JUMP_USER")"
  target_host="$(ssh_config_quote "$REMOTE_HOST")"; target_user="$(ssh_config_quote "$REMOTE_USER")"
  jump_key_quoted="$(ssh_config_quote "$jump_key")"; target_key_quoted="$(ssh_config_quote "$target_key")"
  jump_known_quoted="$(ssh_config_quote "$jump_known")"; target_known_quoted="$(ssh_config_quote "$target_known")"
  tmp="${file}.tmp.$$"
  cat >"$tmp" <<EOF
Host __proxy_agent_jump
  HostName ${jump_host}
  User ${jump_user}
  Port ${SSH_JUMP_PORT}
  IdentityFile ${jump_key_quoted}
  UserKnownHostsFile ${jump_known_quoted}
  StrictHostKeyChecking ${SSH_STRICT_HOST_KEY_CHECKING:-yes}
  IdentitiesOnly yes

Host __proxy_agent_target
  HostName ${target_host}
  User ${target_user}
  Port ${REMOTE_PORT:-22}
  IdentityFile ${target_key_quoted}
  UserKnownHostsFile ${target_known_quoted}
  StrictHostKeyChecking ${SSH_STRICT_HOST_KEY_CHECKING:-yes}
  IdentitiesOnly yes
  ProxyJump __proxy_agent_jump
EOF
  chmod 0600 "$tmp"; mv -f "$tmp" "$file"
}

backend_ssh_socks_start() {
  backend_ssh_socks_validate
  mkdir -p "$PA_STATE_DIR" "$PA_LOG_DIR"
  local existing_pid pid_file key pid ssh_config
  pid_file="$(backend_ssh_socks_pid_file)"
  existing_pid="$(backend_ssh_socks_pid 2>/dev/null || true)"
  [[ -n "$existing_pid" ]] && return 0
  rm -f "$pid_file"
  if port_listening "$SOCKS_PORT"; then die "SOCKS port ${SOCKS_BIND}:${SOCKS_PORT} is already listening and is not owned by this profile"; fi

  if [[ "${SSH_EGRESS_MODE:-direct}" == jump ]]; then
    ssh_config="$(backend_ssh_socks_runtime_ssh_config)"
    backend_ssh_socks_write_jump_config "$ssh_config"
    AUTOSSH_GATETIME=0 autossh -N -M "${AUTOSSH_MONITOR_PORT:-0}" -F "$ssh_config" -o BatchMode=yes -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval="${SSH_SERVER_ALIVE_INTERVAL:-30}" -o ServerAliveCountMax="${SSH_SERVER_ALIVE_COUNT_MAX:-3}" \
      -D "${SOCKS_BIND}:${SOCKS_PORT}" __proxy_agent_target >>"$PA_LOG_DIR/ssh-socks.log" 2>&1 &
  else
    rm -f "$(backend_ssh_socks_runtime_ssh_config)"
    key="$(expand_home "$REMOTE_SSH_KEY")"
    AUTOSSH_GATETIME=0 autossh -N -M "${AUTOSSH_MONITOR_PORT:-0}" -o BatchMode=yes -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval="${SSH_SERVER_ALIVE_INTERVAL:-30}" -o ServerAliveCountMax="${SSH_SERVER_ALIVE_COUNT_MAX:-3}" \
      -o StrictHostKeyChecking="${SSH_STRICT_HOST_KEY_CHECKING:-yes}" -o UserKnownHostsFile="$(expand_home "${SSH_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}")" \
      -i "$key" -p "${REMOTE_PORT:-22}" -D "${SOCKS_BIND}:${SOCKS_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" >>"$PA_LOG_DIR/ssh-socks.log" 2>&1 &
  fi
  pid=$!; echo "$pid" >"$pid_file"
  for _ in {1..20}; do
    if backend_ssh_socks_liveness; then return 0; fi
    if ! kill -0 "$pid" 2>/dev/null; then rm -f "$pid_file"; rm -f "$(backend_ssh_socks_runtime_ssh_config)"; die 'AutoSSH exited before establishing the SOCKS listener'; fi
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
  [[ -n "$pid" ]] || { port_listening "$SOCKS_PORT" && warn "SOCKS port ${SOCKS_BIND}:${SOCKS_PORT} is listening but is not owned by this profile; refusing to kill it"; rm -f "$(backend_ssh_socks_runtime_ssh_config)"; return 0; }
  kill "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    kill -0 "$pid" 2>/dev/null || { rm -f "$(backend_ssh_socks_runtime_ssh_config)"; return 0; }
    sleep 0.25
  done
  kill -9 "$pid" 2>/dev/null || true
  rm -f "$(backend_ssh_socks_runtime_ssh_config)"
}

backend_ssh_socks_liveness() {
  local pid; pid="$(backend_ssh_socks_pid 2>/dev/null || true)"; [[ -n "$pid" ]] || return 1; listener_owned "$SOCKS_BIND" "$SOCKS_PORT" "$pid"
}

backend_ssh_socks_status() { backend_ssh_socks_liveness; }
