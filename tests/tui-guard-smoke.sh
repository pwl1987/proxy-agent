#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUI="$ROOT/bin/proxy-agent-tui"

[[ -x "$TUI" ]]

set +e
output="$("$TUI" 2>&1)"
rc=$?
set -e
[[ $rc -eq 1 ]]
grep -q '需要交互式终端' <<<"$output"

set +e
output="$("$TUI" --profile 2>&1)"
rc=$?
set -e
[[ $rc -eq 2 ]]
grep -q '用法: proxy-agent-tui \[--profile 名称\]' <<<"$output"

grep -q '操作完成' "$ROOT/bin/proxy-agent-tui"
grep -q '操作失败' "$ROOT/bin/proxy-agent-tui"
grep -q '配置档案' "$ROOT/bin/proxy-agent-tui"

echo 'tui guard smoke: PASS'
