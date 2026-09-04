#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Human-facing Chinese surfaces must exist; machine-facing JSON remains English-schema.
grep -q '代理控制台' "$ROOT/bin/proxy-agent-tui"
grep -q '运行状态' "$ROOT/bin/proxy-agent-tui"
grep -q '快捷操作' "$ROOT/bin/proxy-agent-tui"
grep -q '健康检查历史' "$ROOT/bin/proxy-agent-health-history"
grep -q '配置档案' "$ROOT/bin/proxy-agent-health-history"
test -s "$ROOT/docs/README.zh-CN.md"
test -s "$ROOT/docs/CLI.zh-CN.md"
test -s "$ROOT/docs/OPERATIONS.zh-CN.md"

printf 'PASS 中文界面与文档基础检查\n'
