#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/lib/proxy-agent}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
ETC="$CONFIG_HOME/proxy-agent"
BIN="${BIN:-$HOME/.local/bin}"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -ne 0 ]] || { echo 'install-user.sh must not run as root; use install.sh for system deployment' >&2; exit 1; }
[[ -n "${HOME:-}" && -d "$HOME" ]] || { echo 'HOME must point to an existing user home directory' >&2; exit 1; }

install -d -m 0755 "$PREFIX" "$BIN" "$ETC" "$ETC/profiles" "$SYSTEMD_USER_DIR"
cp -a "$ROOT/bin" "$ROOT/lib" "$ROOT/backends" "$ROOT/adapters" "$ROOT/integrations" "$PREFIX/"
chmod 0755 "$PREFIX"/bin/*

if [[ ! -e "$ETC/proxy-agent.conf" ]]; then
  install -m 0600 "$ROOT/proxy-agent.conf.example" "$ETC/proxy-agent.conf"
fi
install -m 0644 "$ROOT/proxy-agent.conf.example" "$ETC/proxy-agent.conf.example"
if [[ -d "$ROOT/profiles" ]]; then
  find "$ROOT/profiles" -maxdepth 1 -type f -name '*.conf' -exec install -m 0600 {} "$ETC/profiles/" \;
fi

ln -sf "$PREFIX/bin/proxy-ctl" "$BIN/proxy-ctl"
ln -sf "$PREFIX/bin/proxy-agent-tui" "$BIN/proxy-agent-tui"
ln -sf "$PREFIX/bin/proxy-agent-profile" "$BIN/proxy-agent-profile"
ln -sf "$PREFIX/bin/proxy-agent-version" "$BIN/proxy-agent-version"

for unit in proxy-agent.service proxy-agent@.service proxy-agent-health.service proxy-agent-health@.service; do
  sed "s#@BIN@#$BIN#g" "$ROOT/systemd-user/$unit" >"$SYSTEMD_USER_DIR/$unit"
  chmod 0644 "$SYSTEMD_USER_DIR/$unit"
done
install -m 0644 "$ROOT/systemd-user/proxy-agent-health.timer" "$SYSTEMD_USER_DIR/proxy-agent-health.timer"
install -m 0644 "$ROOT/systemd-user/proxy-agent-health@.timer" "$SYSTEMD_USER_DIR/proxy-agent-health@.timer"

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable proxy-agent.service >/dev/null
else
  echo 'User systemd manager is not available in this session; user unit files were installed but not enabled.' >&2
fi

echo "Installed rootless proxy-agent to $PREFIX"
echo "Config: $ETC/proxy-agent.conf"
echo "Profiles: $ETC/profiles"
echo "Executables: $BIN"
echo "User service: proxy-agent.service"
echo "Next: edit $ETC/proxy-agent.conf, then run: proxy-ctl validate && proxy-ctl doctor && systemctl --user start proxy-agent"
echo "Profile service: systemctl --user enable --now proxy-agent@<name>.service"
echo "Profile health: systemctl --user enable --now proxy-agent-health@<name>.timer"
echo "For boot-time persistence without login, a system administrator may enable lingering for this user."
