#!/usr/bin/env bash
set -euo pipefail

# Unmanaged upstream HTTP proxy backend. The upstream endpoint may support
# HTTP CONNECT; proxy-agent does not own the remote proxy process.

backend_http_connect_capability() {
  case "$1" in
    http_native|stream_proxy) return 0 ;;
    socks5|dynamic_dns) return 1 ;;
    *) return 1 ;;
  esac
}

backend_http_connect_capabilities() {
  printf '%s\n' http_native stream_proxy
}

backend_http_connect_endpoint() {
  printf '%s' "${HTTP_CONNECT_PROXY_URL:-}"
}

backend_http_connect_managed() {
  return 1
}

backend_http_connect_pid() {
  return 1
}

backend_http_connect_process_identity() {
  return 1
}

backend_http_connect_validate() {
  local endpoint="${HTTP_CONNECT_PROXY_URL:-}" scheme authority host port
  [[ -n "$endpoint" ]] || die 'HTTP_CONNECT_PROXY_URL is required'
  [[ "$endpoint" =~ ^https?://[^/]+/?$ ]] || die 'HTTP_CONNECT_PROXY_URL must use http://host[:port] or https://host[:port]'

  authority="${endpoint#*://}"
  authority="${authority%%/*}"
  if [[ "$authority" == \[*\]* ]]; then
    host="${authority%%]*}]"
    port="${authority#*]:}"
    [[ "$port" == "$authority" ]] && port=''
  else
    host="${authority%%:*}"
    port="${authority#*:}"
    [[ "$port" == "$authority" ]] && port=''
  fi
  [[ -n "$host" ]] || die 'HTTP_CONNECT_PROXY_URL has an empty host'
  if [[ -n "$port" ]]; then
    [[ "$port" =~ ^[0-9]+$ ]] || die 'HTTP_CONNECT_PROXY_URL port must be numeric'
    (( port >= 1 && port <= 65535 )) || die 'HTTP_CONNECT_PROXY_URL port must be 1..65535'
  fi
  scheme="${endpoint%%://*}"
  case "$scheme" in
    http|https) ;;
    *) die 'HTTP_CONNECT_PROXY_URL must use http:// or https://' ;;
  esac
  require_cmd curl
}

backend_http_connect_start() {
  backend_http_connect_validate
}

backend_http_connect_stop() {
  :
}

backend_http_connect_liveness() {
  backend_http_connect_validate >/dev/null 2>&1
}

backend_http_connect_status() {
  backend_http_connect_liveness
}
