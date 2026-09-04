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

config_file_secure() {
  local path="$1" mode owner owner_mode group_mode other_mode
  [[ -f "$path" ]] || return 1
  mode="$(stat -c '%a' "$path" 2>/dev/null || true)"
  owner="$(stat -c '%U' "$path" 2>/dev/null || true)"
  [[ "$mode" =~ ^[0-9]+$ ]] || return 1
  owner_mode=$((10#$mode / 100 % 10))
  group_mode=$((10#$mode / 10 % 10))
  other_mode=$((10#$mode % 10))
  [[ "$owner" == root || "$owner" == "$(id -un 2>/dev/null || true)" ]] || return 1
  (( owner_mode == 4 || owner_mode == 6 )) || return 1
  (( group_mode == 0 || group_mode == 4 )) || return 1
  (( other_mode == 0 )) || return 1
}

require_secure_config_file() {
  local path="$1"
  config_file_secure "$path" || die "configuration file must be owner-readable with optional group-read and no group/other write or other-read access: $path"
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
  require_secure_config_file "$PA_CONFIG"
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

valid_ipv4_cidr() {
  local cidr="$1" network prefix
  [[ "$cidr" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/([0-9]+)$ ]] || return 1
  network="${BASH_REMATCH[1]}"
  prefix="${BASH_REMATCH[2]}"
  valid_ipv4 "$network" || return 1
  (( prefix <= 32 ))
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
  valid_ipv4_cidr "$cidr" || return 1
  network="${cidr%%/*}"
  prefix="${cidr##*/}"
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

listener_owned() {
  local bind="$1" port="$2" pid="$3" endpoint
  command -v ss >/dev/null 2>&1 || return 1
  endpoint="${bind}:${port}"
  ss -H -ltnp 2>/dev/null |
    awk -v endpoint="$endpoint" -v pid="$pid" '$4 == endpoint && index($0, "pid=" pid ",") { found=1 } END { exit found ? 0 : 1 }'
}
