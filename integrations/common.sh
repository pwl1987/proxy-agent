#!/usr/bin/env bash
set -euo pipefail

integration_proxy_url() {
  if [[ "${HTTP_ENABLED:-false}" == "true" ]]; then
    printf 'http://%s:%s' "$HTTP_BIND" "$HTTP_PORT"
  else
    backend_endpoint
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

integration_require_http() {
  if [[ "${HTTP_ENABLED:-false}" == "true" ]]; then
    return 0
  fi
  backend_capability http_native && return 0
  printf 'WARNING: %s integration requires an HTTP-capable active proxy path; enable HTTP_ENABLED or use a backend with http_native capability.\n' "$1" >&2
  return 1
}
