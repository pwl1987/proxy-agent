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

curl -fsS "http://127.0.0.1:$PORT/healthz" | grep -q '"status":"ok"'

status="$(curl -sS -o "$TMP/unauth.body" -w '%{http_code}' "http://127.0.0.1:$PORT/api/v1/status")"
test "$status" = 401

auth_headers="$TMP/login.headers"
status="$(curl -sS -D "$auth_headers" -o "$TMP/login.body" -w '%{http_code}' \
  -c "$COOKIE_JAR" \
  -H 'Content-Type: application/json' \
  -d '{"token":"smoke-admin-token"}' \
  "http://127.0.0.1:$PORT/session/login")"
test "$status" = 200
grep -qi 'HttpOnly' "$auth_headers"
grep -qi 'SameSite=Strict' "$auth_headers"
csrf="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["csrf_token"])' "$TMP/login.body")"
test -n "$csrf"

curl -fsS -b "$COOKIE_JAR" "http://127.0.0.1:$PORT/session" | grep -q '"authenticated":true'

status="$(curl -sS -o "$TMP/session-status.body" -w '%{http_code}' \
  -b "$COOKIE_JAR" \
  "http://127.0.0.1:$PORT/api/v1/status")"
test "$status" = 502
grep -q 'control_api_unavailable' "$TMP/session-status.body"

status="$(curl -sS -o "$TMP/no-csrf.body" -w '%{http_code}' \
  -b "$COOKIE_JAR" \
  -X POST \
  -H 'Content-Type: application/json' \
  -d '{}' \
  "http://127.0.0.1:$PORT/api/v1/apply")"
test "$status" = 403
grep -q 'csrf_failed' "$TMP/no-csrf.body"

status="$(curl -sS -o "$TMP/csrf.body" -w '%{http_code}' \
  -b "$COOKIE_JAR" \
  -X POST \
  -H "X-CSRF-Token: $csrf" \
  -H 'Content-Type: application/json' \
  -d '{}' \
  "http://127.0.0.1:$PORT/api/v1/apply")"
test "$status" = 502
grep -q 'control_api_unavailable' "$TMP/csrf.body"

for _ in {1..5}; do
  status="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -d '{"token":"wrong-token"}' \
    "http://127.0.0.1:$PORT/session/login")"
  test "$status" = 401
done
status="$(curl -sS -o "$TMP/rate.body" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"token":"wrong-token"}' \
  "http://127.0.0.1:$PORT/session/login")"
test "$status" = 429
grep -q 'login_rate_limited' "$TMP/rate.body"

status="$(curl -sS -o "$TMP/method.body" -w '%{http_code}' \
  -X DELETE \
  "http://127.0.0.1:$PORT/api/v1/status")"
test "$status" = 405
grep -q 'method_not_allowed' "$TMP/method.body"

curl -sS -o /dev/null -w '%{http_code}' \
  -X POST \
  -b "$COOKIE_JAR" \
  "http://127.0.0.1:$PORT/session/logout" | grep -q '^204$'

status="$(curl -sS -o "$TMP/logout-session.body" -w '%{http_code}' \
  -b "$COOKIE_JAR" \
  "http://127.0.0.1:$PORT/session")"
test "$status" = 401

echo 'PASS: web gateway session, csrf, rate-limit and control-proxy smoke'