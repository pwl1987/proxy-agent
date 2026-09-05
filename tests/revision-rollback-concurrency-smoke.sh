#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PA_STATE_DIR="$TMP/state"
mkdir -p "$PA_STATE_DIR"
source "$ROOT/lib/revision-store.sh"

config='{"schema_version":1,"profile":"default","backend":{"type":"http-connect","options":{"proxy_url":"http://127.0.0.1:3128"}},"listeners":{},"health":{},"integrations":{},"routing":{},"security":{}}'
r1="$(revision_record "$config" test initial passed ready)"
r2="$(revision_record "$config" test second passed ready)"
[[ "$r1" == 1 && "$r2" == 2 ]]
revision_set_desired 2 "$config"

if revision_rollback_if_match 1 1 test stale >/dev/null 2>&1; then
  echo 'stale rollback unexpectedly succeeded' >&2
  exit 1
fi
[[ "$(revision_current)" == 2 ]]
[[ "$(revision_desired_revision)" == 2 ]]

r3="$(revision_rollback_if_match 2 1 test 'rollback to revision 1')"
[[ "$r3" == 3 ]]
[[ "$(revision_current)" == 3 ]]
[[ "$(revision_desired_revision)" == 3 ]]
python3 - "$(revision_get 3)" "$(revision_desired)" <<'PY'
import json, sys
record = json.loads(sys.argv[1])
desired = json.loads(sys.argv[2])
assert record["previous_revision"] == 2
assert record["rollback_target_revision"] == 1
assert record["config"] == desired
PY

echo 'revision rollback concurrency smoke: PASS'
