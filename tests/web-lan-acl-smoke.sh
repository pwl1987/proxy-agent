#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY="$ROOT/bin/proxy-agent-web-ui"
TMP="$(mktemp -d)"
trap 'kill "${GATEWAY_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT

TOKEN_FILE="$TMP/admin.token"
printf '%s\n' 'smoke-admin-token' >"$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"
PORT=18445
LOG="$TMP/web-ui.log"

python3 "$GATEWAY" --help >/dev/null
if python3 "$GATEWAY" --listen 127.0.0.1 --port "$PORT" --admin-token-file "$TOKEN_FILE" --allow-cidr 'not-a-cidr' >"$LOG" 2>&1; then
  echo "expected invalid management ACL CIDR to fail" >&2
  exit 1
fi
grep -q 'invalid management ACL CIDR' "$LOG"

python3 "$GATEWAY" \
  --listen 127.0.0.1 \
  --port "$PORT" \
  --control-socket "$TMP/missing-control.sock" \
  --admin-token-file "$TOKEN_FILE" \
  --allow-cidr '192.0.2.0/24' >"$LOG" 2>&1 &
GATEWAY_PID=$!

for _ in {1..30}; do
  if curl -sS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then break; fi
  sleep 0.1
done

status="$(curl -sS -o "$TMP/blocked.body" -w '%{http_code}' "http://127.0.0.1:$PORT/healthz")"
test "$status" = 403
grep -q 'network_not_allowed' "$TMP/blocked.body"

kill "$GATEWAY_PID" 2>/dev/null || true
wait "$GATEWAY_PID" 2>/dev/null || true
GATEWAY_PID=''

python3 "$GATEWAY" \
  --listen 127.0.0.1 \
  --port "$PORT" \
  --control-socket "$TMP/missing-control.sock" \
  --admin-token-file "$TOKEN_FILE" \
  --allow-cidr '127.0.0.1/32' >"$LOG" 2>&1 &
GATEWAY_PID=$!

for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then break; fi
  sleep 0.1
done

curl -fsS "http://127.0.0.1:$PORT/healthz" | grep -q '"status":"ok"'

status="$(PA_WEB_ALLOW_CIDRS='192.0.2.0/24' python3 "$GATEWAY" --listen 127.0.0.1 --port "$PORT" --admin-token-file "$TOKEN_FILE" --control-socket "$TMP/other.sock" --allow-cidr '127.0.0.1/32' >/dev/null 2>&1 & echo $!)"
kill "$status" 2>/dev/null || true
wait "$status" 2>/dev/null || true

echo 'PASS: web management listener ACL, CIDR validation and deny/allow boundary smoke'