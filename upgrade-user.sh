#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/lib/proxy-agent}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
ETC="$CONFIG_HOME/proxy-agent"
BIN="${BIN:-$HOME/.local/bin}"
SERVICE_NAME="${SERVICE_NAME:-proxy-agent.service}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -ne 0 ]] || { echo 'upgrade-user.sh 不能以 root 身份运行；系统级部署请使用 upgrade.sh' >&2; exit 1; }
[[ -n "${HOME:-}" && -d "$HOME" ]] || { echo 'HOME 必须指向已存在的用户目录' >&2; exit 1; }
[[ -f "$ROOT/install-user.sh" ]] || { echo 'upgrade-user.sh 必须从 proxy-agent 源码目录运行' >&2; exit 1; }
[[ -f "$ETC/proxy-agent.conf" ]] || { echo "未找到配置文件：$ETC/proxy-agent.conf" >&2; exit 1; }

was_active=false
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
  was_active=true
fi

backup_root="$(mktemp -d "${TMPDIR:-/tmp}/proxy-agent-user-upgrade.XXXXXX")"
cleanup_backup() { rm -rf -- "$backup_root"; }
trap cleanup_backup EXIT

if [[ -d "$PREFIX" ]]; then
  mkdir -p "$backup_root/prefix"
  cp -a "$PREFIX"/. "$backup_root/prefix/"
fi

restore_previous() {
  printf '升级校验失败，正在恢复上一版本……\n' >&2
  if [[ -d "$backup_root/prefix" ]]; then
    rm -rf -- "$PREFIX"
    mkdir -p "$(dirname "$PREFIX")"
    cp -a "$backup_root/prefix" "$PREFIX"
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
    if $was_active; then
      systemctl --user start "$SERVICE_NAME" || true
    fi
  fi
  printf '已恢复上一版本；请检查升级日志后再重试。\n' >&2
}

if $was_active; then
  systemctl --user stop "$SERVICE_NAME"
fi

set +e
PREFIX="$PREFIX" BIN="$BIN" XDG_CONFIG_HOME="$CONFIG_HOME" bash "$ROOT/install-user.sh"
install_rc=$?
if (( install_rc == 0 )); then
  PA_CONFIG="$ETC/proxy-agent.conf" "$BIN/proxy-ctl" validate
  validate_rc=$?
else
  validate_rc=$install_rc
fi
set -e

if (( validate_rc != 0 )); then
  restore_previous
  exit "$validate_rc"
fi

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
  if $was_active; then
    systemctl --user start "$SERVICE_NAME"
  fi
fi

printf 'rootless proxy-agent 已升级到 %s\n' "$(cat "$ROOT/VERSION")"
printf '配置已保留：%s\n' "$ETC/proxy-agent.conf"
if $was_active; then
  printf '用户服务已恢复：%s\n' "$SERVICE_NAME"
else
  printf '升级前用户服务处于停止状态，当前仍保持停止。\n'
fi
