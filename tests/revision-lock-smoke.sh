#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PA_STATE_DIR="$TMP/state"
mkdir -p "$PA_STATE_DIR"
source "$ROOT/lib/revision-store.sh"
lock="$(revision_lock_dir)"
mkdir -p "$lock"
if revision_lock_is_stale; then exit 1; fi
printf '%s\n' "$(( $(date +%s) - 31 ))" >"$lock/created"
revision_lock_is_stale
rm -rf "$lock"
echo 'revision lock smoke: PASS'