#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PA_STATE_DIR="$TMP/state"
mkdir -p "$PA_STATE_DIR"
source "$ROOT/lib/revision-store.sh"

config='{"schema_version":1,"profile":"default","backend":{"type":"http-connect","options":{"proxy_url":"http://127.0.0.1:3128"}},"listeners":{"socks5":{"bind":"127.0.0.1","port":1080},"http":{"enabled":false,"bind":"127.0.0.1","port":8118}},"routing":{"direct_cidrs":[],"direct_domains":[],"no_proxy_extra":[],"rules":[]},"health":{"network_required":false,"timeout":10,"retries":1,"backoff":1,"auto_recover":true,"targets":[]},"integrations":{"git":true,"docker":false,"pip":false,"npm":false},"security":{"ssh_host_key_checking":"yes","allow_public_listener":false}}'

rid="$(revision_record "$config" smoke 'reconciler smoke' passed pending)"
revision_set_desired "$rid" "$config"
PA_STATE_DIR="$PA_STATE_DIR" "$ROOT/bin/proxy-agent-reconcile" >"$TMP/result.json"

python3 - "$TMP/result.json" "$PA_STATE_DIR/runtime/proxy-agent.conf" "$PA_STATE_DIR/runtime/reconcile-state.json" <<'PY'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
state = json.loads(Path(sys.argv[3]).read_text())
conf = Path(sys.argv[2]).read_text()
assert result["status"] == "projected"
assert result["desired_revision"] == 1
assert result["observed_revision"] == 1
assert state["observed_revision"] == 1
assert 'BACKEND=http-connect' in conf
assert 'HTTP_CONNECT_PROXY_URL=http://127.0.0.1:3128' in conf
assert 'REMOTE_SSH_KEY' not in conf
assert 'allow_public_listener' not in conf
PY

echo 'reconciler smoke: PASS'
