#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
CONFIG="$TMP/proxy-agent.conf"
trap 'rm -rf "$TMP"' EXIT

cat >"$CONFIG" <<'EOF'
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
LOCAL_PROXY_STATUS_TARGET="https://example.com"
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
HEALTH_RETRIES="2"
HEALTH_BACKOFF="2"
HEALTH_AUTO_RECOVER="true"
INTEGRATE_GIT="true"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="true"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$CONFIG"

output="$(
  HTTP_PROXY=preexisting \
  HTTPS_PROXY=preexisting \
  ALL_PROXY=preexisting \
  NO_PROXY=preexisting \
  PA_CONFIG="$CONFIG" \
  "$ROOT/bin/proxy-ctl" exec python3 -c 'import os,sys; print(os.environ.get("HTTP_PROXY")); print(os.environ.get("HTTPS_PROXY")); print(os.environ.get("ALL_PROXY")); print(os.environ.get("NO_PROXY")); print(sys.argv[1])' 'hello world'
)"

printf '%s\n' '--- exec environment ---' >&2
printf '%s\n' "$output" >&2

mapfile -t lines <<<"$output"
[[ "${#lines[@]}" -eq 5 ]]
[[ "${lines[0]}" == "http://127.0.0.1:3128" ]]
[[ "${lines[1]}" == "http://127.0.0.1:3128" ]]
[[ -z "${lines[2]}" ]]
[[ "${lines[3]}" == "127.0.0.0/8,localhost,internal.example" ]]
[[ "${lines[4]}" == "hello world" ]]

unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy
output="$(PA_CONFIG="$CONFIG" "$ROOT/bin/proxy-ctl" exec --off python3 -c 'import os; print(repr(os.environ.get("HTTP_PROXY"))); print(repr(os.environ.get("HTTPS_PROXY"))); print(repr(os.environ.get("ALL_PROXY"))); print(repr(os.environ.get("NO_PROXY")))')"
printf '%s\n' '--- exec --off environment ---' >&2
printf '%s\n' "$output" >&2
expected=$'None\nNone\nNone\nNone'
[[ "$output" == "$expected" ]]

if PA_CONFIG="$CONFIG" "$ROOT/bin/proxy-ctl" exec >/dev/null 2>&1; then
  echo 'cli exec smoke: expected missing command failure' >&2
  exit 1
fi

printf 'cli exec smoke: PASS\n'
