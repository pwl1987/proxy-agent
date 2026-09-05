#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
SOCKET="$TMP/control.sock"
CONFIG="$TMP/proxy-agent.conf"
trap '[[ -z "${PID:-}" ]] || kill "$PID" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

cat >"$CONFIG" <<'EOF'
BACKEND="http-connect"
HTTP_CONNECT_PROXY_URL="http://127.0.0.1:3128"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
SSH_STRICT_HOST_KEY_CHECKING="yes"
DIRECT_CIDRS=""
DIRECT_DOMAINS=""
NO_PROXY_EXTRA=""
ROUTE_RULES=""
HEALTH_TARGETS=""
HEALTH_NETWORK_REQUIRED="false"
HEALTH_TIMEOUT="10"
HEALTH_RETRIES="1"
HEALTH_BACKOFF="1"
HEALTH_AUTO_RECOVER="true"
INTEGRATE_GIT="false"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="false"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$CONFIG"

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" env -i PATH="$PATH" HOME="$HOME" PA_CONFIG="$CONFIG" PA_API_SOCKET="$SOCKET" PA_STATE_DIR="$TMP/state" PA_LOG_DIR="$TMP/log" /usr/bin/python3 "$ROOT/bin/proxy-agent-api" --socket "$SOCKET" >"$TMP/api.out" 2>"$TMP/api.err" &
PID=$!
for _ in {1..100}; do [[ -S "$SOCKET" ]] && break; sleep 0.05; done
[[ -S "$SOCKET" ]]

validate() {
  curl --silent --show-error --unix-socket "$SOCKET" -o "$2" -w '%{http_code}' \
    -H 'Content-Type: application/json' -X POST --data "$3" "http://localhost/api/v1/validate"
}

valid='{"config":{"schema_version":1,"backend":{"type":"http-connect","options":{"proxy_url":"http://127.0.0.1:3128"}},"listeners":{"socks5":{"bind":"127.0.0.1","port":1080},"http":{"enabled":false,"bind":"127.0.0.1","port":8118}},"routing":{"direct_cidrs":[],"direct_domains":[],"no_proxy_extra":[],"rules":[]},"health":{"network_required":false,"timeout":10,"retries":1,"backoff":1,"auto_recover":true,"targets":[]},"integrations":{"git":false,"docker":false,"pip":false,"npm":false},"security":{"ssh_host_key_checking":"yes","allow_public_listener":false}}}'
code="$(validate "$TMP/unused" "$TMP/valid.json" "$valid")"
[[ "$code" == 200 ]]
grep -q '"valid":true' "$TMP/valid.json"

invalid='{"config":{"schema_version":1,"backend":{"type":"http-connect","options":{"proxy_url":"http://127.0.0.1:3128"}},"listeners":{"socks5":{"bind":"127.0.0.1","port":99999},"http":{"enabled":false,"bind":"127.0.0.1","port":8118}},"routing":{"direct_cidrs":[],"direct_domains":[],"no_proxy_extra":[],"rules":[]},"health":{"network_required":false,"timeout":10,"retries":1,"backoff":1,"auto_recover":true,"targets":[]},"integrations":{"git":false,"docker":false,"pip":false,"npm":false},"security":{"ssh_host_key_checking":"yes","allow_public_listener":false}}}'
code="$(validate "$TMP/unused" "$TMP/invalid.json" "$invalid")"
[[ "$code" == 422 ]]
grep -q 'invalid_config' "$TMP/invalid.json"

echo 'control API validation smoke: PASS'
