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
if [[ "${1:-}" == --user ]]; then
  shift
fi
case "${1:-}" in
  is-active)
    [[ "${FAKE_SYSTEMD_ACTIVE:-false}" == true ]]
    ;;
  stop)
    : >"${FAKE_SYSTEMD_STOP_SIGNAL:?}"
    ;;
  daemon-reload|start)
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$PATH_BIN/systemctl"

cat >"$WORK/hold-lock.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$1/lib/state.sh"
state_lifecycle_lock_acquire
trap 'state_lifecycle_lock_release' EXIT
: >"$2/holder-ready"
while [[ ! -e "$2/stop-signal" ]]; do
  sleep 0.02
done
EOF
chmod +x "$WORK/hold-lock.sh"

export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$CONFIG_HOME"
export XDG_RUNTIME_DIR="$TMP/runtime"
export PA_STATE_DIR="$STATE"
export PREFIX="$PREFIX"
export BIN="$BIN"
export TREE_INSTALL_SENTINEL="$TMP/install-critical"
export PATH="$PATH_BIN:$PATH"
mkdir -p "$XDG_RUNTIME_DIR"

printf 'old-version\n' >"$PREFIX/marker"

# Regression guard: an active service owns the lifecycle lock while upgrade
# starts. systemctl stop must run before upgrade acquires that lock, otherwise
# this transaction deadlocks indefinitely.
export FAKE_SYSTEMD_ACTIVE=true
export FAKE_SYSTEMD_STOP_SIGNAL="$TMP/stop-signal"
rm -f "$TMP/holder-ready" "$TMP/stop-signal"
"$WORK/hold-lock.sh" "$TREE" "$TMP" >"$WORK/holder.log" 2>&1 &
holder_pid=$!
for _ in {1..100}; do
  [[ -e "$TMP/holder-ready" ]] && break
  sleep 0.02
done
[[ -e "$TMP/holder-ready" ]] || { cat "$WORK/holder.log" >&2; kill "$holder_pid" 2>/dev/null || true; exit 1; }
set +e
( cd "$TREE" && ./upgrade-user.sh ) >"$WORK/active-service.log" 2>&1 &
active_upgrade_pid=$!
set -e
for _ in {1..100}; do
  [[ -e "$TMP/stop-signal" ]] && break
  sleep 0.02
done
[[ -e "$TMP/stop-signal" ]] || { cat "$WORK/active-service.log" >&2; kill "$active_upgrade_pid" "$holder_pid" 2>/dev/null || true; exit 1; }
wait "$holder_pid"
wait "$active_upgrade_pid"
unset FAKE_SYSTEMD_ACTIVE

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
[[ "$(wc -l <"$TREE_INSTALL_SENTINEL.log")" -eq 3 ]]

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
