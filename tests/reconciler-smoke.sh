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

PROFILE_DIR="$TMP/profiles"
PROFILE_STATE="$TMP/profile-state"
PROFILE_LOG="$TMP/profile-log"
mkdir -p "$PROFILE_DIR" "$PROFILE_STATE" "$PROFILE_LOG"
cat >"$PROFILE_DIR/alpha.conf" <<EOF
BACKEND="http-connect"
HTTP_CONNECT_PROXY_URL="http://127.0.0.1:3128"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
SSH_STRICT_HOST_KEY_CHECKING="yes"
DIRECT_CIDRS=""
DIRECT_DOMAINS=""
NO_PROXY_EXTRA=""
ROUTE_RULES=""
HEALTH_TARGETS=""
HEALTH_NETWORK_REQUIRED="false"
HEALTH_TIMEOUT="10"
HEALTH_RETRIES="1"
HEALTH_BACKOFF="1"
HEALTH_AUTO_RECOVER="true"
INTEGRATE_GIT="false"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="false"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$PROFILE_DIR/alpha.conf"

PA_PROFILE_DIR="$PROFILE_DIR" PA_STATE_DIR="$PROFILE_STATE" PA_LOG_DIR="$PROFILE_LOG" PROFILE_CONFIG_JSON="$config" \
  bash -c '
    set -euo pipefail
    source "$1/lib/common.sh"
    source "$1/lib/profile.sh"
    source "$1/lib/profile-context.sh"
    source "$1/lib/revision-store.sh"
    profile_apply_context alpha
    rid="$(revision_record "$PROFILE_CONFIG_JSON" smoke "profile reconciler smoke" passed pending)"
    revision_set_desired "$rid" "$PROFILE_CONFIG_JSON"
    "$1/bin/proxy-agent-reconcile" >"$2/profile-result.json"
  ' _ "$ROOT" "$TMP"

python3 - "$TMP/profile-result.json" "$PROFILE_STATE/runtime/reconcile-state.json" "$PROFILE_STATE/runtime/proxy-agent.conf" <<'PY'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
state = json.loads(Path(sys.argv[2]).read_text())
conf = Path(sys.argv[3]).read_text()
assert result["status"] == "projected"
assert result["desired_revision"] == 1
assert result["runtime_config"] == str(Path(sys.argv[3]))
assert state["observed_revision"] == 1
assert 'BACKEND=http-connect' in conf
assert not Path(sys.argv[3]).parent.parent.joinpath("alpha", "runtime", "proxy-agent.conf").exists()
PY

PA_STATE_DIR="$TMP/bootstrap-state" PA_BOOTSTRAP_CONFIG="$TMP/bootstrap.conf" mkdir -p "$TMP/bootstrap-state"
cat >"$TMP/bootstrap.conf" <<'EOF'
BACKEND="http-connect"
HTTP_CONNECT_PROXY_URL="http://127.0.0.1:3128"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
SSH_STRICT_HOST_KEY_CHECKING="yes"
DIRECT_CIDRS=""
DIRECT_DOMAINS=""
NO_PROXY_EXTRA=""
ROUTE_RULES=""
HEALTH_TARGETS=""
HEALTH_NETWORK_REQUIRED="false"
HEALTH_TIMEOUT="10"
HEALTH_RETRIES="1"
HEALTH_BACKOFF="1"
HEALTH_AUTO_RECOVER="true"
INTEGRATE_GIT="false"
INTEGRATE_DOCKER="false"
INTEGRATE_PIP="false"
INTEGRATE_NPM="false"
EOF
chmod 0600 "$TMP/bootstrap.conf"
PA_STATE_DIR="$TMP/bootstrap-state" PA_BOOTSTRAP_CONFIG="$TMP/bootstrap.conf" PA_CONFIG="$TMP/bootstrap.conf" "$ROOT/bin/proxy-agent-reconcile" --bootstrap >"$TMP/bootstrap-result.json"
python3 - "$TMP/bootstrap-result.json" "$TMP/bootstrap-state" <<'PY'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
state = Path(sys.argv[2])
assert result["status"] == "projected"
assert result["desired_revision"] == 1
assert (state / "runtime" / "proxy-agent.conf").is_file()
assert (state / "runtime" / "reconcile-state.json").is_file()
PY

mkdir -p "$TMP/activate-state"
PA_STATE_DIR="$TMP/activate-state" source "$ROOT/lib/revision-store.sh"
PA_STATE_DIR="$TMP/activate-state" rid2="$(revision_record "$config" smoke 'activation smoke' passed pending)"
PA_STATE_DIR="$TMP/activate-state" revision_set_desired "$rid2" "$config"
PA_STATE_DIR="$TMP/activate-state" "$ROOT/bin/proxy-agent-reconcile" --activate >"$TMP/activate-result.json"
python3 - "$TMP/activate-result.json" "$TMP/activate-state/runtime/reconcile-state.json" <<'PY'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
state = json.loads(Path(sys.argv[2]).read_text())
assert result["status"] == "activated"
assert result["observed_revision"] == result["desired_revision"] == 1
assert state["status"] == "activated"
PY

echo 'reconciler smoke: PASS'
