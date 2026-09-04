#!/usr/bin/env bash
set -euo pipefail

backend_capability() {
  local capability="$1"
  case "${BACKEND:-}" in
    ssh-socks)
      case "$capability" in
        socks5) return 0 ;;
        dynamic_dns) return 0 ;;
        http_native) return 1 ;;
        stream_proxy) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

backend_capabilities() {
  case "${BACKEND:-}" in
    ssh-socks) printf '%s\n' socks5 dynamic_dns stream_proxy ;;
    *) : ;;
  esac
}

backend_require_capability() {
  backend_capability "$1" || die "backend '$BACKEND' does not provide capability '$1'"
}
