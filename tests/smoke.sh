#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/config" <<'EOF'
BACKEND="ssh-socks"
REMOTE_HOST="proxy.example.com"
REMOTE_USER="proxy"
REMOTE_PORT="22"
REMOTE_SSH_KEY="~/.ssh/id_ed25519"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
DIRECT_CIDRS="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
DIRECT_DOMAINS="localhost,.local,.cn"
NO_PROXY_EXTRA="internal.example"
HEALTH_TIMEOUT="1"
INTEGRATE_GIT="true"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="false"
INTEGRATE_NPM="false"
EOF

cat >"$TMP/local-config" <<'EOF'
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
LOCAL_PROXY_STATUS_TARGET="https://example.com"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
DIRECT_CIDRS="127.0.0.0/8"
DIRECT_DOMAINS="localhost"
HEALTH_TIMEOUT="1"
INTEGRATE_GIT="true"
INTEGRATE_DOCKER="true"
INTEGRATE_PIP="true"
INTEGRATE_NPM="true"
EOF

mkdir -p "$TMP/profiles"
sed 's/REMOTE_HOST="proxy.example.com"/REMOTE_HOST="profile.example"/' "$TMP/config" >"$TMP/profiles/work.conf"

run() { PA_CONFIG="$TMP/config" PA_STATE_DIR="$TMP/state" bash "$ROOT/bin/proxy-ctl" "$@"; }
run_local() { PA_CONFIG="$TMP/local-config" bash "$ROOT/bin/proxy-ctl" "$@"; }
run_profile() { PA_PROFILE_DIR="$TMP/profiles" bash "$ROOT/bin/proxy-ctl" --profile work "$@"; }
run_integration() { PA_CONFIG="$TMP/config" bash "$ROOT/bin/proxy-agent-integration" "$@"; }
run_local_integration() { PA_CONFIG="$TMP/local-config" bash "$ROOT/bin/proxy-agent-integration" "$@"; }
run_profile_inspect() { PA_PROFILE_DIR="$TMP/profiles" bash "$ROOT/bin/proxy-agent-profile" "$@"; }

for file in \
  "$ROOT/bin/proxy-ctl" "$ROOT/bin/proxy-agent-health" "$ROOT/bin/proxy-agent-integration" "$ROOT/bin/proxy-agent-profile" \
  "$ROOT/bin/proxy-agent-tui" "$ROOT/install.sh" "$ROOT/adapters/privoxy.sh" "$ROOT/backends/ssh-socks.sh" \
  "$ROOT/backends/local-endpoint.sh" "$ROOT/lib/common.sh" "$ROOT/lib/profile.sh" "$ROOT/lib/backend-capabilities.sh" \
  "$ROOT/lib/backend.sh" "$ROOT/integrations/common.sh" "$ROOT/integrations/git.sh" "$ROOT/integrations/docker.sh" \
  "$ROOT/integrations/pip.sh" "$ROOT/integrations/npm.sh"; do
  bash -n "$file"
done

[[ "$(run route example.cn)" == DIRECT* ]]
[[ "$(run route foo.local)" == DIRECT* ]]
[[ "$(run route 10.12.34.56)" == DIRECT* ]]
[[ "$(run route 8.8.8.8)" == PROXY* ]]
[[ "$(run env | grep -c '^unset HTTP_PROXY')" -eq 1 ]]
[[ "$(run env | grep -c '^export ALL_PROXY=')" -eq 1 ]]
[[ "$(run capabilities | grep -c '^socks5$')" -eq 1 ]]
[[ "$(run_profile status | grep -c 'profile: work')" -eq 1 ]]
[[ "$(run_profile status | grep -c 'remote: proxy@profile.example:22')" -eq 1 ]]
[[ "$(run_profile_inspect list | grep -c '^work$')" -eq 1 ]]
[[ "$(run_profile_inspect show work | grep -c 'REMOTE_SSH_KEY=\"<redacted>\"')" -eq 1 ]]
[[ "$(run_integration git | grep -c 'git config --global http.proxy')" -eq 1 ]]

[[ "$(run_local capabilities | grep -c '^http_native$')" -eq 1 ]]
[[ "$(run_local env | grep -c 'export ALL_PROXY=.*http://127.0.0.1:3128')" -eq 1 ]]
[[ "$(run_local_integration docker | grep -c 'Environment=\"HTTP_PROXY=http://127.0.0.1:3128\"')" -eq 1 ]]
[[ "$(run_local_integration pip | grep -c 'global.proxy \"http://127.0.0.1:3128\"')" -eq 1 ]]
[[ "$(run_local_integration npm | grep -c 'npm config set proxy \"http://127.0.0.1:3128\"')" -eq 1 ]]

! run doctor

echo 'PASS smoke tests'
