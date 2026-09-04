#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/lib/proxy-agent}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
ETC="$CONFIG_HOME/proxy-agent"
BIN="${BIN:-$HOME/.local/bin}"
SERVICE_NAME="${SERVICE_NAME:-proxy-agent.service}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -ne 0 ]] || { echo 'upgrade-user.sh must not run as root; use upgrade.sh for system deployment' >&2; exit 1; }
[[ -n "${HOME:-}" && -d "$HOME" ]] || { echo 'HOME must point to an existing user home directory' >&2; exit 1; }
[[ -f "$ROOT/install-user.sh" ]] || { echo 'upgrade-user.sh must be run from a proxy-agent source checkout' >&2; exit 1; }
[[ -f "$ETC/proxy-agent.conf" ]] || { echo "configuration not found: $ETC/proxy-agent.conf" >&2; exit 1; }

was_active=false
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
  was_active=true
fi

if $was_active; then
  systemctl --user stop "$SERVICE_NAME"
fi

PREFIX="$PREFIX" BIN="$BIN" XDG_CONFIG_HOME="$CONFIG_HOME" bash "$ROOT/install-user.sh"

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
  if $was_active; then
    systemctl --user start "$SERVICE_NAME"
  fi
fi

PA_CONFIG="$ETC/proxy-agent.conf" "$BIN/proxy-ctl" validate

printf 'Upgraded rootless proxy-agent to %s\n' "$(cat "$ROOT/VERSION")"
printf 'Config preserved: %s\n' "$ETC/proxy-agent.conf"
if $was_active; then
  printf 'User service restored: %s\n' "$SERVICE_NAME"
else
  printf 'User service was inactive before upgrade; it remains inactive.\n'
fi
