#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -q '配置档案' "$ROOT/bin/proxy-agent-tui"
grep -q '操作完成' "$ROOT/bin/proxy-agent-tui"
grep -q '操作失败' "$ROOT/bin/proxy-agent-tui"
grep -q '管理员登录' "$ROOT/web/index.html"
grep -q '校验.*Diff' "$ROOT/web/index.html"
grep -q '请继续执行“校验 + Diff”' "$ROOT/web/index.html"

printf 'chinese localization smoke: PASS\n'
