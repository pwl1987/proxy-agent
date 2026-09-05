#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="$ROOT/bin/proxy-agent-api-auth"
WEB="$ROOT/bin/proxy-agent-web-ui"
TMP="$(mktemp -d)"
trap 'kill "${WEB_PID:-}" "${API_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT

SOCKET="$TMP/control.sock"
STATE="$TMP/state"
TOKEN="$TMP/admin.token"
PROFILE_DIR="$TMP/profiles"
PORT=18445
mkdir -p "$STATE" "$PROFILE_DIR"
printf '%s\n' 'smoke-admin-token' >"$TOKEN"
chmod 0600 "$TOKEN"
cat >"$PROFILE_DIR/work.conf" <<'EOF'
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
LOCAL_PROXY_STATUS_TARGET="https://example.com"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
HEALTH_NETWORK_REQUIRED="false"
HEALTH_TIMEOUT="5"
HEALTH_RETRIES="0"
HEALTH_BACKOFF="0"
HEALTH_AUTO_RECOVER="true"
INTEGRATE_GIT="true"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="false"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$PROFILE_DIR/work.conf"

PA_STATE_DIR="$STATE" python3 -m py_compile "$API" "$WEB"
PA_PROFILE_DIR="$PROFILE_DIR" PA_STATE_DIR="$STATE" python3 "$API" --socket "$SOCKET" >"$TMP/api.log" 2>&1 &
API_PID=$!

for _ in {1..30}; do
  [[ -S "$SOCKET" ]] && break
  sleep 0.1
done
test -S "$SOCKET"

events="$STATE/audit/events.jsonl"

PA_STATE_DIR="$STATE" python3 "$WEB" \
  --listen 127.0.0.1 \
  --port "$PORT" \
  --control-socket "$SOCKET" \
  --admin-token-file "$TOKEN" >"$TMP/web.log" 2>&1 &
WEB_PID=$!

for _ in {1..30}; do
  if curl -sS "http://127.0.0.1:$PORT/healthz" -o "$TMP/healthz.body" -w '%{http_code}' >"$TMP/healthz.status" 2>/dev/null; then
    grep -q '^200$' "$TMP/healthz.status" && break
  fi
  sleep 0.1
done
test "$(cat "$TMP/healthz.status")" = 200

status="$(curl -sS -o "$TMP/failure.body" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"token":"wrong-token"}' \
  "http://127.0.0.1:$PORT/session/login")"
test "$status" = 401

for _ in {1..20}; do [[ -s "$events" ]] && break; sleep 0.1; done
test -s "$events"
grep -q '"event":"login.failure"' "$events"
grep -q '"actor":"web-gateway"' "$events"
grep -q '"reason":"invalid_credentials"' "$events"
! grep -q 'wrong-token' "$events"

status="$(curl -sS -c "$TMP/cookies.txt" -o "$TMP/success.body" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"token":"smoke-admin-token"}' \
  "http://127.0.0.1:$PORT/session/login")"
test "$status" = 200

csrf="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["csrf_token"])' "$TMP/success.body")"
test -n "$csrf"
grep -q '"event":"login.success"' "$events"
grep -q '"status":"succeeded"' "$events"

profiles="$(curl -sS -b "$TMP/cookies.txt" "http://127.0.0.1:$PORT/api/v1/profiles")"
PROFILE_JSON="$profiles" python3 - <<'PY'
import json, os
obj = json.loads(os.environ["PROFILE_JSON"])
assert obj["api_version"] == "v1", obj
assert obj["kind"] == "profiles", obj
assert obj["data"]["profiles"] == ["work"], obj
PY

status="$(curl -sS -o "$TMP/profiles-unauth.body" -w '%{http_code}' "http://127.0.0.1:$PORT/api/v1/profiles")"
test "$status" = 401

rm -rf "$STATE/audit"
printf '%s\n' 'audit-store-disabled-for-smoke' >"$STATE/audit"

status="$(curl --silent --show-error --unix-socket "$SOCKET" \
  -o "$TMP/remote-mutation-audit-failed.json" \
  -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -X POST \
  --data '{"actor":"web-ui"}' \
  "http://localhost/api/v1/runtime/start")"
test "$status" = 503
python3 - "$TMP/remote-mutation-audit-failed.json" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1]))
assert obj["error"]["code"] == "audit_unavailable", obj
assert "remote mutation audit could not be committed" in obj["error"]["message"], obj
PY

test -f "$STATE/audit"
! grep -q 'runtime.start' "$TMP/api.log"

echo 'web auth audit smoke: PASS'
