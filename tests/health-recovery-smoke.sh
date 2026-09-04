#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export PA_STATE_DIR="$TMP/state"
export PA_ACTIVE_PROFILE="smoke"
export BACKEND="http-connect"
export HEALTH_RECOVERY_MAX_ATTEMPTS=2
export HEALTH_RECOVERY_WINDOW=900
export HEALTH_RECOVERY_COOLDOWN=0

source "$ROOT/lib/common.sh"
source "$ROOT/lib/health.sh"
source "$ROOT/lib/state.sh"

health_recovery_allowed
health_recovery_allowed
if health_recovery_allowed; then
  echo 'expected recovery budget exhaustion' >&2
  exit 1
fi

python3 - "$PA_STATE_DIR/health-recovery.json" "$PA_STATE_DIR/health-history.jsonl" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text())
assert state["attempts"] == 2

events = [json.loads(line) for line in Path(sys.argv[2]).read_text().splitlines()]
assert events[-1]["result"] == "recovery_exhausted"
assert events[-1]["network"] == "blocked"
PY

health_recovery_reset
python3 - "$PA_STATE_DIR/health-recovery.json" <<'PY'
import json
import sys
from pathlib import Path
state = json.loads(Path(sys.argv[1]).read_text())
assert state == {"window_started": 0, "attempts": 0, "cooldown_until": 0}
PY

export HEALTH_RECOVERY_COOLDOWN=300
health_recovery_allowed
if health_recovery_allowed; then
  echo 'expected recovery cooldown' >&2
  exit 1
fi

python3 - "$PA_STATE_DIR/health-history.jsonl" <<'PY'
import json
import sys
from pathlib import Path
events = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert events[-1]["result"] == "recovery_cooldown"
assert events[-1]["network"] == "skipped"
PY

echo 'health recovery smoke: PASS'
