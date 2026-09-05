#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORTER="$ROOT/lib/typed-legacy-export.py"

base_json='{
  "schema_version": 1,
  "profile": "default",
  "backend": {"type": "ssh-socks", "options": {"remote_ssh_key_ref": "~/.ssh/id_ed25519", "ssh_strict_host_key_checking": "yes", "ssh_known_hosts_ref": "~/.ssh/known_hosts"}},
  "listeners": {"socks5": {"bind": "127.0.0.1", "port": 1080}, "http": {"enabled": false, "bind": "127.0.0.1", "port": 8118}},
  "health": {"network_required": false, "timeout": 10, "retries": 2, "backoff": 2, "auto_recover": false, "targets": []},
  "integrations": {"git": false, "docker": false, "pip": false, "npm": false},
  "routing": {"direct_cidrs": [], "direct_domains": [], "no_proxy_extra": [], "rules": []},
  "security": {"ssh_host_key_checking": "yes", "allow_public_listener": false},
  "egress_path": {"transport": "ssh", "mode": "direct", "target": {"host": "proxy.example.com", "user": "proxy", "port": 22}}
}'

python3 - "$EXPORTER" "$base_json" <<'PY'
import json, subprocess, sys
out = subprocess.check_output([sys.executable, sys.argv[1]], input=sys.argv[2], text=True)
lines = dict(line.split("=", 1) for line in out.splitlines() if "=" in line)
assert lines["BACKEND"] == "ssh-socks"
assert lines["REMOTE_HOST"] == "proxy.example.com"
assert lines["REMOTE_USER"] == "proxy"
assert lines["REMOTE_PORT"] == "22"
assert lines["REMOTE_SSH_KEY"] == "'~/.ssh/id_ed25519'"
assert lines["SSH_EGRESS_MODE"] == "direct"
assert lines["SSH_DNS_MODE"] == "remote"
assert "egress_path" not in out
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json, subprocess, sys
doc=json.loads(sys.argv[2]); doc["backend"]["options"]["remote_host"]="other.example.com"
p=subprocess.run([sys.executable,sys.argv[1]],input=json.dumps(doc),text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert p.returncode != 0 and "conflicts with backend.options.remote_host" in p.stderr
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json, subprocess, sys
doc=json.loads(sys.argv[2]); doc["backend"]["type"]="http-connect"
p=subprocess.run([sys.executable,sys.argv[1]],input=json.dumps(doc),text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert p.returncode != 0 and "egress_path requires backend.type=ssh-socks" in p.stderr
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json, subprocess, sys
doc=json.loads(sys.argv[2]); del doc["egress_path"]["target"]["port"]
p=subprocess.run([sys.executable,sys.argv[1]],input=json.dumps(doc),text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert p.returncode != 0 and "missing required field: egress_path.target.port" in p.stderr
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json, subprocess, sys
doc=json.loads(sys.argv[2]); doc["egress_path"]={"transport":"ssh","mode":"jump","dns_mode":"local","target":{"host":"target.example","user":"target","port":22,"identity_ref":"file:/run/proxy-agent/keys/target","known_hosts_ref":"file:/run/proxy-agent/keys/target-known_hosts"},"jump":{"host":"jump.example","user":"jump","port":2222,"identity_ref":"file:/run/proxy-agent/keys/jump","known_hosts_ref":"file:/run/proxy-agent/keys/jump-known_hosts"}}
out=subprocess.check_output([sys.executable,sys.argv[1]],input=json.dumps(doc),text=True)
lines=dict(line.split("=",1) for line in out.splitlines() if "=" in line)
assert lines["SSH_EGRESS_MODE"] == "jump"
assert lines["SSH_DNS_MODE"] == "local"
assert lines["REMOTE_HOST"] == "target.example"
assert lines["REMOTE_USER"] == "target"
assert lines["REMOTE_PORT"] == "22"
assert lines["SSH_JUMP_HOST"] == "jump.example"
assert lines["SSH_JUMP_USER"] == "jump"
assert lines["SSH_JUMP_PORT"] == "2222"
assert lines["SSH_JUMP_KEY"] == "/run/proxy-agent/keys/jump"
assert lines["SSH_TARGET_KEY"] == "/run/proxy-agent/keys/target"
assert lines["SSH_JUMP_KNOWN_HOSTS"] == "/run/proxy-agent/keys/jump-known_hosts"
assert lines["SSH_TARGET_KNOWN_HOSTS"] == "/run/proxy-agent/keys/target-known_hosts"
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json, subprocess, sys
doc=json.loads(sys.argv[2]); doc["egress_path"]={"transport":"ssh","mode":"jump","target":{"host":"target.example","user":"target","port":22},"jump":{"host":"jump.example","user":"jump","port":22,"identity_ref":"file:/jump","known_hosts_ref":"file:/jump-hosts"}}
p=subprocess.run([sys.executable,sys.argv[1]],input=json.dumps(doc),text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert p.returncode != 0 and "egress_path.target.identity_ref must be a non-empty file: reference" in p.stderr
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json, subprocess, sys
doc=json.loads(sys.argv[2]); doc["egress_path"]={"transport":"ssh","mode":"jump","dns_mode":"remote","target":{"host":"target.example","user":"target","port":22,"identity_ref":"file:/target","known_hosts_ref":"file:/target-hosts"},"jump":{"host":"jump.example","user":"jump","port":22,"identity_ref":"file:/jump","known_hosts_ref":"file:/jump-hosts","next":{"host":"third.example"}}}
p=subprocess.run([sys.executable,sys.argv[1]],input=json.dumps(doc),text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert p.returncode != 0 and "contains unknown fields: next" in p.stderr
PY

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/keys" "$tmp_dir/known"
printf 'identity' >"$tmp_dir/keys/jump"
printf 'known' >"$tmp_dir/known/jump"
printf 'identity' >"$tmp_dir/keys/target"
printf 'known' >"$tmp_dir/known/target"
chmod 600 "$tmp_dir/keys/jump" "$tmp_dir/keys/target"
chmod 644 "$tmp_dir/known/jump" "$tmp_dir/known/target"

export PA_CONFIG="$tmp_dir/proxy-agent.conf"
export PA_STATE_DIR="$tmp_dir/state"
export PA_LOG_DIR="$tmp_dir/log"
export SSH_JUMP_KEY="file:$tmp_dir/keys/jump"
export SSH_JUMP_KNOWN_HOSTS="file:$tmp_dir/known/jump"
export SSH_TARGET_KEY="file:$tmp_dir/keys/target"
export SSH_TARGET_KNOWN_HOSTS="file:$tmp_dir/known/target"
export SSH_JUMP_HOST='jump"node.example'
export SSH_JUMP_USER='jump user'
export SSH_JUMP_PORT=2222
export REMOTE_HOST='target"node.example'
export REMOTE_USER='target user'
export REMOTE_PORT=22
export SSH_STRICT_HOST_KEY_CHECKING=yes
source "$ROOT/lib/common.sh"
source "$ROOT/backends/ssh-socks.sh"
mkdir -p "$PA_STATE_DIR"
ssh_config="$PA_STATE_DIR/ssh-socks-runtime.conf"
backend_ssh_socks_write_jump_config "$ssh_config"
assert_file="$(cat "$ssh_config")"
printf '%s\n' "$assert_file" | grep -F 'HostName "jump\"node.example"' >/dev/null
printf '%s\n' "$assert_file" | grep -F 'User "jump user"' >/dev/null
printf '%s\n' "$assert_file" | grep -F 'HostName "target\"node.example"' >/dev/null
printf '%s\n' "$assert_file" | grep -F 'User "target user"' >/dev/null
printf '%s\n' "$assert_file" | grep -F "IdentityFile \"$tmp_dir/keys/jump\"" >/dev/null
[[ "$(stat -c '%a' "$ssh_config")" == 600 ]]

chmod 640 "$tmp_dir/keys/jump"
if (ssh_identity_resolve "file:$tmp_dir/keys/jump" >/dev/null 2>&1); then
  printf 'identity group-readable key unexpectedly accepted\n' >&2
  exit 1
fi

printf 'egress path foundation smoke: PASS\n'
