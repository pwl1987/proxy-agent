#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORTER="$ROOT/lib/typed-legacy-export.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

base_json='{
  "schema_version": 1,
  "profile": "jump-test",
  "backend": {"type": "ssh-socks", "options": {"remote_ssh_key_ref": "~/.ssh/legacy.key"}},
  "listeners": {"socks5": {"bind": "127.0.0.1", "port": 1080}, "http": {"enabled": false, "bind": "127.0.0.1", "port": 8118}},
  "health": {"network_required": true, "timeout": 5, "retries": 3, "backoff": 2, "auto_recover": true, "targets": []},
  "integrations": {"git": true, "docker": true, "pip": true, "npm": true},
  "routing": {"direct_cidrs": [], "direct_domains": [], "no_proxy_extra": [], "rules": []},
  "security": {"ssh_host_key_checking": "yes", "allow_public_listener": false}
}'

python3 - "$base_json" "$TMP/direct.json" <<'PY'
import json, sys
cfg=json.loads(sys.argv[1])
cfg["egress_path"]={"transport":"ssh","mode":"direct","target":{"host":"target.example","user":"proxy","port":22}}
open(sys.argv[2],"w",encoding="utf-8").write(json.dumps(cfg))
PY
python3 "$EXPORTER" <"$TMP/direct.json" >"$TMP/direct.conf"
grep -q "SSH_EGRESS_MODE=direct" "$TMP/direct.conf"
grep -q "SSH_DNS_MODE=remote" "$TMP/direct.conf"
grep -q "REMOTE_HOST=target.example" "$TMP/direct.conf"

echo "ok - 0.5.0 direct shape remains exportable"

python3 - "$base_json" "$TMP/jump.json" <<'PY'
import json, sys
cfg=json.loads(sys.argv[1])
cfg["egress_path"]={
  "transport":"ssh", "mode":"jump", "dns_mode":"local",
  "target":{"host":"10.20.0.8","user":"target","port":22,"identity_ref":"file:/etc/proxy-agent/keys/target","known_hosts_ref":"file:/etc/proxy-agent/keys/target-known_hosts"},
  "jump":{"host":"jump.example","user":"jump","port":2222,"identity_ref":"file:/etc/proxy-agent/keys/jump","known_hosts_ref":"file:/etc/proxy-agent/keys/jump-known_hosts"}
}
open(sys.argv[2],"w",encoding="utf-8").write(json.dumps(cfg))
PY
python3 "$EXPORTER" <"$TMP/jump.json" >"$TMP/jump.conf"
grep -q "SSH_EGRESS_MODE=jump" "$TMP/jump.conf"
grep -q "SSH_DNS_MODE=local" "$TMP/jump.conf"
grep -q "SSH_JUMP_HOST=jump.example" "$TMP/jump.conf"
grep -q "SSH_JUMP_USER=jump" "$TMP/jump.conf"
grep -q "SSH_JUMP_PORT=2222" "$TMP/jump.conf"
grep -q "SSH_JUMP_KEY=/etc/proxy-agent/keys/jump" "$TMP/jump.conf"
grep -q "SSH_TARGET_KEY=/etc/proxy-agent/keys/target" "$TMP/jump.conf"
grep -q "SSH_JUMP_KNOWN_HOSTS=/etc/proxy-agent/keys/jump-known_hosts" "$TMP/jump.conf"
grep -q "SSH_TARGET_KNOWN_HOSTS=/etc/proxy-agent/keys/target-known_hosts" "$TMP/jump.conf"
! grep -q 'PRIVATE-KEY-MATERIAL' "$TMP/jump.conf"

echo "ok - one-hop Jump projects separate identities and known_hosts references"

python3 - "$base_json" "$TMP/invalid.json" <<'PY'
import json, sys
cfg=json.loads(sys.argv[1])
cfg["egress_path"]={
  "transport":"ssh", "mode":"jump",
  "target":{"host":"target.example","user":"target","port":22,"identity_ref":"file:/target","known_hosts_ref":"file:/target-hosts"},
  "jump":{"host":"jump.example","user":"jump","port":22,"identity_ref":"file:/jump","known_hosts_ref":"file:/jump-hosts","next":{"host":"third.example"}}
}
open(sys.argv[2],"w",encoding="utf-8").write(json.dumps(cfg))
PY
if python3 "$EXPORTER" <"$TMP/invalid.json" >"$TMP/invalid.conf" 2>"$TMP/invalid.err"; then
  echo 'expected deeper jump chain to fail' >&2
  exit 1
fi
grep -q 'unknown fields: next' "$TMP/invalid.err"

echo "ok - deeper-than-one-hop configuration is rejected"

echo "PASS egress-path-jump-smoke"
