#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY="$ROOT/bin/proxy-agent-web-ui"
TMP="$(mktemp -d)"
trap 'kill "${GATEWAY_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT

TOKEN_FILE="$TMP/admin.token"
printf '%s\n' 'smoke-admin-token' >"$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"
PORT=18444
LOG="$TMP/ui.log"
COOKIE_JAR="$TMP/cookies.txt"

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

curl -fsS -D "$TMP/ui.headers" "http://127.0.0.1:$PORT/" -o "$TMP/ui.html"
grep -q 'proxy-agent.*Web Management' "$TMP/ui.html"
grep -q 'Validate.*Diff' "$TMP/ui.html"
grep -q '/api/v1/validate' "$TMP/ui.html"
grep -q '/api/v1/revisions' "$TMP/ui.html"
grep -q '/api/v1/apply' "$TMP/ui.html"
grep -qi 'Cache-Control: no-store' "$TMP/ui.headers"

status="$(curl -sS -D "$TMP/login.headers" -o "$TMP/login.body" -w '%{http_code}' \
  -c "$COOKIE_JAR" \
  -H 'Content-Type: application/json' \
  -d '{"token":"smoke-admin-token"}' \
  "http://127.0.0.1:$PORT/session/login")"
test "$status" = 200
csrf="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["csrf_token"])' "$TMP/login.body")"
test -n "$csrf"

status="$(curl -sS -o "$TMP/status.body" -w '%{http_code}' -b "$COOKIE_JAR" \
  "http://127.0.0.1:$PORT/api/v1/status")"
test "$status" = 502
grep -q 'control_api_unavailable' "$TMP/status.body"

echo 'PASS: web UI config editor and gateway integration smoke'