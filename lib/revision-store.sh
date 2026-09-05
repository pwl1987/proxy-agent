#!/usr/bin/env bash
set -euo pipefail

revision_dir() { printf '%s/revisions' "$PA_STATE_DIR"; }
revision_head_file() { printf '%s/head' "$(revision_dir)"; }
revision_lock_dir() { printf '%s/.revision.lock' "$PA_STATE_DIR"; }
revision_proc_starttime() {
  local pid="$1"
  [[ -r "/proc/$pid/stat" ]] || return 1
  awk '{print $22}' "/proc/$pid/stat"
}
revision_lock_is_stale() {
  local lock="$(revision_lock_dir)" pid start created now current
  [[ -d "$lock" ]] || return 1
  pid="$(cat "$lock/pid" 2>/dev/null || true)"
  start="$(cat "$lock/starttime" 2>/dev/null || true)"
  created="$(cat "$lock/created" 2>/dev/null || true)"
  now="$(date +%s)"
  if [[ -z "$pid" || -z "$start" ]]; then
    [[ "$created" =~ ^[0-9]+$ ]] && (( now - created > 30 ))
    return
  fi
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  if ! current="$(revision_proc_starttime "$pid" 2>/dev/null)"; then return 0; fi
  [[ "$current" != "$start" ]]
}
revision_lock_reclaim() {
  local lock="$(revision_lock_dir)" guard="$(revision_lock_dir).reclaim" stale="${lock}.stale.$$.$RANDOM" created now
  if ! mkdir "$guard" 2>/dev/null; then
    created="$(cat "$guard/created" 2>/dev/null || true)"
    now="$(date +%s)"
    if [[ "$created" =~ ^[0-9]+$ ]] && (( now - created > 30 )); then
      rm -rf "$guard" 2>/dev/null || true
    else
      return 1
    fi
    mkdir "$guard" 2>/dev/null || return 1
  fi
  printf '%s\n' "$$" >"$guard/pid"
  printf '%s\n' "$(date +%s)" >"$guard/created"
  if revision_lock_is_stale; then
    if mv "$lock" "$stale" 2>/dev/null; then
      rm -rf "$stale"
      return 0
    fi
  fi
  rm -rf "$guard" 2>/dev/null || true
  return 1
}
revision_lock_acquire() {
  revision_init
  local lock="$(revision_lock_dir)" now
  for _ in {1..100}; do
    if mkdir "$lock" 2>/dev/null; then
      now="$(date +%s)"
      printf '%s\n' "$$" >"$lock/pid"
      printf '%s\n' "$(revision_proc_starttime "$$" 2>/dev/null || printf 0)" >"$lock/starttime"
      printf '%s\n' "$now" >"$lock/created"
      return 0
    fi
    if revision_lock_is_stale; then
      revision_lock_reclaim || true
      continue
    fi
    sleep 0.05
  done
  printf '%s\n' "revision store is locked: $lock" >&2
  return 1
}
revision_lock_release() {
  local lock="$(revision_lock_dir)" pid start current
  [[ -d "$lock" ]] || return 0
  pid="$(cat "$lock/pid" 2>/dev/null || true)"
  start="$(cat "$lock/starttime" 2>/dev/null || true)"
  current="$(revision_proc_starttime "$$" 2>/dev/null || true)"
  [[ "$pid" == "$$" && -n "$start" && "$start" == "$current" ]] || return 1
  rm -rf "$lock"
}

revision_next_id() {
  local current=0
  if [[ -r "$(revision_head_file)" ]]; then current="$(cat "$(revision_head_file)")"; fi
  [[ "$current" =~ ^[0-9]+$ ]] || current=0
  printf '%d' "$((current + 1))"
}

revision_init() {
  mkdir -p "$(revision_dir)"
  if [[ ! -e "$(revision_head_file)" ]]; then printf '0\n' >"$(revision_head_file)"; fi
}

revision_file() { printf '%s/%010d.json' "$(revision_dir)" "$1"; }
revision_desired_file() { printf '%s/desired.json' "$(revision_dir)"; }
revision_desired_revision_file() { printf '%s/desired_revision' "$(revision_dir)"; }
revision_current() { revision_init; cat "$(revision_head_file)"; }

revision_record() {
  local config_json="$1" actor="${2:-local}" summary="${3:-configuration change}" validation="${4:-passed}" health="${5:-pending}"
  revision_init
  revision_lock_acquire || return 1
  local id="$(revision_next_id)" timestamp file tmp previous
  previous="$(revision_current)"
  timestamp="$(date +%s)"
  file="$(revision_file "$id")"
  tmp="${file}.tmp.$$"
  if ! python3 - "$config_json" "$actor" "$summary" "$validation" "$health" "$id" "$previous" "$timestamp" >"$tmp" <<'PY'
import json, sys
config = json.loads(sys.argv[1])
payload = {"schema_version": 1, "revision": int(sys.argv[6]), "previous_revision": int(sys.argv[7]), "timestamp": int(sys.argv[8]), "actor": sys.argv[2], "change_summary": sys.argv[3], "validation_result": sys.argv[4], "health_result": sys.argv[5], "config": config}
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
PY
  then rm -f "$tmp"; revision_lock_release; return 1; fi
  mv -f "$tmp" "$file"
  printf '%s\n' "$id" >"$(revision_head_file)"
  revision_lock_release
  printf '%s' "$id"
}

