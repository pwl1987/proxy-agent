#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STATE="$TMP/state"
mkdir -p "$STATE" "$TMP/lib"
cp "$ROOT/lib/state.sh" "$TMP/lib/state.sh"

cat >"$TMP/proxy-ctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/state.sh"
case "${1:-}" in
  start|stop|restart|run)
    printf 'started %s\n' "$$" >>"$PA_STATE_DIR/events"
    sleep 0.25
    ;;
  --profile)
    printf 'started %s\n' "$$" >>"$PA_STATE_DIR/events"
    sleep 0.25
    ;;
  *)
    :
    ;;
esac
EOF
chmod +x "$TMP/proxy-ctl"

export PA_STATE_DIR="$STATE"

# Two lifecycle commands through a proxy-ctl-shaped caller must serialize on the
# same per-runtime lock. The marker duration makes overlap observable.
set +e
( "$TMP/proxy-ctl" start ) & pid_a=$!
sleep 0.03
( "$TMP/proxy-ctl" restart ) & pid_b=$!
wait "$pid_a"; rc_a=$?
wait "$pid_b"; rc_b=$?
set -e
(( rc_a == 0 ))
(( rc_b == 0 ))
[[ "$(wc -l <"$STATE/events")" -eq 2 ]]
[[ -f "$STATE/.lifecycle.lock" ]]

# The --profile dispatch also maps to the same lifecycle lock.
rm -f "$STATE/.lifecycle.lock"
set +e
( "$TMP/proxy-ctl" --profile demo start ) & pid_a=$!
sleep 0.03
( "$TMP/proxy-ctl" --profile demo restart ) & pid_b=$!
wait "$pid_a"; rc_a=$?
wait "$pid_b"; rc_b=$?
set -e
(( rc_a == 0 ))
(( rc_b == 0 ))
[[ "$(wc -l <"$STATE/events")" -eq 4 ]]
[[ -f "$STATE/.lifecycle.lock" ]]

# A non-lifecycle command must not contend on the lifecycle lock.
rm -f "$STATE/.lifecycle.lock"
"$TMP/proxy-ctl" status
[[ ! -e "$STATE/.lifecycle.lock" ]]

echo 'cli lifecycle lock smoke: PASS'
