#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/proxy-ctl"

set +e
output="$("$CLI" --profile 2>&1)"
rc=$?
set -e
[[ $rc -eq 2 ]]
grep -q '用法：proxy-ctl --profile <名称> <命令> \[参数\]' <<<"$output"

set +e
output="$("$CLI" definitely-not-a-command 2>&1)"
rc=$?
set -e
[[ $rc -eq 2 ]]
grep -q '未知命令' <<<"$output"

grep -q 'case "\${1:-}"' "$CLI"
grep -q 'start|stop|restart|run' "$CLI"
grep -q 'cmd_validate' "$CLI"
grep -q 'cmd_status' "$CLI"

echo 'cli policy smoke: PASS'
