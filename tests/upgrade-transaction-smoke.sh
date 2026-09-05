#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# This test exercises the rootless upgrade entrypoint with a fake installer/service.
# The fake installer deliberately holds a critical-section directory so overlapping
# upgrades fail; the shared lifecycle lock must serialize both invocations.
WORK="$TMP/work"
HOME_DIR="$TMP/home"
CONFIG_HOME="$HOME_DIR/.config"
PREFIX="$HOME_DIR/.local/lib/proxy-agent"
BIN="$HOME_DIR/.local/bin"
TREE="$TMP/tree"
STATE="$TMP/state"
PATH_BIN="$TMP/bin"
mkdir -p "$TREE/lib" "$TREE/bin" "$CONFIG_HOME/proxy-agent" "$PREFIX" "$BIN" "$STATE" "$PATH_BIN"
cp "$ROOT/upgrade-user.sh" "$TREE/upgrade-user.sh"
cp "$ROOT/lib/state.sh" "$TREE/lib/state.sh"
printf '0.4.0\n' >"$TREE/VERSION"
cat >"$CONFIG_HOME/proxy-agent/proxy-agent.conf" <<'EOF'
BACKEND="http-connect"
HTTP_CONNECT_PROXY_URL="http://127.0.0.1:3128"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
SSH_STRICT_HOST_KEY_CHECKING="yes"
DIRECT_CIDRS=""
DIRECT_DOMAINS=""
NO_PROXY_EXTRA=""
ROUTE_RULES=""
HEALTH_TARGETS=""
HEALTH_NETWORK_REQUIRED="false"
HEALTH_TIMEOUT="10"
HEALTH_RETRIES="1"
HEALTH_BACKOFF="1"
HEALTH_AUTO_RECOVER="true"
INTEGRATE_GIT="false"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="false"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$CONFIG_HOME/proxy-agent/proxy-agent.conf"

cat >"$TREE/install-user.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${TREE_INSTALL_SENTINEL:?}"
active="$TREE_INSTALL_SENTINEL.active"
if ! mkdir "$active" 2>/dev/null; then
  echo 'overlapping upgrade transaction detected' >&2
  exit 90
fi
trap 'rmdir "$active"' EXIT
printf 'installed-%s\n' "$$" >"$TREE_INSTALL_SENTINEL.last"
sleep 0.25
EOF
chmod +x "$TREE/install-user.sh"

cat >"$TREE/bin/proxy-ctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == validate ]] || exit 2
exit 0
EOF
chmod +x "$TREE/bin/proxy-ctl"

# Neutralize host systemd so the smoke is deterministic and exercises file/state transaction only.
cat >"$PATH_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$PATH_BIN/systemctl"

export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$CONFIG_HOME"
export XDG_RUNTIME_DIR="$TMP/runtime"
export PA_STATE_DIR="$STATE"
export PREFIX="$PREFIX"
export BIN="$BIN"
export TREE_INSTALL_SENTINEL="$TMP/install-critical"
export PATH="$PATH_BIN:$PATH"
mkdir -p "$XDG_RUNTIME_DIR"

# Seed the installed program with an old marker so rollback can be checked later.
printf 'old-version\n' >"$PREFIX/marker"

# Two concurrent upgrades must serialize on the same lifecycle lock.
set +e
( cd "$TREE" && ./upgrade-user.sh ) >"$WORK-a.log" 2>&1 &
pid_a=$!
sleep 0.03
( cd "$TREE" && ./upgrade-user.sh ) >"$WORK-b.log" 2>&1 &
pid_b=$!
wait "$pid_a"; rc_a=$?
wait "$pid_b"; rc_b=$?
set -e
(( rc_a == 0 )) || { cat "$WORK-a.log" >&2; exit 1; }
(( rc_b == 0 )) || { cat "$WORK-b.log" >&2; exit 1; }
[[ ! -d "$TREE_INSTALL_SENTINEL.active" ]]
[[ "$(grep -c '^installed-' "$TREE_INSTALL_SENTINEL.last")" -eq 1 ]]

# Rollback path: make the installer mutate the prefix and then fail validation.
cat >"$TREE/install-user.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'new-version\n' >"${PREFIX:?}/marker"
exit 91
EOF
chmod +x "$TREE/install-user.sh"
set +e
( cd "$TREE" && ./upgrade-user.sh ) >"$TMP/rollback.log" 2>&1
rc=$?
set -e
(( rc != 0 )) || { cat "$TMP/rollback.log" >&2; exit 1; }
[[ "$(cat "$PREFIX/marker")" == 'old-version' ]]
[[ -f "$CONFIG_HOME/proxy-agent/proxy-agent.conf" ]]

# Static contract: both upgrade entrypoints must source and acquire the lifecycle lock.
grep -q 'source "$ROOT/lib/state.sh"' "$TREE/upgrade-user.sh"
grep -q 'state_lifecycle_lock_acquire' "$TREE/upgrade-user.sh"

printf 'upgrade transaction smoke: PASS\n'
