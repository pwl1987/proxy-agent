#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PA_STATE_DIR="$TMP/state"
mkdir -p "$PA_STATE_DIR"
# shellcheck disable=SC1091
source "$ROOT/lib/state.sh"

worker() {
  local id="$1"
  state_lifecycle_lock_acquire
  local active=0
  [[ -r "$TMP/active" ]] && active="$(cat "$TMP/active")"
  (( active == 0 )) || { echo "overlap detected by worker $id" >&2; state_lifecycle_lock_release; return 1; }
  printf '1\n' >"$TMP/active"
  printf 'start %s\n' "$id" >>"$TMP/events"
  sleep 0.15
  printf 'end %s\n' "$id" >>"$TMP/events"
  printf '0\n' >"$TMP/active"
  state_lifecycle_lock_release
}

pids=()
for i in {1..8}; do
  worker "$i" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

python3 - "$TMP/events" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
assert len(lines) == 16, lines
active = 0
for line in lines:
    kind, _worker = line.split()
    if kind == "start":
        active += 1
        assert active == 1, lines
    else:
        active -= 1
        assert active == 0, lines
assert active == 0
PY

# Verify that a Python fcntl holder blocks the same lock file used by the shell helper.
python3 - "$TMP/state/.lifecycle.lock" <<'PY' &
import fcntl, pathlib, sys, time
path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("a+b") as handle:
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    pathlib.Path(str(path) + ".held").write_text("1")
    time.sleep(0.4)
PY
holder=$!
for _ in {1..50}; do [[ -e "$TMP/state/.lifecycle.lock.held" ]] && break; sleep 0.02; done
[[ -e "$TMP/state/.lifecycle.lock.held" ]]
start_ns="$(date +%s%N)"
state_lifecycle_lock_acquire
elapsed_ms="$(( ( $(date +%s%N) - start_ns ) / 1000000 ))"
state_lifecycle_lock_release
wait "$holder"
(( elapsed_ms >= 250 )) || { echo "lifecycle lock did not block on Python holder: ${elapsed_ms}ms" >&2; exit 1; }

# A caller-controlled symlink must be rejected before the lock helper applies
# permissions or otherwise mutates the pointed-to inode.
target="$TMP/lock-target"
printf 'sentinel\n' >"$target"
ln -s "$target" "$TMP/state/.lifecycle.lock"
set +e
( state_lifecycle_lock_acquire ) >"$TMP/symlink.out" 2>&1
symlink_rc=$?
set -e
(( symlink_rc != 0 )) || { cat "$TMP/symlink.out" >&2; exit 1; }
[[ -L "$TMP/state/.lifecycle.lock" ]]
[[ "$(cat "$target")" == 'sentinel' ]]

rm -f "$TMP/state/.lifecycle.lock"

echo 'lifecycle lock smoke: PASS'
