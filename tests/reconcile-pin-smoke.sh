#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PA_STATE_DIR="$TMP/state"
mkdir -p "$PA_STATE_DIR"
source "$ROOT/lib/revision-store.sh"

config_a='{"schema_version":1,"profile":"default","backend":{"type":"http-connect","options":{"proxy_url":"http://127.0.0.1:3128"}},"listeners":{"socks5":{"bind":"127.0.0.1","port":1080},"http":{"enabled":false,"bind":"127.0.0.1","port":8118}},"routing":{"direct_cidrs":[],"direct_domains":[],"no_proxy_extra":[],"rules":[]},"health":{"network_required":false,"timeout":10,"retries":1,"backoff":1,"auto_recover":true,"targets":[]},"integrations":{"git":false,"docker":false,"pip":false,"npm":false},"security":{"ssh_host_key_checking":"yes","allow_public_listener":false}}'
config_b="${config_a/http:\/\/127.0.0.1:3128/http:\/\/127.0.0.1:4128}"

rid_a="$(revision_record "$config_a" smoke 'pin A' passed pending)"
rid_b="$(revision_record "$config_b" smoke 'pin B' passed pending)"
revision_set_desired "$rid_b" "$config_b"

if "$ROOT/bin/proxy-agent-reconcile" --activate --revision "$rid_a" >"$TMP/result.json" 2>"$TMP/error.log"; then
  echo 'expected pinned reconcile to reject superseded revision' >&2
  exit 1
fi

grep -q "requested revision 1 was superseded by desired revision 2" "$TMP/error.log"
[[ ! -e "$PA_STATE_DIR/runtime/reconcile-state.json" ]]
[[ ! -e "$PA_STATE_DIR/runtime/proxy-agent.conf" ]]

echo 'reconcile pin smoke: PASS'
