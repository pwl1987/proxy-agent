#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/opt/proxy-agent}"
ETC="${ETC:-/etc/proxy-agent}"
BIN="${BIN:-/usr/local/bin}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -eq 0 ]] || { echo 'install.sh must run as root' >&2; exit 1; }

install -d -m 0755 "$PREFIX" "$ETC" "$BIN" "$ETC/profiles"
cp -a "$ROOT/bin" "$ROOT/lib" "$ROOT/backends" "$ROOT/adapters" "$ROOT/integrations" "$ROOT/systemd" "$PREFIX/"
chmod 0755 "$PREFIX"/bin/* 2>/dev/null || true
install -m 0644 "$ROOT/proxy-agent.conf.example" "$ETC/proxy-agent.conf.example"
if [[ ! -e "$ETC/proxy-agent.conf" ]]; then install -m 0600 "$ROOT/proxy-agent.conf.example" "$ETC/proxy-agent.conf"; fi
if [[ -d "$ROOT/profiles" ]]; then find "$ROOT/profiles" -maxdepth 1 -type f -name '*.conf' -exec install -m 0600 {} "$ETC/profiles/" \;; fi
ln -sf "$PREFIX/bin/proxy-ctl" "$BIN/proxy-ctl"
ln -sf "$PREFIX/bin/proxy-agent-tui" "$BIN/proxy-agent-tui"
ln -sf "$PREFIX/bin/proxy-agent-profile" "$BIN/proxy-agent-profile"
ln -sf "$PREFIX/bin/proxy-agent-version" "$BIN/proxy-agent-version"

install -d -m 0755 /etc/systemd/system
sed "s#@PREFIX@#$PREFIX#g" "$ROOT/systemd/proxy-agent.service" >/etc/systemd/system/proxy-agent.service
sed "s#@PREFIX@#$PREFIX#g" "$ROOT/systemd/proxy-agent@.service" >/etc/systemd/system/proxy-agent@.service
sed "s#@PREFIX@#$PREFIX#g" "$ROOT/systemd/proxy-agent-health.service" >/etc/systemd/system/proxy-agent-health.service
sed "s#@PREFIX@#$PREFIX#g" "$ROOT/systemd/proxy-agent-health@.service" >/etc/systemd/system/proxy-agent-health@.service
install -m 0644 "$ROOT/systemd/proxy-agent-health.timer" /etc/systemd/system/proxy-agent-health.timer
install -m 0644 "$ROOT/systemd/proxy-agent-health@.timer" /etc/systemd/system/proxy-agent-health@.timer

if command -v systemctl >/dev/null 2>&1; then systemctl daemon-reload; systemctl enable proxy-agent.service >/dev/null; fi

echo "Installed proxy-agent to $PREFIX"
echo "Config: $ETC/proxy-agent.conf"
echo "Profiles: $ETC/profiles"
echo "Default service: proxy-agent.service"
echo "Profile service: proxy-agent@<name>.service"
echo "Next: edit the config, then run: proxy-ctl validate && proxy-ctl doctor && systemctl start proxy-agent"
echo "TUI: proxy-ctl tui"
echo "Optional health loop: systemctl enable --now proxy-agent-health.timer"
echo "Profile health: systemctl enable --now proxy-agent-health@<name>.timer"
