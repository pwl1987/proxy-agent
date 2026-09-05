#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/proxy-ctl"

set +e
output="$("$CLI" --profile 2>&1)"
rc=$?
set -e
[[ $rc -eq 1 ]]
grep -q '用法：proxy-ctl --profile <名称> <命令> \[参数\]' <<<"$output"

authoritative_commands='validate start run stop restart status test diagnose doctor route env exec integration profiles capabilities config health-history agent tui'
for command in $authoritative_commands; do
  grep -q "^[[:space:]]*${command})" "$CLI" || { echo "missing CLI command dispatch: $command" >&2; exit 1; }
done

set +e
output="$("$CLI" definitely-not-a-command 2>&1)"
rc=$?
set -e
[[ $rc -eq 2 ]]
grep -q '^用法：proxy-ctl' <<<"$output"

grep -q 'case "\${1:-}"' "$CLI"
grep -q 'cmd_validate' "$CLI"
grep -q 'cmd_status' "$CLI"

echo 'cli policy smoke: PASS'
