#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORTER="$ROOT/lib/typed-legacy-export.py"

base_json='{
  "schema_version": 1,
  "profile": "default",
  "backend": {
    "type": "ssh-socks",
    "options": {
      "remote_ssh_key_ref": "~/.ssh/id_ed25519",
      "ssh_strict_host_key_checking": "yes",
      "ssh_known_hosts_ref": "~/.ssh/known_hosts"
    }
  },
  "listeners": {
    "socks5": {"bind": "127.0.0.1", "port": 1080},
    "http": {"enabled": false, "bind": "127.0.0.1", "port": 8118}
  },
  "health": {
    "network_required": false,
    "timeout": 10,
    "retries": 2,
    "backoff": 2,
    "auto_recover": false,
    "targets": []
  },
  "integrations": {"git": false, "docker": false, "pip": false, "npm": false},
  "routing": {"direct_cidrs": [], "direct_domains": [], "no_proxy_extra": [], "rules": []},
  "security": {"ssh_host_key_checking": "yes", "allow_public_listener": false},
  "egress_path": {
    "transport": "ssh",
    "mode": "direct",
    "target": {"host": "proxy.example.com", "user": "proxy", "port": 22}
  }
}'

python3 - "$EXPORTER" "$base_json" <<'PY'
import json
import subprocess
import sys

exporter = sys.argv[1]
doc = json.loads(sys.argv[2])
out = subprocess.check_output([sys.executable, exporter], input=json.dumps(doc), text=True)
lines = dict(line.split("=", 1) for line in out.splitlines() if "=" in line)
assert lines["BACKEND"] == "ssh-socks"
assert lines["REMOTE_HOST"] == "proxy.example.com"
assert lines["REMOTE_USER"] == "proxy"
assert lines["REMOTE_PORT"] == "22"
assert lines["REMOTE_SSH_KEY"] == "~/.ssh/id_ed25519"
assert "egress_path" not in out
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json
import subprocess
import sys

doc = json.loads(sys.argv[2])
doc["backend"]["options"]["remote_host"] = "other.example.com"
p = subprocess.run([sys.executable, sys.argv[1]], input=json.dumps(doc), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert p.returncode != 0
assert "conflicts with backend.options.remote_host" in p.stderr
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json
import subprocess
import sys

doc = json.loads(sys.argv[2])
doc["backend"]["type"] = "http-connect"
p = subprocess.run([sys.executable, sys.argv[1]], input=json.dumps(doc), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert p.returncode != 0
assert "egress_path requires backend.type=ssh-socks in 0.5.0" in p.stderr
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json
import subprocess
import sys

doc = json.loads(sys.argv[2])
doc["egress_path"]["mode"] = "jump"
p = subprocess.run([sys.executable, sys.argv[1]], input=json.dumps(doc), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert p.returncode != 0
assert "egress_path.mode must be direct in 0.5.0" in p.stderr
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json
import subprocess
import sys

doc = json.loads(sys.argv[2])
doc["egress_path"]["dns_mode"] = "remote"
p = subprocess.run([sys.executable, sys.argv[1]], input=json.dumps(doc), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert p.returncode != 0
assert "egress_path fields are invalid" in p.stderr
PY

python3 - "$EXPORTER" "$base_json" <<'PY'
import json
import subprocess
import sys

doc = json.loads(sys.argv[2])
del doc["egress_path"]["target"]["port"]
p = subprocess.run([sys.executable, sys.argv[1]], input=json.dumps(doc), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert p.returncode != 0
assert "missing=port" in p.stderr
PY

printf 'egress path foundation smoke: PASS\n'
