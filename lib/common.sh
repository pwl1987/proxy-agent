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

apply_config_defaults() {
  : "${BACKEND:=ssh-socks}"
  : "${SOCKS_BIND:=127.0.0.1}"
  : "${SOCKS_PORT:=1080}"
  : "${HTTP_ENABLED:=false}"
  : "${HTTP_BIND:=127.0.0.1}"
  : "${HTTP_PORT:=8118}"
  : "${HEALTH_TIMEOUT:=10}"
  : "${HEALTH_RETRIES:=2}"
  : "${HEALTH_BACKOFF:=2}"
  : "${HEALTH_AUTO_RECOVER:=true}"
  : "${SSH_STRICT_HOST_KEY_CHECKING:=yes}"
  : "${INTEGRATE_GIT:=false}"
  : "${INTEGRATE_DOCKER:=false}"
  : "${INTEGRATE_PIP:=false}"
  : "${INTEGRATE_NPM:=false}"
}

load_config() {
  [[ -r "$PA_CONFIG" ]] || die "config not found: $PA_CONFIG"
  # shellcheck disable=SC1090
  source "$PA_CONFIG"
  apply_config_defaults
}

expand_home() {
  case "$1" in
    '~/'*) printf '%s/%s' "$HOME" "${1#~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

valid_ipv4() {
  local ip="$1" IFS=.
  local a b c d
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  read -r a b c d <<< "$ip"
  for octet in "$a" "$b" "$c" "$d"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( octet <= 255 )) || return 1
  done
}

ipv4_to_int() {
  local IFS=.
  local a b c d
  read -r a b c d <<< "$1"
  printf '%u\n' $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

cidr_contains() {
  local ip="$1" cidr="$2" network prefix mask base value
  valid_ipv4 "$ip" || return 1
  [[ "$cidr" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/([0-9]+)$ ]] || return 1
  network="${BASH_REMATCH[1]}"
  prefix="${BASH_REMATCH[2]}"
  valid_ipv4 "$network" || return 1
  (( prefix >= 0 && prefix <= 32 )) || return 1
  base="$(ipv4_to_int "$network")"
  value="$(ipv4_to_int "$ip")"
  if (( prefix == 0 )); then mask=0; else mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF )); fi
  (( (base & mask) == (value & mask) ))
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