revision_record_if_match() {
  local expected="$1" config_json="$2" actor="${3:-local}" summary="${4:-configuration change}" validation="${5:-passed}" health="${6:-pending}"
  revision_init; revision_lock_acquire || return 1
  local current; current="$(revision_current)"
  if [[ "$expected" != "$current" ]]; then printf 'revision conflict: expected revision %s, current revision is %s\n' "$expected" "$current" >&2; revision_lock_release; return 3; fi
  local id="$(revision_next_id)" timestamp file tmp previous; previous="$current"; timestamp="$(date +%s)"; file="$(revision_file "$id")"; tmp="${file}.tmp.$$"
  if ! python3 - "$config_json" "$actor" "$summary" "$validation" "$health" "$id" "$previous" "$timestamp" >"$tmp" <<'PY'
import json, sys
config=json.loads(sys.argv[1]); payload={"schema_version":1,"revision":int(sys.argv[6]),"previous_revision":int(sys.argv[7]),"timestamp":int(sys.argv[8]),"actor":sys.argv[2],"change_summary":sys.argv[3],"validation_result":sys.argv[4],"health_result":sys.argv[5],"config":config}; print(json.dumps(payload,ensure_ascii=False,separators=(",",":"),sort_keys=True))
PY
  then rm -f "$tmp"; revision_lock_release; return 1; fi
  mv -f "$tmp" "$file"; printf '%s\n' "$id" >"$(revision_head_file)"; revision_lock_release; printf '%s' "$id"
}

revision_get() { local id="$1" file; [[ "$id" =~ ^[0-9]+$ ]] || return 1; file="$(revision_file "$id")"; [[ -r "$file" ]] || return 1; cat "$file"; }
revision_list() { revision_init; find "$(revision_dir)" -maxdepth 1 -type f -name '[0-9]*.json' -printf '%f\n' | sort -r; }

revision_set_desired() {
  local id="$1" config_json="$2" dir tmp; revision_get "$id" >/dev/null || return 1; revision_lock_acquire || return 1; dir="$(revision_dir)"; tmp="$(revision_desired_file).tmp.$$"
  if ! printf '%s\n' "$config_json" >"$tmp"; then rm -f "$tmp"; revision_lock_release; return 1; fi
  mv -f "$tmp" "$(revision_desired_file)"; tmp="$(revision_desired_revision_file).tmp.$$"; printf '%s\n' "$id" >"$tmp"; mv -f "$tmp" "$(revision_desired_revision_file)"; revision_lock_release
}
revision_set_desired_if_match() {
  local expected="$1" id="$2" config_json="$3" dir tmp; revision_get "$id" >/dev/null || return 1; revision_lock_acquire || return 1; local current; current="$(revision_current)"
  if [[ "$expected" != "$current" ]]; then printf 'revision conflict: expected revision %s, current revision is %s\n' "$expected" "$current" >&2; revision_lock_release; return 3; fi
  dir="$(revision_dir)"; tmp="$(revision_desired_file).tmp.$$"; if ! printf '%s\n' "$config_json" >"$tmp"; then rm -f "$tmp"; revision_lock_release; return 1; fi
  mv -f "$tmp" "$(revision_desired_file)"; tmp="$(revision_desired_revision_file).tmp.$$"; printf '%s\n' "$id" >"$tmp"; mv -f "$tmp" "$(revision_desired_revision_file)"; revision_lock_release
}
revision_rollback_if_match() {
  local expected="$1" target="$2" actor="${3:-local}" summary="${4:-rollback}" dir config_json; revision_init; [[ "$target" =~ ^[0-9]+$ ]] || return 1; dir="$(revision_dir)"; [[ -r "$(revision_file "$target")" ]] || return 1; revision_lock_acquire || return 1; local current; current="$(revision_current)"
  if [[ "$expected" != "$current" ]]; then printf 'revision conflict: expected revision %s, current revision is %s\n' "$expected" "$current" >&2; revision_lock_release; return 3; fi
  config_json="$(cat "$(revision_file "$target")")" || { revision_lock_release; return 1; }
  config_json="$(python3 - "$config_json" <<'PY'
import json, sys
print(json.dumps(json.loads(sys.argv[1])["config"], ensure_ascii=False, separators=(",", ":"), sort_keys=True))
PY
  )" || { revision_lock_release; return 1; }
  local id="$(revision_next_id)" timestamp file tmp previous; previous="$current"; timestamp="$(date +%s)"; file="$(revision_file "$id")"; tmp="${file}.tmp.$$"
  if ! python3 - "$config_json" "$actor" "$summary" "$id" "$previous" "$timestamp" "$target" >"$tmp" <<'PY'
import json, sys
config=json.loads(sys.argv[1]); payload={"schema_version":1,"revision":int(sys.argv[4]),"previous_revision":int(sys.argv[5]),"timestamp":int(sys.argv[6]),"actor":sys.argv[2],"change_summary":sys.argv[3],"validation_result":"passed","health_result":"pending","rollback_target_revision":int(sys.argv[7]),"config":config}; print(json.dumps(payload,ensure_ascii=False,separators=(",",":"),sort_keys=True))
PY
  then rm -f "$tmp"; revision_lock_release; return 1; fi
  mv -f "$tmp" "$file"; printf '%s\n' "$id" >"$(revision_head_file)"
  tmp="$(revision_desired_file).tmp.$$"; if ! printf '%s\n' "$config_json" >"$tmp"; then rm -f "$tmp"; revision_lock_release; return 1; fi
  mv -f "$tmp" "$(revision_desired_file)"; tmp="$(revision_desired_revision_file).tmp.$$"; printf '%s\n' "$id" >"$tmp"; mv -f "$tmp" "$(revision_desired_revision_file)"; revision_lock_release; printf '%s' "$id"
}
revision_desired() { if [[ -r "$(revision_desired_file)" ]]; then cat "$(revision_desired_file)"; return; fi; printf '%s\n' '{}'; }
revision_desired_revision() { if [[ -r "$(revision_desired_revision_file)" ]]; then cat "$(revision_desired_revision_file)"; else printf '0'; fi; }
