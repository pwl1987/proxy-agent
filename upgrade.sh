#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/opt/proxy-agent}"
ETC="${ETC:-/etc/proxy-agent}"
SERVICE_USER="${SERVICE_USER:-proxy-agent}"
SERVICE_NAME="${SERVICE_NAME:-proxy-agent.service}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -eq 0 ]] || { echo 'upgrade.sh must run as root' >&2; exit 1; }
[[ -f "$ROOT/install.sh" ]] || { echo 'upgrade.sh must be run from a proxy-agent source checkout' >&2; exit 1; }
[[ -f "$ETC/proxy-agent.conf" ]] || { echo "configuration not found: $ETC/proxy-agent.conf" >&2; exit 1; }

was_active=false
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$SERVICE_NAME"; then
  was_active=true
fi

if $was_active; then
  systemctl stop "$SERVICE_NAME"
fi

PREFIX="$PREFIX" ETC="$ETC" SERVICE_USER="$SERVICE_USER" SERVICE_GROUP="${SERVICE_GROUP:-proxy-agent}" bash "$ROOT/install.sh"

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  if $was_active; then
    systemctl start "$SERVICE_NAME"
  fi
fi

"$PREFIX/bin/proxy-ctl" validate

printf 'Upgraded proxy-agent to %s\n' "$(cat "$ROOT/VERSION")"
printf 'Config preserved: %s\n' "$ETC/proxy-agent.conf"
if $was_active; then
  printf 'Service restored: %s\n' "$SERVICE_NAME"
else
  printf 'Service was inactive before upgrade; it remains inactive.\n'
fi
