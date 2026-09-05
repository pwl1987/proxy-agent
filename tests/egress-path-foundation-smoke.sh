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
assert p.returncode != 0 and "missing required field: egress_path.target.identity_ref" in p.stderr
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json, subprocess, sys
doc=json.loads(sys.argv[2]); doc["egress_path"]={"transport":"ssh","mode":"jump","dns_mode":"remote","target":{"host":"target.example","user":"target","port":22,"identity_ref":"file:/target","known_hosts_ref":"file:/target-hosts"},"jump":{"host":"jump.example","user":"jump","port":22,"identity_ref":"file:/jump","known_hosts_ref":"file:/jump-hosts","next":{"host":"third.example"}}}
p=subprocess.run([sys.executable,sys.argv[1]],input=json.dumps(doc),text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert p.returncode != 0 and "unknown fields: next" in p.stderr
PY

printf 'egress path foundation smoke: PASS\n'
