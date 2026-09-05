#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/opt/proxy-agent}"
ETC="${ETC:-/etc/proxy-agent}"
SERVICE_USER="${SERVICE_USER:-proxy-agent}"
SERVICE_NAME="${SERVICE_NAME:-proxy-agent.service}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -eq 0 ]] || { echo 'upgrade.sh 必须以 root 身份运行' >&2; exit 1; }
[[ -f "$ROOT/install.sh" ]] || { echo 'upgrade.sh 必须从 proxy-agent 源码目录运行' >&2; exit 1; }
[[ -f "$ETC/proxy-agent.conf" ]] || { echo "未找到配置文件：$ETC/proxy-agent.conf" >&2; exit 1; }

# Share the lifecycle lock with proxy-ctl/reconciler for the default system profile.
PA_STATE_DIR="${PA_STATE_DIR:-/run/proxy-agent}"
# shellcheck disable=SC1091
source "$ROOT/lib/state.sh"
state_lifecycle_lock_acquire
release_lifecycle_lock() { state_lifecycle_lock_release; }
cleanup_lifecycle() { release_lifecycle_lock; cleanup_backup; }

was_active=false
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$SERVICE_NAME"; then
  was_active=true
fi

backup_root="$(mktemp -d /tmp/proxy-agent-upgrade.XXXXXX)"
cleanup_backup() { rm -rf -- "$backup_root"; }
trap cleanup_lifecycle EXIT

backup_tree() {
  local source="$1" target="$2"
  if [[ -d "$source" ]]; then
    mkdir -p "$target"
    cp -a "$source"/. "$target/"
  fi
}

backup_tree "$PREFIX" "$backup_root/prefix"
backup_tree "$ETC" "$backup_root/etc"
mkdir -p "$backup_root/systemd"
for unit in \
  proxy-agent.service proxy-agent@.service \
  proxy-agent-health.service proxy-agent-health@.service \
  proxy-agent-health.timer proxy-agent-health@.timer; do
  [[ -e "$SYSTEMD_DIR/$unit" ]] && cp -a "$SYSTEMD_DIR/$unit" "$backup_root/systemd/$unit"
done

restore_path() {
  local target="$1" backup="$2"
  rm -rf -- "$target"
  if [[ -d "$backup" ]]; then
    mkdir -p "$(dirname "$target")"
    cp -a "$backup" "$target"
  fi
}

restore_systemd_units() {
  mkdir -p "$SYSTEMD_DIR"
  for unit in \
    proxy-agent.service proxy-agent@.service \
    proxy-agent-health.service proxy-agent-health@.service \
    proxy-agent-health.timer proxy-agent-health@.timer; do
    if [[ -e "$backup_root/systemd/$unit" ]]; then
      cp -a "$backup_root/systemd/$unit" "$SYSTEMD_DIR/$unit"
    else
      rm -f -- "$SYSTEMD_DIR/$unit"
    fi
  done
}

restore_previous() {
  printf '升级校验失败，正在恢复上一版本……\n' >&2
  restore_path "$PREFIX" "$backup_root/prefix"
  restore_path "$ETC" "$backup_root/etc"
  restore_systemd_units
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    if $was_active; then
      systemctl start "$SERVICE_NAME" || true
    fi
  fi
  printf '已恢复上一版本的程序、配置、Profile 和 systemd 单元；请检查升级日志后再重试。\n' >&2
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
    # The systemd service invokes proxy-ctl, which must acquire the same
    # lifecycle lock. Release our transaction lock before asking systemd to
    # start the service, otherwise the service would wait on us while we wait
    # for systemctl start to complete.
    state_lifecycle_lock_release
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
