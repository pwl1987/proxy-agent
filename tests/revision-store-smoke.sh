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
import json
import sys

obj = json.loads(sys.argv[1])
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

echo 'revision store smoke: PASS'
