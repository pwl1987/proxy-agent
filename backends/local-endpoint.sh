#!/usr/bin/env bash
set -euo pipefail

# Existing local proxy endpoint backend. proxy-agent does not own the process.

backend_local_endpoint_capability() {
  case "$1" in
    socks5|stream_proxy) [[ "${LOCAL_PROXY_URL:-}" == socks5://* || "${LOCAL_PROXY_URL:-}" == socks5h://* ]] ;;
    http_native) [[ "${LOCAL_PROXY_URL:-}" == http://* || "${LOCAL_PROXY_URL:-}" == https://* ]] ;;
    *) return 1 ;;
  esac
}

backend_local_endpoint_capabilities() {
  case "${LOCAL_PROXY_URL:-}" in
    socks5://*|socks5h://*) printf '%s\n' socks5 stream_proxy ;;
    http://*|https://*) printf '%s\n' http_native stream_proxy ;;
    *) return 0 ;;
  esac
}

backend_local_endpoint_validate() {
  local endpoint="${LOCAL_PROXY_URL:-}"
  [[ -n "$endpoint" ]] || die 'LOCAL_PROXY_URL is required'
  case "$endpoint" in
    socks5://*|socks5h://*|http://*|https://*) ;;
    *) die 'LOCAL_PROXY_URL must use socks5://, socks5h://, http://, or https://' ;;
  esac
  require_cmd curl
}

backend_local_endpoint_start() {
  backend_local_endpoint_validate
}

backend_local_endpoint_stop() {
  :
}

backend_local_endpoint_status() {
  backend_local_endpoint_validate >/dev/null 2>&1 || return 1
  local probe="${LOCAL_PROXY_STATUS_TARGET:-https://example.com}"
  curl -fsS --proxy "$LOCAL_PROXY_URL" --connect-timeout "${HEALTH_TIMEOUT:-2}" --max-time "$((HEALTH_TIMEOUT + 3))" "$probe" >/dev/null
}

backend_local_endpoint_endpoint() {
  backend_local_endpoint_validate
  printf '%s' "$LOCAL_PROXY_URL"
}

backend_local_endpoint_managed() {
  return 1
}

backend_local_endpoint_pid() {
  return 1
}

backend_local_endpoint_process_identity() {
  return 1
}
