#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTLESS_HOME="$(mktemp -d /tmp/proxy-agent-rootless.XXXXXX)"
trap 'rm -rf "$ROOTLESS_HOME"' EXIT

install -d -m 0700 "$ROOTLESS_HOME" "$ROOTLESS_HOME/runtime"
chown -R runner:runner "$ROOTLESS_HOME"

sudo -u runner env \
  HOME="$ROOTLESS_HOME" \
  XDG_CONFIG_HOME="$ROOTLESS_HOME/.config" \
  XDG_RUNTIME_DIR="$ROOTLESS_HOME/runtime" \
  BIN="$ROOTLESS_HOME/bin" \
  PREFIX="$ROOTLESS_HOME/lib/proxy-agent" \
  GITHUB_WORKSPACE="$ROOT" \
  bash "$ROOT/install-user.sh"

test -f "$ROOTLESS_HOME/.config/proxy-agent/proxy-agent.conf"
test -x "$ROOTLESS_HOME/bin/proxy-ctl"
grep -q "^ExecStart=$ROOTLESS_HOME/bin/proxy-ctl run$" "$ROOTLESS_HOME/.config/systemd/user/proxy-agent.service"
grep -q '^Environment=PA_STATE_DIR=%t/proxy-agent/run$' "$ROOTLESS_HOME/.config/systemd/user/proxy-agent.service"

audited_config="$ROOTLESS_HOME/.config/proxy-agent/proxy-agent.conf"
sudo -u runner env \
  HOME="$ROOTLESS_HOME" \
  XDG_CONFIG_HOME="$ROOTLESS_HOME/.config" \
  XDG_RUNTIME_DIR="$ROOTLESS_HOME/runtime" \
  bash -c 'cat >"$XDG_CONFIG_HOME/proxy-agent/proxy-agent.conf" <<EOF
BACKEND="local-endpoint"
LOCAL_PROXY_URL="http://127.0.0.1:3128"
HTTP_ENABLED="false"
HEALTH_TIMEOUT="1"
HEALTH_RETRIES="0"
HEALTH_BACKOFF="0"
HEALTH_AUTO_RECOVER="false"
HEALTH_NETWORK_REQUIRED="false"
EOF
chmod 0600 "$XDG_CONFIG_HOME/proxy-agent/proxy-agent.conf"'

sudo -u runner env \
  HOME="$ROOTLESS_HOME" \
  XDG_CONFIG_HOME="$ROOTLESS_HOME/.config" \
  XDG_RUNTIME_DIR="$ROOTLESS_HOME/runtime" \
  PA_CONFIG="$audited_config" \
  PA_STATE_DIR="$ROOTLESS_HOME/runtime/state" \
  "$ROOTLESS_HOME/bin/proxy-ctl" validate

echo 'PASS rootless smoke'
