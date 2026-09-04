#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/opt/proxy-agent}"
ETC="${ETC:-/etc/proxy-agent}"
SERVICE_USER="${SERVICE_USER:-proxy-agent}"
SERVICE_NAME="${SERVICE_NAME:-proxy-agent.service}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -eq 0 ]] || { echo 'upgrade.sh 必须以 root 身份运行' >&2; exit 1; }
[[ -f "$ROOT/install.sh" ]] || { echo 'upgrade.sh 必须从 proxy-agent 源码目录运行' >&2; exit 1; }
[[ -f "$ETC/proxy-agent.conf" ]] || { echo "未找到配置文件：$ETC/proxy-agent.conf" >&2; exit 1; }

was_active=false
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$SERVICE_NAME"; then
  was_active=true
fi

backup_root="$(mktemp -d /tmp/proxy-agent-upgrade.XXXXXX)"
cleanup_backup() { rm -rf -- "$backup_root"; }
trap cleanup_backup EXIT

if [[ -d "$PREFIX" ]]; then
  mkdir -p "$backup_root/prefix"
  cp -a "$PREFIX"/. "$backup_root/prefix/"
  printf '%s\n' "$PREFIX" >"$backup_root/prefix.path"
fi

restore_previous() {
  printf '升级校验失败，正在恢复上一版本……\n' >&2
  if [[ -d "$backup_root/prefix" ]]; then
    rm -rf -- "$PREFIX"
    mkdir -p "$(dirname "$PREFIX")"
    cp -a "$backup_root/prefix" "$PREFIX"
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    if $was_active; then
      systemctl start "$SERVICE_NAME" || true
    fi
  fi
  printf '已恢复上一版本；请检查升级日志后再重试。\n' >&2
}

if $was_active; then
  systemctl stop "$SERVICE_NAME"
fi

set +e
PREFIX="$PREFIX" ETC="$ETC" SERVICE_USER="$SERVICE_USER" SERVICE_GROUP="${SERVICE_GROUP:-proxy-agent}" bash "$ROOT/install.sh"
install_rc=$?
if (( install_rc == 0 )); then
  "$PREFIX/bin/proxy-ctl" validate
  validate_rc=$?
else
  validate_rc=$install_rc
fi
set -e

if (( validate_rc != 0 )); then
  restore_previous
  exit "$validate_rc"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  if $was_active; then
    systemctl start "$SERVICE_NAME"
  fi
fi

printf 'proxy-agent 已升级到 %s\n' "$(cat "$ROOT/VERSION")"
printf '配置已保留：%s\n' "$ETC/proxy-agent.conf"
if $was_active; then
  printf '服务已恢复：%s\n' "$SERVICE_NAME"
else
  printf '升级前服务处于停止状态，当前仍保持停止。\n'
fi
