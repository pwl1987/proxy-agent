#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
CONFIG="$TMP/source.conf"
PROFILE_DIR="$TMP/profiles"
STATE_DIR="$TMP/state"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$PROFILE_DIR" "$STATE_DIR"
cat >"$CONFIG" <<'EOF'
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
LOCAL_PROXY_STATUS_TARGET=""
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
SSH_STRICT_HOST_KEY_CHECKING="yes"
DIRECT_CIDRS="127.0.0.0/8"
DIRECT_DOMAINS="localhost"
NO_PROXY_EXTRA="internal.example"
ROUTE_RULES=""
HEALTH_TARGETS=""
HEALTH_NETWORK_REQUIRED="false"
HEALTH_TIMEOUT="10"
HEALTH_RETRIES="1"
HEALTH_BACKOFF="1"
HEALTH_AUTO_RECOVER="false"
INTEGRATE_GIT="true"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="true"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$CONFIG"

installed="$(
  PA_CONFIG="$CONFIG" PA_PROFILE_DIR="$PROFILE_DIR" PA_STATE_DIR="$STATE_DIR" \
    "$ROOT/bin/proxy-ctl" agent install --profile coding
)"
printf '%s\n' "$installed"
test -f "$PROFILE_DIR/coding.conf"
test "$(stat -c '%a' "$PROFILE_DIR/coding.conf")" = 600

PA_PROFILE_DIR="$PROFILE_DIR" PA_STATE_DIR="$STATE_DIR" \
  "$ROOT/bin/proxy-ctl" agent env --profile coding --json >"$TMP/env.json"
python3 - "$TMP/env.json" <<'PY'
import json, sys
obj=json.load(open(sys.argv[1]))
assert obj["schema_version"] == 1
assert obj["profile"] == "coding"
assert obj["http_proxy"] == "http://127.0.0.1:3128"
assert obj["https_proxy"] == "http://127.0.0.1:3128"
assert obj["all_proxy"] == ""
assert obj["no_proxy"] == "127.0.0.0/8,localhost,internal.example"
PY

PA_PROFILE_DIR="$PROFILE_DIR" PA_STATE_DIR="$STATE_DIR" \
  "$ROOT/bin/proxy-ctl" agent env --profile coding --shell bash >"$TMP/env.sh"
grep -q 'export HTTP_PROXY=' "$TMP/env.sh"
grep -q 'export NO_PROXY=' "$TMP/env.sh"

PA_PROFILE_DIR="$PROFILE_DIR" PA_STATE_DIR="$STATE_DIR" \
  "$ROOT/bin/proxy-ctl" agent status --profile coding --json >"$TMP/status.json"
python3 - "$TMP/status.json" <<'PY'
import json, sys
obj=json.load(open(sys.argv[1]))
assert obj["schema_version"] == 1
assert obj["profile"] == "coding"
assert obj["backend"]["name"] == "local-endpoint"
assert obj["integrations"] == {"docker": False, "git": True, "npm": False, "pip": True}
PY

printf 'agent environment smoke: PASS\n'
