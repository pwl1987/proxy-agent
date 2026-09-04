#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
SOCKET="$TMP/control.sock"
CONFIG="$TMP/proxy-agent.conf"
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

PA_CONFIG="$CONFIG" PA_API_SOCKET="$SOCKET" PA_STATE_DIR="$TMP/state" python3 "$ROOT/bin/proxy-agent-api" --socket "$SOCKET" >"$TMP/api.out" 2>"$TMP/api.err" &
PID=$!

for _ in {1..100}; do
  [[ -S "$SOCKET" ]] && break
  sleep 0.05
done
[[ -S "$SOCKET" ]]
[[ "$(stat -c '%a' "$SOCKET")" == "600" ]]

curl_unix() { curl --silent --show-error --fail --unix-socket "$SOCKET" "http://localhost$1"; }
post_json() { curl --silent --show-error --unix-socket "$SOCKET" -H 'Content-Type: application/json' -X POST --data "$2" "http://localhost$1"; }

curl_unix /api/v1/health >"$TMP/health.json"
curl_unix /api/v1/status >"$TMP/status.json"
curl_unix /api/v1/capabilities >"$TMP/capabilities.json"
curl_unix /api/v1/config >"$TMP/config.json"
curl_unix /api/v1/revisions >"$TMP/revisions0.json"
curl_unix /api/v1/metrics >"$TMP/metrics.txt"

python3 - "$TMP" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
health = json.loads((root / "health.json").read_text())
status = json.loads((root / "status.json").read_text())
caps = json.loads((root / "capabilities.json").read_text())
config = json.loads((root / "config.json").read_text())
revisions = json.loads((root / "revisions0.json").read_text())
metrics = (root / "metrics.txt").read_text()
assert health == {"api_version": "v1", "data": {"status": "ok", "transport": "ready"}, "kind": "health"}
assert status["data"]["backend"] == "local-endpoint"
assert caps["data"]["backend"] == "local-endpoint"
assert caps["data"]["capabilities"] == ["http_native", "stream_proxy"]
assert config["data"]["schema_version"] == 1
assert config["data"]["backend"]["type"] == "local-endpoint"
assert revisions["data"] == {"current": 0, "desired": 0, "revisions": []}
assert "proxy_agent_control_api_up 1" in metrics
PY

cat >"$TMP/revision.json" <<'EOF'
{"config":{"schema_version":1,"profile":"default","backend":{"type":"http-connect","options":{"proxy_url":"http://127.0.0.1:8080"}},"listeners":{"socks5":{"bind":"127.0.0.1","port":1080}},"routing":{"direct_cidrs":[],"direct_domains":[],"no_proxy_extra":[],"rules":[]},"health":{"network_required":false,"timeout":10,"retries":1,"backoff":1,"auto_recover":true,"targets":[]},"integrations":{"git":true,"docker":false,"pip":false,"npm":false},"security":{"ssh_host_key_checking":"yes","allow_public_listener":false}},"actor":"smoke","change_summary":"test revision"}
EOF
post_json /api/v1/revisions "$(cat "$TMP/revision.json")" >"$TMP/revision-created.json"
python3 - "$TMP/revision-created.json" <<'PY'
import json, sys
obj=json.load(open(sys.argv[1]))
assert obj["kind"] == "revision"
assert obj["data"]["revision"] == 1
PY

post_json /api/v1/apply '{"revision":1,"if_match_revision":1,"actor":"smoke"}' >"$TMP/applied.json"
python3 - "$TMP/applied.json" <<'PY'
import json, sys
obj=json.load(open(sys.argv[1]))
assert obj["kind"] == "apply"
assert obj["data"]["revision"] == 1
assert obj["data"]["desired_revision"] == 1
assert obj["data"]["reconcile"]["status"] == "projected"
assert obj["data"]["reconcile"]["observed_revision"] == 1
PY

conflict_status="$(curl --silent --show-error --unix-socket "$SOCKET" -o "$TMP/conflict.json" -w '%{http_code}' -H 'Content-Type: application/json' -X POST --data '{"revision":1,"if_match_revision":0}' http://localhost/api/v1/apply)"
[[ "$conflict_status" == "409" ]]
grep -q 'revision_conflict' "$TMP/conflict.json"

rollback_status="$(curl --silent --show-error --unix-socket "$SOCKET" -o "$TMP/rollback.json" -w '%{http_code}' -H 'Content-Type: application/json' -X POST --data '{"revision":1,"if_match_revision":1,"actor":"smoke"}' http://localhost/api/v1/rollback)"
[[ "$rollback_status" == "202" ]]
python3 - "$TMP/rollback.json" <<'PY'
import json, sys
obj=json.load(open(sys.argv[1]))
assert obj["data"]["reconcile"]["status"] == "projected"
assert obj["data"]["reconcile"]["observed_revision"] == obj["data"]["revision"]
PY

printf 'control API smoke: PASS\n'
