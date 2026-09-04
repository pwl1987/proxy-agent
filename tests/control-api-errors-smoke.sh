#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
SOCKET="$TMP/control.sock"
CONFIG="$TMP/proxy-agent.conf"
RECONCILER="$TMP/reconcile-fail.sh"
trap '[[ -z "${PID:-}" ]] || kill "$PID" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

cat >"$CONFIG" <<'EOF'
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
LOCAL_PROXY_STATUS_TARGET="https://example.com"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
SSH_STRICT_HOST_KEY_CHECKING="yes"
DIRECT_CIDRS="127.0.0.0/8"
DIRECT_DOMAINS="localhost"
NO_PROXY_EXTRA=""
ROUTE_RULES=$'100|DIRECT|suffix|.internal.example'
HEALTH_TARGETS="https://example.com"
HEALTH_NETWORK_REQUIRED="false"
HEALTH_TIMEOUT="10"
HEALTH_RETRIES="2"
HEALTH_BACKOFF="2"
HEALTH_AUTO_RECOVER="true"
INTEGRATE_GIT="true"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="true"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$CONFIG"

cat >"$RECONCILER" <<'EOF'
#!/usr/bin/env bash
printf 'forced activation failure for smoke test\n' >&2
exit 42
EOF
chmod 0755 "$RECONCILER"

PA_CONFIG="$CONFIG" PA_API_SOCKET="$SOCKET" PA_STATE_DIR="$TMP/state" PA_RECONCILER="$RECONCILER" python3 "$ROOT/bin/proxy-agent-api" --socket "$SOCKET" >"$TMP/api.out" 2>"$TMP/api.err" &
PID=$!

for _ in {1..100}; do
  [[ -S "$SOCKET" ]] && break
  sleep 0.05
done
[[ -S "$SOCKET" ]]
[[ "$(stat -c '%a' "$SOCKET")" == "600" ]]

curl_unix() { curl --silent --show-error --fail --unix-socket "$SOCKET" "http://localhost$1"; }
post_status() { curl --silent --show-error --unix-socket "$SOCKET" -o "$2" -w '%{http_code}' -H 'Content-Type: application/json' -X POST --data "$3" "http://localhost$1"; }

status="$(post_status /api/v1/validate "$TMP/invalid.json" '{"config":{"schema_version":1}}')"
[[ "$status" == "422" ]]
grep -q '"invalid_config"' "$TMP/invalid.json"

cat >"$TMP/revision.json" <<'EOF'
{"config":{"schema_version":1,"profile":"default","backend":{"type":"http-connect","options":{"proxy_url":"http://127.0.0.1:8080"}},"listeners":{"socks5":{"bind":"127.0.0.1","port":1080}},"routing":{"direct_cidrs":[],"direct_domains":[],"no_proxy_extra":[],"rules":[]},"health":{"network_required":false,"timeout":10,"retries":1,"backoff":1,"auto_recover":true,"targets":[]},"integrations":{"git":true,"docker":false,"pip":false,"npm":false},"security":{"ssh_host_key_checking":"yes","allow_public_listener":false}},"actor":"smoke","change_summary":"activation failure test"}
EOF

revision_status="$(post_status /api/v1/revisions "$TMP/revision-created.json" "$(cat "$TMP/revision.json")")"
[[ "$revision_status" == "201" ]]

activation_status="$(post_status /api/v1/apply "$TMP/activation-failed.json" '{"revision":1,"if_match_revision":1,"actor":"smoke"}')"
echo "--- activation failure status: $activation_status ---"
cat "$TMP/activation-failed.json"
[[ "$activation_status" == "503" ]]
grep -q '"activation_failed"' "$TMP/activation-failed.json"
grep -q 'forced activation failure for smoke test' "$TMP/activation-failed.json"

curl_unix /api/v1/events >"$TMP/events.json"
python3 - "$TMP/events.json" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1]))
events = obj["data"]
assert any(
    e.get("event") == "desired_state.activation_failed"
    and e.get("revision") == 1
    and e.get("status") == "failed"
    and "forced activation failure" in e.get("error", "")
    for e in events
)
PY

printf 'control API error smoke: PASS\n'
