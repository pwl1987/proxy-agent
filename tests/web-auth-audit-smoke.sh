#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="$ROOT/bin/proxy-agent-api-auth"
TMP="$(mktemp -d)"
trap 'kill "${API_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT

SOCKET="$TMP/control.sock"
STATE="$TMP/state"
mkdir -p "$STATE"

PA_STATE_DIR="$STATE" python3 -m py_compile "$API" "$ROOT/bin/proxy-agent-web-ui"
PA_STATE_DIR="$STATE" python3 "$API" --socket "$SOCKET" >"$TMP/api.log" 2>&1 &
API_PID=$!

for _ in {1..30}; do
  [[ -S "$SOCKET" ]] && break
  sleep 0.1
done
test -S "$SOCKET"

status="$(curl -sS --unix-socket "$SOCKET" -o "$TMP/body" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"event":"login.failure","status":"failed","peer":"127.0.0.1","reason":"invalid_credentials"}' \
  http://localhost/api/v1/auth-events)"
test "$status" = 202
grep -q '"accepted":true' "$TMP/body"

events="$STATE/audit/events.jsonl"
test -s "$events"
grep -q '"event":"login.failure"' "$events"
grep -q '"actor":"web-gateway"' "$events"
grep -q '"reason":"invalid_credentials"' "$events"
! grep -q 'token' "$events"

status="$(curl -sS --unix-socket "$SOCKET" -o "$TMP/rejected" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"event":"arbitrary.event","peer":"127.0.0.1"}' \
  http://localhost/api/v1/auth-events)"
test "$status" = 400

echo 'web auth audit smoke: PASS'
