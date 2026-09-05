#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/opt/proxy-agent}"
ETC="${ETC:-/etc/proxy-agent}"
BIN="${BIN:-/usr/local/bin}"
SERVICE_USER="${SERVICE_USER:-proxy-agent}"
SERVICE_GROUP="${SERVICE_GROUP:-proxy-agent}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -eq 0 ]] || { echo 'install.sh must run as root' >&2; exit 1; }

if ! getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
  groupadd --system "$SERVICE_GROUP"
fi
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --gid "$SERVICE_GROUP" --home-dir "/var/lib/$SERVICE_USER" --create-home \
    --shell /usr/sbin/nologin "$SERVICE_USER"
fi

install -d -m 0755 "$PREFIX" "$BIN"
install -d -m 0750 -o root -g "$SERVICE_GROUP" "$ETC" "$ETC/profiles"
cp -a "$ROOT/bin" "$ROOT/lib" "$ROOT/backends" "$ROOT/adapters" "$ROOT/integrations" "$ROOT/systemd" "$ROOT/web" "$PREFIX/"
chmod 0755 "$PREFIX"/bin/* 2>/dev/null || true
install -m 0644 "$ROOT/proxy-agent.conf.example" "$ETC/proxy-agent.conf.example"
if [[ ! -e "$ETC/proxy-agent.conf" ]]; then install -m 0640 -o root -g "$SERVICE_GROUP" "$ROOT/proxy-agent.conf.example" "$ETC/proxy-agent.conf"; fi
if [[ -f "$ROOT/examples/web.env.example" ]]; then
  install -m 0644 "$ROOT/examples/web.env.example" "$ETC/web.env.example"
fi
if [[ ! -e "$ETC/web.env" && -f "$ROOT/examples/web.env.example" ]]; then
  install -m 0640 -o root -g "$SERVICE_GROUP" "$ROOT/examples/web.env.example" "$ETC/web.env"
fi
if [[ -d "$ROOT/profiles" ]]; then
  find "$ROOT/profiles" -maxdepth 1 -type f -name '*.conf' -exec install -m 0640 -o root -g "$SERVICE_GROUP" {} "$ETC/profiles/" \;
fi
ln -sf "$PREFIX/bin/proxy-ctl" "$BIN/proxy-ctl"
ln -sf "$PREFIX/bin/proxy-agent-tui" "$BIN/proxy-agent-tui"
ln -sf "$PREFIX/bin/proxy-agent-profile" "$BIN/proxy-agent-profile"
ln -sf "$PREFIX/bin/proxy-agent-version" "$BIN/proxy-agent-version"
ln -sf "$PREFIX/bin/proxy-agent-web-ui" "$BIN/proxy-agent-web-ui"

install -d -m 0755 /etc/systemd/system
for unit in proxy-agent.service proxy-agent@.service proxy-agent-health.service proxy-agent-health@.service proxy-agent-reconcile.service proxy-agent-api.service proxy-agent-web.service; do
  sed -e "s#@PREFIX@#$PREFIX#g" -e "s#@SERVICE_USER@#$SERVICE_USER#g" -e "s#@SERVICE_GROUP@#$SERVICE_GROUP#g" \
    "$ROOT/systemd/$unit" >"/etc/systemd/system/$unit"
done
for unit in proxy-agent-health.timer proxy-agent-health@.timer proxy-agent-reconcile.timer; do
  install -m 0644 "$ROOT/systemd/$unit" "/etc/systemd/system/$unit"
done

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl enable proxy-agent.service >/dev/null
  systemctl enable proxy-agent-api.service >/dev/null
  systemctl enable proxy-agent-health.timer >/dev/null
fi

echo "Installed proxy-agent to $PREFIX"
echo "Service account: $SERVICE_USER:$SERVICE_GROUP"
echo "Config: $ETC/proxy-agent.conf"
echo "Profiles: $ETC/profiles"
echo "Default service: proxy-agent.service"
echo "Control API: proxy-agent-api.service (/run/proxy-agent/control.sock, local-only)"
echo "Profile service: proxy-agent@<name>.service"
echo "Web UI binary: $BIN/proxy-agent-web-ui"
echo "Web service: proxy-agent-web.service (not enabled by default; requires $ETC/web-admin-token)"
echo "Web listener defaults: 127.0.0.1:8443; non-loopback requires PA_WEB_TLS_CERT and PA_WEB_TLS_KEY in $ETC/web.env"
echo "Next: provision an SSH key readable by $SERVICE_USER, edit the config, then run: proxy-ctl validate && proxy-ctl doctor && systemctl start proxy-agent"
echo "Web bootstrap: install a random token at $ETC/web-admin-token with mode 0640 and group $SERVICE_GROUP, then: systemctl enable --now proxy-agent-web.service"
echo "TUI: proxy-ctl tui"
echo "Default health loop: proxy-agent-health.timer (2min interval)"
echo "Profile health: systemctl enable --now proxy-agent-health@<name>.timer"
echo "Optional desired-state projection loop: systemctl enable --now proxy-agent-reconcile.timer"
