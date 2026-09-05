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

# Exercise the actual multi-process RMW path. With a budget of two and no
# cooldown, exactly two of many concurrent callers may reserve an attempt.
rm -rf "$PA_STATE_DIR"
export HEALTH_RECOVERY_COOLDOWN=0
mkdir -p "$TMP/workers"
for _ in {1..20}; do
  bash -c '
    set -euo pipefail
    source "$1/lib/common.sh"
    source "$1/lib/health.sh"
    source "$1/lib/state.sh"
    if health_recovery_allowed; then
      printf "%s\n" allowed
    else
      printf "%s\n" blocked
    fi
  ' _ "$ROOT" >"$TMP/workers/$RANDOM-$BASHPID" 2>&1 &
done
wait

python3 - "$PA_STATE_DIR/health-recovery.json" "$TMP/workers" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text())
assert state["attempts"] == 2, state
outputs = [p.read_text() for p in Path(sys.argv[2]).iterdir()]
assert sum(text.strip() == "allowed" for text in outputs) == 2, outputs
PY

echo 'health recovery smoke: PASS'
