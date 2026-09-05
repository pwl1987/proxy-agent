#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/proxy-ctl"

[[ -x "$CLI" ]]

grep -q '用法：proxy-ctl \[--profile 名称\] <命令>' "$CLI"
grep -q '说明：--json 输出保持稳定的英文 schema；其他人类可读输出默认使用中文。' "$CLI"

for command in validate start run stop restart status test diagnose doctor route env exec integration profiles capabilities config health-history agent tui; do
  grep -q "^[[:space:]]*${command})" "$CLI" || { echo "missing CLI command dispatch: $command" >&2; exit 1; }
done

grep -q '^[[:space:]]*\*) usage; exit 2 ;;' "$CLI"
grep -q 'die() .*exit 1' "$ROOT/lib/common.sh"

echo 'cli policy smoke: PASS'
