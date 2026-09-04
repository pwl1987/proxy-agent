#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/backend.sh"
source "$ROOT/backends/http-connect.sh"

BACKEND=http-connect
HTTP_CONNECT_PROXY_URL='http://proxy.example.net:3128'
SOCKS_BIND=127.0.0.1
SOCKS_PORT=1080
HEALTH_TIMEOUT=1

backend_http_connect_validate
[[ "$(backend_http_connect_endpoint)" == 'http://proxy.example.net:3128' ]]
! backend_http_connect_managed
! backend_http_connect_pid >/dev/null 2>&1
backend_http_connect_liveness
[[ "$(backend_http_connect_capabilities | paste -sd, -)" == 'http_native,stream_proxy' ]]

printf 'PASS HTTP CONNECT backend\n'
