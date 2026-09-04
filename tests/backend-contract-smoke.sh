#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

install -d -m 0700 "$TMP/state" "$TMP/log"
cat >"$TMP/mihomo.yaml" <<'EOF'
mixed-port: 1080
allow-lan: false
mode: rule
log-level: silent
EOF
chmod 0600 "$TMP/mihomo.yaml"

cat >"$TMP/mihomo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  -t)
    [[ "${2:-}" == -f && -n "${3:-}" ]]
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod 0755 "$TMP/mihomo"

source "$ROOT/lib/common.sh"
source "$ROOT/lib/backend.sh"
source "$ROOT/backends/mihomo.sh"

BACKEND=mihomo
SOCKS_BIND=127.0.0.1
SOCKS_PORT=1080
MIHOMO_BIN="$TMP/mihomo"
MIHOMO_CONFIG="$TMP/mihomo.yaml"
PA_STATE_DIR="$TMP/state"
PA_LOG_DIR="$TMP/log"

backend_mihomo_validate
[[ "$(backend_mihomo_endpoint)" == socks5h://127.0.0.1:1080 ]]
backend_mihomo_managed
! backend_mihomo_pid >/dev/null 2>&1
! backend_mihomo_liveness
[[ "$(backend_mihomo_capabilities | paste -sd, -)" == 'socks5,stream_proxy' ]]

echo 'PASS mihomo backend contract'
