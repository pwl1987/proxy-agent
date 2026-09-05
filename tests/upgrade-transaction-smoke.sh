#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

WORK="$TMP/work"
HOME_DIR="$TMP/home"
CONFIG_HOME="$HOME_DIR/.config"
PREFIX="$HOME_DIR/.local/lib/proxy-agent"
BIN="$HOME_DIR/.local/bin"
TREE="$TMP/tree"
STATE="$TMP/state"
PATH_BIN="$TMP/bin"
mkdir -p "$WORK" "$TREE/lib" "$TREE/bin" "$CONFIG_HOME/proxy-agent" "$PREFIX" "$BIN" "$STATE" "$PATH_BIN"
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
mkdir -p "${BIN:?}"
cat >"$BIN/proxy-ctl" <<'CTL'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == validate ]] || exit 2
exit 0
CTL
chmod +x "$BIN/proxy-ctl"
printf 'installed-%s\n' "$$" >>"$TREE_INSTALL_SENTINEL.log"
sleep 0.25
EOF
chmod +x "$TREE/install-user.sh"

cat >"$PATH_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --user)
    shift
    ;;
esac
case "${1:-}" in
  is-active)
    exit 0
    ;;
  stop)
    [[ -n "${RELEASE_ACTIVE_LOCK:-}" ]] && : >"$RELEASE_ACTIVE_LOCK"
    exit 0
    ;;
  daemon-reload)
    exit 0
    ;;
  start)
    exec "$PATH_BIN/prove-lock-release"
    ;;
  show-environment)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$PATH_BIN/systemctl"

cat >"$PATH_BIN/prove-lock-release" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$TREE/lib/state.sh"
timeout 2s bash -c 'source "$1"; state_lifecycle_lock_acquire; state_lifecycle_lock_release' _ "$TREE/lib/state.sh"
EOF
chmod +x "$PATH_BIN/prove-lock-release"

cat >"$TREE/hold-lock.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$TREE/lib/state.sh"
state_lifecycle_lock_acquire
touch "$ACTIVE_LOCK_HELD"
while [[ ! -e "$RELEASE_ACTIVE_LOCK" ]]; do sleep 0.02; done
state_lifecycle_lock_release
EOF
chmod +x "$TREE/hold-lock.sh"

export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$CONFIG_HOME"
export XDG_RUNTIME_DIR="$TMP/runtime"
export PA_STATE_DIR="$STATE"
export PREFIX="$PREFIX"
export BIN="$BIN"
export TREE_INSTALL_SENTINEL="$TMP/install-critical"
export TREE="$TREE"
export ACTIVE_LOCK_HELD="$TMP/active-lock-held"
export RELEASE_ACTIVE_LOCK="$TMP/release-active-lock"
export PATH="$PATH_BIN:$PATH"
mkdir -p "$XDG_RUNTIME_DIR"

# Model a running proxy-ctl run that owns the lifecycle lock. systemctl stop
# must run before upgrade acquires that lock; otherwise the old implementation
# deadlocks before it can ask systemd to stop the service.
rm -f "$ACTIVE_LOCK_HELD" "$RELEASE_ACTIVE_LOCK"
"$TREE/hold-lock.sh" >/"$TMP/holder.log" 2>&1 &
holder_pid=$!
for _ in {1..100}; do [[ -e "$ACTIVE_LOCK_HELD" ]] && break; sleep 0.02; done
[[ -e "$ACTIVE_LOCK_HELD" ]]
set +e
( cd "$TREE" && timeout 5s ./upgrade-user.sh ) >"$WORK/active-upgrade.log" 2>&1
active_rc=$?
set -e
wait "$holder_pid"
(( active_rc == 0 )) || { cat "$WORK/active-upgrade.log" >&2; exit 1; }

printf 'old-version\n' >"$PREFIX/marker"

set +e
( cd "$TREE" && ./upgrade-user.sh ) >"$WORK/a.log" 2>&1 &
pid_a=$!
sleep 0.03
( cd "$TREE" && ./upgrade-user.sh ) >"$WORK/b.log" 2>&1 &
pid_b=$!
wait "$pid_a"; rc_a=$?
wait "$pid_b"; rc_b=$?
set -e
(( rc_a == 0 )) || { cat "$WORK/a.log" >&2; exit 1; }
(( rc_b == 0 )) || { cat "$WORK/b.log" >&2; exit 1; }
[[ ! -d "$TREE_INSTALL_SENTINEL.active" ]]
[[ "$(wc -l <"$TREE_INSTALL_SENTINEL.log")" -eq 2 ]]

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

grep -q 'source "$ROOT/lib/state.sh"' "$TREE/upgrade-user.sh"
grep -q 'state_lifecycle_lock_acquire' "$TREE/upgrade-user.sh"

echo 'upgrade transaction smoke: PASS'
