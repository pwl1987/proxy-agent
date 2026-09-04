#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/bin/proxy-agent-tui"

if "$ROOT/bin/proxy-agent-tui" >/tmp/proxy-agent-tui.out 2>/tmp/proxy-agent-tui.err; then
  echo 'unexpected TUI success without a tty' >&2
  exit 1
fi

grep -q 'requires an interactive terminal' /tmp/proxy-agent-tui.err
printf 'PASS TUI guard\n'
