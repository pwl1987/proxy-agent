#!/usr/bin/env bash
set -euo pipefail

CONFIG_ERRORS=0

config_error() {
  printf '[config] ERROR: %s\n' "$*" >&2
  CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
}

config_is_bool() {
  [[ "$2" == true || "$2" == false ]] || config_error "$1 must be true or false"
}

config_is_uint_range() {
  local name="$1" value="$2" min="$3" max="$4"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    config_error "$name must be an integer"
    return
  fi
  if (( value < min || value > max )); then
    config_error "$name must be between $min and $max"
  fi
}

config_is_bind() {
  local name="$1" value="$2"
  [[ -n "$value" ]] || { config_error "$name must not be empty"; return; }
  [[ "$value" != *[[:space:]]* ]] || { config_error "$name must not contain whitespace"; return; }
  [[ "$value" =~ ^[A-Za-z0-9_.:-]+$ || "$value" =~ ^\[[0-9A-Fa-f:]+\]$ ]] || \
    config_error "$name contains unsupported address syntax: $value"
}

config_validate_proxy_url() {
  local name="$1" value="$2" hostport host port
  [[ -n "$value" ]] || { config_error "$name must not be empty"; return; }
  [[ "$value" =~ ^(socks5|socks5h|http|https)://([^/]+)(/)?$ ]] || {
    config_error "$name must use scheme://host[:port] with socks5, socks5h, http, or https"
    return
  }
  hostport="${BASH_REMATCH[2]}"
  if [[ "$hostport" =~ ^\[[0-9A-Fa-f:]+\](:([0-9]+))?$ ]]; then
    port="${BASH_REMATCH[2]:-}"
  elif [[ "$hostport" =~ ^([^:]+)(:([0-9]+))?$ ]]; then
    host="${BASH_REMATCH[1]}"
    port="${BASH_REMATCH[3]:-}"
    [[ -n "$host" && "$host" != *[[:space:]]* ]] || config_error "$name has an invalid host"
  else
    config_error "$name has an invalid host/port: $hostport"
    return
  fi
  [[ -z "$port" ]] || config_is_uint_range "$name port" "$port" 1 65535
}

config_validate_list() {
  local name="$1" value="$2" item
  [[ -z "$value" ]] && return 0
  IFS=',' read -r -a items <<< "$value"
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || { config_error "$name contains an empty entry"; continue; }
    [[ "$item" != *[[:space:]]* ]] || config_error "$name contains whitespace: $item"
  done
}

config_validate_domains() {
  local name="$1" value="$2" item
  [[ -z "$value" ]] && return 0
  IFS=',' read -r -a items <<< "$value"
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || { config_error "$name contains an empty entry"; continue; }
    item="${item#.}"
    [[ "$item" =~ ^[A-Za-z0-9_*.?-]+$ ]] || config_error "$name contains invalid hostname pattern: $item"
  done
}

config_validate_targets() {
  local name="$1" value="$2" target
  [[ -z "$value" ]] && return 0
  IFS=',' read -r -a targets <<< "$value"
  for target in "${targets[@]}"; do
    [[ "$target" =~ ^https?://[^[:space:]]+$ ]] || config_error "$name contains invalid target: $target"
  done
}

config_validate_core() {
  [[ "${BACKEND:-}" =~ ^[A-Za-z0-9._-]+$ ]] || config_error 'BACKEND must contain only letters, digits, dot, underscore, or dash'
  config_is_bind SOCKS_BIND "${SOCKS_BIND:-}"
  config_is_uint_range SOCKS_PORT "${SOCKS_PORT:-}" 1 65535
  config_is_bool HTTP_ENABLED "${HTTP_ENABLED:-}"
  config_is_bind HTTP_BIND "${HTTP_BIND:-}"
  config_is_uint_range HTTP_PORT "${HTTP_PORT:-}" 1 65535

  config_is_bool HEALTH_NETWORK_REQUIRED "${HEALTH_NETWORK_REQUIRED:-false}"
  config_is_uint_range HEALTH_TIMEOUT "${HEALTH_TIMEOUT:-}" 1 3600
  config_is_uint_range HEALTH_RETRIES "${HEALTH_RETRIES:-}" 0 100
  config_is_uint_range HEALTH_BACKOFF "${HEALTH_BACKOFF:-}" 0 3600
  config_is_bool HEALTH_AUTO_RECOVER "${HEALTH_AUTO_RECOVER:-}"
  config_is_bool INTEGRATE_GIT "${INTEGRATE_GIT:-}"
  config_is_bool INTEGRATE_DOCKER "${INTEGRATE_DOCKER:-}"
  config_is_bool INTEGRATE_PIP "${INTEGRATE_PIP:-}"
  config_is_bool INTEGRATE_NPM "${INTEGRATE_NPM:-}"
  case "${SSH_STRICT_HOST_KEY_CHECKING:-}" in
    yes|accept-new) ;;
    *) config_error 'SSH_STRICT_HOST_KEY_CHECKING must be yes or accept-new' ;;
  esac
  [[ "${SOCKS_BIND:-}" != '0.0.0.0' && "${SOCKS_BIND:-}" != '::' ]] || config_error 'SOCKS_BIND must not expose the proxy by default; use loopback or make exposure an explicit deployment decision'

  local cidr
  config_validate_list DIRECT_CIDRS "${DIRECT_CIDRS:-}"
  if [[ -n "${DIRECT_CIDRS:-}" ]]; then
    IFS=',' read -r -a cidrs <<< "$DIRECT_CIDRS"
    for cidr in "${cidrs[@]}"; do
      valid_ipv4_cidr "$cidr" || config_error "DIRECT_CIDRS contains invalid CIDR: $cidr"
    done
  fi
  config_validate_domains DIRECT_DOMAINS "${DIRECT_DOMAINS:-}"
  config_validate_list NO_PROXY_EXTRA "${NO_PROXY_EXTRA:-}"
  config_validate_targets HEALTH_TARGETS "${HEALTH_TARGETS:-}"
  local route_errors=0
  route_validate_rules || route_errors=$?
  CONFIG_ERRORS=$((CONFIG_ERRORS + route_errors))
}

config_validate_backend_fields() {
  case "$BACKEND" in
    ssh-socks)
      [[ -n "${REMOTE_HOST:-}" ]] || config_error 'REMOTE_HOST is required for ssh-socks'
      [[ -n "${REMOTE_USER:-}" ]] || config_error 'REMOTE_USER is required for ssh-socks'
      config_is_uint_range REMOTE_PORT "${REMOTE_PORT:-22}" 1 65535
      [[ -n "${REMOTE_SSH_KEY:-}" ]] || config_error 'REMOTE_SSH_KEY is required for ssh-socks'
      ;;
    local-endpoint)
      config_validate_proxy_url LOCAL_PROXY_URL "${LOCAL_PROXY_URL:-}"
      [[ -z "${LOCAL_PROXY_STATUS_TARGET:-}" || "${LOCAL_PROXY_STATUS_TARGET}" =~ ^https?://[^[:space:]]+$ ]] || config_error 'LOCAL_PROXY_STATUS_TARGET must be an http(s) URL'
      ;;
  esac
}

config_validate_cross_fields() {
  if [[ "${HTTP_ENABLED:-false}" == true ]]; then
    backend_capability socks5 || config_error "backend '$BACKEND' cannot provide the Privoxy HTTP adapter (requires socks5 capability)"
  fi
}

config_validate_backend_runtime() {
  local prefix="$(backend_function_prefix "$BACKEND")" output
  if output="$(${prefix}_validate 2>&1)"; then
    [[ -z "$output" ]] || printf '%s\n' "$output"
  else
    [[ -z "$output" ]] || while IFS= read -r line; do config_error "backend: $line"; done <<< "$output"
    config_error "backend '$BACKEND' validation failed"
  fi
}

config_validate() {
  CONFIG_ERRORS=0
  config_validate_core
  config_validate_backend_fields
  config_validate_cross_fields
  config_validate_backend_runtime
  if (( CONFIG_ERRORS == 0 )); then
    printf 'configuration valid: profile=%s backend=%s\n' "${PA_ACTIVE_PROFILE:-default}" "$BACKEND"
    return 0
  fi
  printf 'configuration invalid: %d error(s)\n' "$CONFIG_ERRORS" >&2
  return 1
}
