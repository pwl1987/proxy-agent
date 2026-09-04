#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PA_STATE_DIR="$TMP/state"
mkdir -p "$PA_STATE_DIR"
source "$ROOT/lib/revision-store.sh"

config='{"schema_version":1,"profile":"default","backend":{"type":"http-connect","options":{"proxy_url":"http://127.0.0.1:3128"}}}'

[[ "$(revision_current)" == 0 ]]
r1="$(revision_record "$config" "test" "initial" "passed" "ready")"
[[ "$r1" == 1 ]]
[[ "$(revision_current)" == 1 ]]
python3 - "$(revision_get 1)" <<'PY'
import json, sys
obj=json.loads(sys.argv[1])
assert obj["revision"] == 1
assert obj["previous_revision"] == 0
assert obj["actor"] == "test"
assert obj["validation_result"] == "passed"
assert obj["health_result"] == "ready"
assert obj["config"]["backend"]["type"] == "http-connect"
PY

r2="$(revision_record "$config" "test" "second" "passed" "ready")"
[[ "$r2" == 2 ]]
[[ "$(revision_current)" == 2 ]]
[[ "$(revision_list)" == $'0000000002.json\n0000000001.json' ]]

# The compare-and-write primitive must reject a stale head without creating a revision.
if revision_record_if_match 1 "$config" "test" "stale" "passed" "ready" >/dev/null 2>&1; then
  echo 'stale revision create unexpectedly succeeded' >&2; exit 1
fi
[[ "$(revision_current)" == 2 ]]

revision_set_desired 1 "$config"
[[ "$(revision_desired_revision)" == 1 ]]
if revision_set_desired_if_match 1 1 "$config" >/dev/null 2>&1; then
  echo 'stale desired-state update unexpectedly succeeded' >&2; exit 1
fi
[[ "$(revision_desired_revision)" == 1 ]]
revision_set_desired_if_match 2 2 "$config"
[[ "$(revision_desired_revision)" == 2 ]]

# A lock directory without owner metadata is a crash window. It must not be
# deleted immediately; after the stale threshold a writer may recover it.
lock="$(revision_lock_dir)"
mkdir -p "$lock"
if revision_lock_is_stale; then
  echo 'fresh ownerless revision lock incorrectly marked stale' >&2; exit 1
fi
printf '%s\n' "$(( $(date +%s) - 31 ))" >"$lock/created"
if ! revision_lock_is_stale; then
  echo 'old ownerless revision lock was not marked stale' >&2; exit 1
fi
rm -rf "$lock"

# A live PID with a different process starttime is stale; a matching process
# starttime is not stale. This guards against PID reuse.
mkdir -p "$lock"
printf '%s\n' "$$" >"$lock/pid"
printf '%s\n' "$(revision_proc_starttime "$$")" >"$lock/starttime"
printf '%s\n' "$(date +%s)" >"$lock/created"
if revision_lock_is_stale; then
  echo 'live revision lock incorrectly marked stale' >&2; exit 1
fi
printf '%s\n' 1 >"$lock/starttime"
if ! revision_lock_is_stale; then
  echo 'PID-reused revision lock was not marked stale' >&2; exit 1
fi
rm -rf "$lock"

echo 'revision store smoke: PASS'