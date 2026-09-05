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

run_pair() {
  local label="$1" a_rc b_rc
  set +e
  ( "$TMP/proxy-ctl" "$2" "$3" ) >"$TMP/${label}-a.log" 2>&1 & pid_a=$!
  sleep 0.03
  ( "$TMP/proxy-ctl" "$4" "$5" ) >"$TMP/${label}-b.log" 2>&1 & pid_b=$!
  wait "$pid_a"; a_rc=$?
  wait "$pid_b"; b_rc=$?
  set -e
  if (( a_rc != 0 || b_rc != 0 )); then
    echo "${label}: first_rc=${a_rc} second_rc=${b_rc}" >&2
    cat "$TMP/${label}-a.log" >&2 || true
    cat "$TMP/${label}-b.log" >&2 || true
    return 1
  fi
}

run_pair plain start '' restart ''
[[ "$(wc -l <"$STATE/events")" -eq 2 ]] || { echo 'plain lifecycle did not record two operations' >&2; exit 1; }
[[ -f "$STATE/.lifecycle.lock" ]] || { echo 'plain lifecycle lock file missing' >&2; exit 1; }

rm -f "$STATE/.lifecycle.lock"
run_pair profile --profile demo --profile demo
[[ "$(wc -l <"$STATE/events")" -eq 4 ]] || { echo 'profile lifecycle did not record two operations' >&2; exit 1; }
[[ -f "$STATE/.lifecycle.lock" ]] || { echo 'profile lifecycle lock file missing' >&2; exit 1; }

rm -f "$STATE/.lifecycle.lock"
"$TMP/proxy-ctl" status
[[ ! -e "$STATE/.lifecycle.lock" ]] || { echo 'read-only status unexpectedly created lifecycle lock' >&2; exit 1; }

echo 'cli lifecycle lock smoke: PASS'
