#!/usr/bin/env bash
set -euo pipefail

BACKEND_NAME="${1:-}"
BINARY_PATH="${2:-}"
[[ -n "$BACKEND_NAME" && -x "$BINARY_PATH" ]] || { echo 'usage: real-backend-smoke.sh <sing-box|mihomo> <binary>'; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${RUNNER_TEMP:-/tmp}/proxy-agent-real-${BACKEND_NAME}"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/state" "$WORKDIR/log" "$WORKDIR/bin"
trap 'PA_CONFIG="$WORKDIR/proxy-agent.conf" PA_STATE_DIR="$WORKDIR/state" PA_LOG_DIR="$WORKDIR/log" bash "$ROOT/bin/proxy-ctl" stop >/dev/null 2>&1 || true; rm -rf "$WORKDIR"' EXIT

PORT=18080
BACKEND_CONFIG="$WORKDIR/backend.conf"
case "$BACKEND_NAME" in
  sing-box)
    cat >"$BACKEND_CONFIG" <<EOF
{
  "log": {"level": "error"},
  "inbounds": [{"type": "socks", "tag": "socks-in", "listen": "127.0.0.1", "listen_port": $PORT}],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF
    cat >"$WORKDIR/proxy-agent.conf" <<EOF
BACKEND="sing-box"
SING_BOX_BIN="$BINARY_PATH"
SING_BOX_CONFIG="$BACKEND_CONFIG"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="$PORT"
HTTP_ENABLED="false"
DIRECT_CIDRS="127.0.0.0/8"
DIRECT_DOMAINS="localhost"
NO_PROXY_EXTRA=""
HEALTH_TARGETS=""
EOF
    ;;
  mihomo)
    cat >"$BACKEND_CONFIG" <<EOF
mixed-port: $PORT
allow-lan: false
mode: direct
log-level: error
ipv6: false
EOF
    chmod 0600 "$BACKEND_CONFIG"
    cat >"$WORKDIR/proxy-agent.conf" <<EOF
BACKEND="mihomo"
MIHOMO_BIN="$BINARY_PATH"
MIHOMO_CONFIG="$BACKEND_CONFIG"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="$PORT"
HTTP_ENABLED="false"
DIRECT_CIDRS="127.0.0.0/8"
DIRECT_DOMAINS="localhost"
NO_PROXY_EXTRA=""
HEALTH_TARGETS=""
EOF
    ;;
  *)
    echo "unsupported backend: $BACKEND_NAME" >&2
    exit 2
    ;;
esac

chmod 0600 "$WORKDIR/proxy-agent.conf"
export PA_CONFIG="$WORKDIR/proxy-agent.conf" PA_STATE_DIR="$WORKDIR/state" PA_LOG_DIR="$WORKDIR/log"

"$ROOT/bin/proxy-ctl" validate
"$BINARY_PATH" version >/dev/null 2>&1 || "$BINARY_PATH" --version >/dev/null 2>&1 || true
"$ROOT/bin/proxy-ctl" start
"$ROOT/bin/proxy-ctl" status --json=v2 | grep -q '"status":"ready"'
"$ROOT/bin/proxy-ctl" stop

echo "PASS real backend: $BACKEND_NAME"
