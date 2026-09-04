#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/proxy-agent.conf" <<'EOF'
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
LOCAL_PROXY_STATUS_TARGET="https://example.com"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
SSH_STRICT_HOST_KEY_CHECKING="yes"
DIRECT_CIDRS="127.0.0.0/8,10.0.0.0/8"
DIRECT_DOMAINS="localhost,.cn"
NO_PROXY_EXTRA="git.internal"
ROUTE_RULES=$'100|DIRECT|suffix|.internal.example\n200|PROXY|wildcard|*.example.net'
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
chmod 0600 "$TMP/proxy-agent.conf"

PA_CONFIG="$TMP/proxy-agent.conf" bash "$ROOT/bin/proxy-ctl" config export-typed >"$TMP/typed.json"

python3 - "$TMP/typed.json" <<'PY'
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["schema_version"] == 1
assert doc["backend"]["type"] == "local-endpoint"
assert doc["backend"]["options"]["proxy_url"] == "http://127.0.0.1:3128"
assert doc["backend"]["options"]["status_target"] == "https://example.com"
assert doc["routing"]["rules"][0]["priority"] == 100
assert doc["routing"]["rules"][0]["action"] == "direct"
assert doc["routing"]["rules"][1]["action"] == "proxy"
assert doc["security"]["allow_public_listener"] is False
PY

printf 'typed config CLI smoke: PASS\n'
