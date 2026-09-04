#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
SOCKET="$TMP/control.sock"
CONFIG="$TMP/proxy-agent.conf"
PID=""
trap '[[ -z "$PID" ]] || kill "$PID" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

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

PA_CONFIG="$CONFIG" PA_API_SOCKET="$SOCKET" python3 "$ROOT/bin/proxy-agent-api" --socket "$SOCKET" >"$TMP/api.out" 2>"$TMP/api.err" &
PID=$!

for _ in {1..100}; do
  [[ -S "$SOCKET" ]] && break
  sleep 0.05
done
[[ -S "$SOCKET" ]]
[[ "$(stat -c '%a' "$SOCKET")" == "600" ]]

curl_unix() {
  curl --silent --show-error --fail --unix-socket "$SOCKET" "http://localhost$1"
}

curl_unix /api/v1/health >"$TMP/health.json"
curl_unix /api/v1/status >"$TMP/status.json"
curl_unix /api/v1/capabilities >"$TMP/capabilities.json"
curl_unix /api/v1/config >"$TMP/config.json"
curl_unix /api/v1/metrics >"$TMP/metrics.txt"

python3 - "$TMP" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
health = json.loads((root / "health.json").read_text())
status = json.loads((root / "status.json").read_text())
caps = json.loads((root / "capabilities.json").read_text())
config = json.loads((root / "config.json").read_text())
metrics = (root / "metrics.txt").read_text()

assert health == {"api_version": "v1", "data": {"status": "ok", "transport": "ready"}, "kind": "health"}
assert status["api_version"] == "v1"
assert status["kind"] == "status"
assert status["data"]["backend"] == "local-endpoint"
assert caps["data"]["backend"] == "local-endpoint"
assert caps["data"]["capabilities"] == ["http_native", "stream_proxy"]
assert config["data"]["schema_version"] == 1
assert config["data"]["backend"]["type"] == "local-endpoint"
assert "proxy_agent_control_api_up 1" in metrics
PY

post_status="$(curl --silent --show-error --unix-socket "$SOCKET" -o "$TMP/post.json" -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data '{}' http://localhost/api/v1/apply)"
[[ "$post_status" == "501" ]]
grep -q '"not_implemented"' "$TMP/post.json"

unknown_status="$(curl --silent --show-error --unix-socket "$SOCKET" -o "$TMP/unknown.json" -w '%{http_code}' http://localhost/api/v1/does-not-exist)"
[[ "$unknown_status" == "404" ]]
grep -q '"not_found"' "$TMP/unknown.json"

printf 'control API smoke: PASS\n'
