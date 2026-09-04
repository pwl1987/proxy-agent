#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f -- "$SCRIPT_PATH")"
fi
ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export PA_STATE_DIR="$TMP_DIR/state"

# shellcheck source=/dev/null
source "$ROOT/lib/revision-store.sh"

config='{"schema_version":1,"backend":{"type":"local-endpoint"},"listeners":{},"health":{},"integrations":{},"routing":{},"security":{}}'

first="$(revision_record "$config" tester initial passed pending)"
[[ "$first" == 1 ]]
[[ "$(revision_current)" == 1 ]]

if revision_record_if_match 0 "$config" tester stale passed pending >/dev/null 2>&1; then
  echo 'expected stale revision create to be rejected' >&2
  exit 1
fi
[[ "$(revision_current)" == 1 ]]

second="$(revision_record_if_match 1 "$config" tester second passed pending)"
[[ "$second" == 2 ]]
[[ "$(revision_current)" == 2 ]]

revision_set_desired 1 "$config"
[[ "$(revision_desired_revision)" == 1 ]]

if revision_set_desired_if_match 1 1 "$config" >/dev/null 2>&1; then
  echo 'expected stale desired-state update to be rejected' >&2
  exit 1
fi
[[ "$(revision_desired_revision)" == 1 ]]

revision_set_desired_if_match 2 2 "$config"
[[ "$(revision_desired_revision)" == 2 ]]

echo 'revision-store concurrency tests: PASS'
