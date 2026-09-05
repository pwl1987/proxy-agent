#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY="$ROOT/bin/proxy-agent-web"
TMP="$(mktemp -d)"
trap 'kill "${GATEWAY_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT

TOKEN_FILE="$TMP/admin.token"
printf '%s\n' 'smoke-admin-token' >"$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"
PORT=18443
LOG="$TMP/gateway.log"

python3 "$GATEWAY" --help >/dev/null

if python3 "$GATEWAY" --listen 0.0.0.0 --port "$PORT" --admin-token-file "$TOKEN_FILE" >"$LOG" 2>&1; then
  echo "expected non-loopback listener without TLS to fail" >&2
  exit 1
fi
grep -q 'non-loopback management listener requires' "$LOG"

python3 "$GATEWAY" \
  --listen 127.0.0.1 \
  --port "$PORT" \
  --control-socket "$TMP/missing-control.sock" \
  --admin-token-file "$TOKEN_FILE" >"$LOG" 2>&1 &
GATEWAY_PID=$!

for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then break; fi
  sleep 0.1
done

curl -fsS "http://127.0.0.1:$PORT/healthz" | grep -q '"status":"ok"'

status="$(curl -sS -o "$TMP/unauth.body" -w '%{http_code}' "http://127.0.0.1:$PORT/api/v1/status")"
test "$status" = 401
grep -q 'WWW-Authenticate' "$TMP/headers" 2>/dev/null || true

status="$(curl -sS -o "$TMP/auth.body" -w '%{http_code}' \
  -H 'Authorization: Bearer smoke-admin-token' \
  "http://127.0.0.1:$PORT/api/v1/status")"
test "$status" = 502
grep -q 'control_api_unavailable' "$TMP/auth.body"

status="$(curl -sS -o "$TMP/mutation.body" -w '%{http_code}' \
  -X POST \
  -H 'Authorization: Bearer smoke-admin-token' \
  -H 'Content-Type: application/json' \
  -d '{}' \
  "http://127.0.0.1:$PORT/api/v1/apply")"
test "$status" = 405
grep -q 'read_only_gateway' "$TMP/mutation.body"

echo 'PASS: web gateway security foundation smoke'
