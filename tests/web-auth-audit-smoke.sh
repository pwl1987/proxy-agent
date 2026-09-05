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
PORT=18445
mkdir -p "$STATE"
printf '%s\n' 'smoke-admin-token' >"$TOKEN"
chmod 0600 "$TOKEN"

PA_STATE_DIR="$STATE" python3 -m py_compile "$API" "$WEB"
PA_STATE_DIR="$STATE" python3 "$API" --socket "$SOCKET" >"$TMP/api.log" 2>&1 &
API_PID=$!

for _ in {1..30}; do
  [[ -S "$SOCKET" ]] && break
  sleep 0.1
done
test -S "$SOCKET"

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

events="$STATE/audit/events.jsonl"
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

grep -q '"event":"login.success"' "$events"
grep -q '"status":"succeeded"' "$events"

echo 'web auth audit smoke: PASS'
