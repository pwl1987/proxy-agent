#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORTER="$ROOT/lib/legacy-typed-export.py"

export PA_ACTIVE_PROFILE="ci-profile"
export SOCKS_BIND="127.0.0.1"
export SOCKS_PORT="1080"
export HTTP_ENABLED="true"
export HTTP_BIND="127.0.0.1"
export HTTP_PORT="8118"
export DIRECT_CIDRS="127.0.0.0/8,10.0.0.0/8"
export DIRECT_DOMAINS="localhost,.cn"
export NO_PROXY_EXTRA="git.internal,10.0.0.5"
export ROUTE_RULES=$'200|PROXY|wildcard|*.example.net\n100|DIRECT|suffix|.internal.example'
export HEALTH_TARGETS="https://example.com,https://pypi.org"
export HEALTH_NETWORK_REQUIRED="false"
export HEALTH_TIMEOUT="10"
export HEALTH_RETRIES="2"
export HEALTH_BACKOFF="2"
export HEALTH_AUTO_RECOVER="true"
export INTEGRATE_GIT="true"
export INTEGRATE_DOCKER="false"
export INTEGRATE_PIP="true"
export INTEGRATE_NPM="false"
export SSH_STRICT_HOST_KEY_CHECKING="yes"
export AUTOSSH_MONITOR_PORT="0"
export SSH_SERVER_ALIVE_INTERVAL="30"
export SSH_SERVER_ALIVE_COUNT_MAX="3"
export SSH_KNOWN_HOSTS="~/.ssh/known_hosts"

assert_python() {
  BACKEND="$1" python3 - "$EXPORTER" <<'PY'
import json
import os
import subprocess
import sys

exporter = sys.argv[1]
env = os.environ.copy()
backend = env["BACKEND"]

if backend == "ssh-socks":
    env.update(
        REMOTE_HOST="proxy.example.com",
        REMOTE_USER="proxy",
        REMOTE_PORT="22",
        REMOTE_SSH_KEY="~/.ssh/id_ed25519",
    )
elif backend == "local-endpoint":
    env["LOCAL_PROXY_URL"] = "http://127.0.0.1:3128"
    env["LOCAL_PROXY_STATUS_TARGET"] = "https://example.com"
elif backend == "sing-box":
    env.update(SING_BOX_CONFIG="/etc/proxy-agent/sing-box.json", SING_BOX_BIN="sing-box")
elif backend == "mihomo":
    env.update(MIHOMO_CONFIG="/etc/proxy-agent/mihomo.yaml", MIHOMO_BIN="mihomo")
elif backend == "http-connect":
    env["HTTP_CONNECT_PROXY_URL"] = "http://127.0.0.1:8080"

raw = subprocess.check_output([sys.executable, exporter], env=env, text=True)
doc = json.loads(raw)
assert doc["schema_version"] == 1
assert doc["profile"] == "ci-profile"
assert doc["backend"]["type"] == backend
assert doc["listeners"]["http"]["enabled"] is True
assert doc["routing"]["rules"] == [
    {"action": "direct", "matcher": "suffix", "pattern": ".internal.example", "priority": 100},
    {"action": "proxy", "matcher": "wildcard", "pattern": "*.example.net", "priority": 200},
]
assert "remote_ssh_key_ref" not in doc["backend"].get("options", {}) if backend != "ssh-socks" else True
if backend == "ssh-socks":
    assert doc["backend"]["options"]["remote_ssh_key_ref"] == "~/.ssh/id_ed25519"
    assert "private" not in raw.lower()
if backend == "local-endpoint":
    assert doc["backend"]["options"]["status_target"] == "https://example.com"
if backend == "sing-box":
    assert doc["backend"]["options"]["config_path"] == "/etc/proxy-agent/sing-box.json"
if backend == "mihomo":
    assert doc["backend"]["options"]["config_path"] == "/etc/proxy-agent/mihomo.yaml"
if backend == "http-connect":
    assert doc["backend"]["options"]["proxy_url"] == "http://127.0.0.1:8080"
assert doc["security"]["allow_public_listener"] is False
PY
}

for backend in ssh-socks local-endpoint sing-box mihomo http-connect; do
  assert_python "$backend"
done

if SOCKS_BIND="0.0.0.0" BACKEND="local-endpoint" LOCAL_PROXY_URL="http://127.0.0.1:3128" \
  python3 "$EXPORTER" >/tmp/typed-public-listener.json 2>/tmp/typed-public-listener.err; then
  echo "legacy typed export: public listener unexpectedly accepted" >&2
  exit 1
fi
grep -q "public listener exposure cannot be migrated implicitly" /tmp/typed-public-listener.err

if BACKEND="unsupported-backend" python3 "$EXPORTER" >/tmp/typed-unsupported.json 2>/tmp/typed-unsupported.err; then
  echo "legacy typed export: unsupported backend unexpectedly accepted" >&2
  exit 1
fi
grep -q "unsupported backend" /tmp/typed-unsupported.err

rm -f /tmp/typed-public-listener.json /tmp/typed-public-listener.err /tmp/typed-unsupported.json /tmp/typed-unsupported.err
printf 'legacy typed config smoke: PASS\n'
