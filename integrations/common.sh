#!/usr/bin/env bash
set -euo pipefail

integration_proxy_url() {
  if [[ "${HTTP_ENABLED:-false}" == "true" ]]; then
    printf 'http://%s:%s' "$HTTP_BIND" "$HTTP_PORT"
  else
    printf 'socks5h://%s:%s' "$SOCKS_BIND" "$SOCKS_PORT"
  fi
}

integration_no_proxy() {
  local value="${DIRECT_CIDRS:-}"
  [[ -z "${DIRECT_DOMAINS:-}" ]] || value="${value:+${value},}${DIRECT_DOMAINS}"
  [[ -z "${NO_PROXY_EXTRA:-}" ]] || value="${value:+${value},}${NO_PROXY_EXTRA}"
  printf '%s' "$value"
}

integration_enabled() {
  case "$1" in
    git) [[ "${INTEGRATE_GIT:-false}" == "true" ]] ;;
    docker) [[ "${INTEGRATE_DOCKER:-false}" == "true" ]] ;;
    pip) [[ "${INTEGRATE_PIP:-false}" == "true" ]] ;;
    npm) [[ "${INTEGRATE_NPM:-false}" == "true" ]] ;;
    *) return 1 ;;
  esac
}
