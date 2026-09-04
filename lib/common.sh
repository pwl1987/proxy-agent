#!/usr/bin/env bash
set -euo pipefail

PA_CONFIG="${PA_CONFIG:-/etc/proxy-agent/proxy-agent.conf}"
PA_STATE_DIR="${PA_STATE_DIR:-/run/proxy-agent}"
PA_LOG_DIR="${PA_LOG_DIR:-/var/log/proxy-agent}"

log() { printf '[proxy-agent] %s\n' "$*"; }
warn() { printf '[proxy-agent] WARNING: %s\n' "$*" >&2; }
die() { printf '[proxy-agent] ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

load_config() {
  [[ -r "$PA_CONFIG" ]] || die "config not found: $PA_CONFIG"
  # shellcheck disable=SC1090
  source "$PA_CONFIG"
  : "${BACKEND:=ssh-socks}"
  : "${SOCKS_BIND:=127.0.0.1}"
  : "${SOCKS_PORT:=1080}"
  : "${HTTP_ENABLED:=false}"
  : "${HTTP_BIND:=127.0.0.1}"
  : "${HTTP_PORT:=8118}"
  : "${HEALTH_TIMEOUT:=10}"
}

expand_home() {
  case "$1" in
    '~/'*) printf '%s/%s' "$HOME" "${1#~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

svc() {
  local action="$1"; shift
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl "$action" "$@"
  else
    return 1
  fi
}

port_listening() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${1}$"
}
