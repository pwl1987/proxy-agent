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
python3 -c 'import importlib.machinery, importlib.util; p="sys-import-check"; l=importlib.machinery.SourceFileLoader(p, "bin/proxy-agent-web"); s=importlib.util.spec_from_loader(p,l); m=importlib.util.module_from_spec(s); l.exec_module(m); print("core-import=PASS")'

if python3 "$GATEWAY" --listen 0.0.0.0 --port "$PORT" --admin-token-file "$TOKEN_FILE" >"$LOG" 2>&1; then
  echo "expected non-loopback listener without TLS to fail" >&2
  exit 1
fi
grep -q 'non-loopback management listener requires' "$LOG" || { cat "$LOG" >&2; exit 1; }

printf '%s\n' 'placeholder' >"$TMP/tls.crt"
printf '%s\n' 'placeholder' >"$TMP/tls.key"
if python3 "$GATEWAY" --listen 0.0.0.0 --port "$PORT" --admin-token-file "$TOKEN_FILE" --tls-cert "$TMP/tls.crt" --tls-key "$TMP/tls.key" >"$LOG" 2>&1; then
  echo "expected non-loopback listener without explicit ACL to fail" >&2
  exit 1
fi
grep -q 'requires at least one --allow-cidr' "$LOG" || { cat "$LOG" >&2; exit 1; }

if python3 "$GATEWAY" --listen 127.0.0.1 --port "$PORT" --admin-token-file "$TOKEN_FILE" --allow-cidr 'not-a-cidr' >"$LOG" 2>&1; then
  echo "expected invalid management ACL CIDR to fail" >&2
  exit 1
fi
grep -q 'invalid management ACL CIDR' "$LOG" || { cat "$LOG" >&2; exit 1; }

python3 "$GATEWAY" \
  --listen 127.0.0.1 \
  --port "$PORT" \
  --control-socket "$TMP/missing-control.sock" \
  --admin-token-file "$TOKEN_FILE" \
  --allow-cidr '192.0.2.0/24' >"$LOG" 2>&1 &
GATEWAY_PID=$!

for _ in {1..30}; do
  if ! kill -0 "$GATEWAY_PID" 2>/dev/null; then
    echo 'Web UI process exited before readiness:' >&2
    cat "$LOG" >&2
    exit 1
  fi
  if curl -sS "http://127.0.0.1:$PORT/healthz" -o "$TMP/healthz.body" -w '%{http_code}' >"$TMP/healthz.status" 2>/dev/null; then
    if grep -q '^403$' "$TMP/healthz.status"; then break; fi
  fi
  sleep 0.1
done

test "$(cat "$TMP/healthz.status" 2>/dev/null || true)" = 403 || { echo 'ACL deny readiness failed' >&2; cat "$LOG" >&2; cat "$TMP/healthz.body" >&2 || true; exit 1; }
grep -q 'network_not_allowed' "$TMP/healthz.body"

kill "$GATEWAY_PID" 2>/dev/null || true
wait "$GATEWAY_PID" 2>/dev/null || true
GATEWAY_PID=''

PA_WEB_ALLOW_CIDRS='127.0.0.1/32' python3 "$GATEWAY" \
  --listen 127.0.0.1 \
  --port "$PORT" \
  --control-socket "$TMP/missing-control.sock" \
  --admin-token-file "$TOKEN_FILE" >"$LOG" 2>&1 &
GATEWAY_PID=$!

for _ in {1..30}; do
  if ! kill -0 "$GATEWAY_PID" 2>/dev/null; then
    echo 'Web UI process exited before readiness:' >&2
    cat "$LOG" >&2
    exit 1
  fi
  if curl -sS "http://127.0.0.1:$PORT/healthz" -o "$TMP/healthz.body" -w '%{http_code}' >"$TMP/healthz.status" 2>/dev/null; then
    if grep -q '^200$' "$TMP/healthz.status"; then break; fi
  fi
  sleep 0.1
done

test "$(cat "$TMP/healthz.status" 2>/dev/null || true)" = 200 || { echo 'healthz readiness failed' >&2; cat "$LOG" >&2; cat "$TMP/healthz.body" >&2 || true; exit 1; }
grep -q '"status":"ok"' "$TMP/healthz.body"
grep -q 'acl=127.0.0.1/32' "$LOG"

status="$(curl -sS -D "$TMP/ui.headers" -o "$TMP/ui.html" -w '%{http_code}' "http://127.0.0.1:$PORT/" || true)"
echo "ui_http_status=$status"
if [[ "$status" != 200 ]]; then cat "$LOG" >&2; cat "$TMP/ui.html" >&2 || true; exit 1; fi
grep -q 'proxy-agent.*Web Management' "$TMP/ui.html"
grep -q '校验.*Diff' "$TMP/ui.html"
grep -q '/api/v1/validate' "$TMP/ui.html"
grep -q '/api/v1/revisions' "$TMP/ui.html"
grep -q '/api/v1/apply' "$TMP/ui.html"
grep -q 'config-form.js' "$TMP/ui.html"
grep -qi 'Cache-Control: no-store' "$TMP/ui.headers"

status="$(curl -sS -D "$TMP/js.headers" -o "$TMP/config-form.js" -w '%{http_code}' "http://127.0.0.1:$PORT/config-form.js" || true)"
test "$status" = 200 || { cat "$LOG" >&2; cat "$TMP/config-form.js" >&2 || true; exit 1; }
grep -q 'structured-config' "$TMP/config-form.js"
grep -q 'ssh-socks' "$TMP/config-form.js"
grep -q 'egress_path' "$TMP/config-form.js"
grep -qi 'no-store' "$TMP/js.headers"

status="$(curl -sS -D "$TMP/login.headers" -o "$TMP/login.body" -w '%{http_code}' \
  -c "$COOKIE_JAR" \
  -H 'Content-Type: application/json' \
  -d '{"token":"smoke-admin-token"}' \
  "http://127.0.0.1:$PORT/session/login")"
test "$status" = 200 || { cat "$LOG" >&2; cat "$TMP/login.body" >&2; exit 1; }
csrf="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["csrf_token"])' "$TMP/login.body")"
test -n "$csrf"

grep -qi 'HttpOnly' "$TMP/login.headers"
grep -qi 'SameSite=Strict' "$TMP/login.headers"

status="$(curl -sS -o "$TMP/status.body" -w '%{http_code}' -b "$COOKIE_JAR" \
  "http://127.0.0.1:$PORT/api/v1/status")"
test "$status" = 502 || { cat "$TMP/status.body" >&2; exit 1; }
grep -q 'control_api_unavailable' "$TMP/status.body"

echo 'PASS: web UI structured configuration, management ACL and gateway integration smoke'
