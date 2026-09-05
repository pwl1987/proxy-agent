#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export PA_CONFIG="$TMP/proxy-agent.conf"
export PA_STATE_DIR="$TMP/state"
export PA_LOG_DIR="$TMP/log"
export PA_ACTIVE_PROFILE="smoke"
export BACKEND="ssh-socks"
export SOCKS_BIND="127.0.0.1"
export SOCKS_PORT="1080"
export REMOTE_HOST="target.example"
export REMOTE_USER="target"
export REMOTE_PORT="22"
export REMOTE_SSH_KEY="$TMP/target.key"
export SSH_KNOWN_HOSTS="$TMP/known_hosts"
export SSH_STRICT_HOST_KEY_CHECKING="yes"
export SSH_EGRESS_MODE="direct"
export HEALTH_TIMEOUT=1
printf 'identity\n' >"$TMP/target.key"
printf 'known\n' >"$TMP/known_hosts"
chmod 600 "$TMP/target.key"
chmod 644 "$TMP/known_hosts"

source "$ROOT/lib/common.sh"
source "$ROOT/backends/ssh-socks.sh"

backend_ssh_socks_liveness() { return 1; }

mkdir -p "$TMP/bin"
cat >"$TMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *__proxy_agent_jump*true) exit "${FAKE_JUMP_RC:-0}" ;;
  *__proxy_agent_target*true) exit "${FAKE_TARGET_RC:-0}" ;;
  *) exit "${FAKE_TARGET_RC:-0}" ;;
esac
EOF
chmod 0755 "$TMP/bin/ssh"
export PATH="$TMP/bin:$PATH"

FAKE_TARGET_RC=7
export FAKE_TARGET_RC
python3 - "$(backend_ssh_socks_health_detail)" <<'PY'
import json, sys
x=json.loads(sys.argv[1])
assert x["overall_status"] == "failed"
assert x["transport_status"] == "failed"
assert x["jump_status"] == "not_applicable"
assert x["target_status"] == "failed"
assert x["reason"] == "target_unreachable"
assert isinstance(x["last_checked"], int)
PY

FAKE_TARGET_RC=0
export FAKE_TARGET_RC
python3 - "$(backend_ssh_socks_health_detail)" <<'PY'
import json, sys
x=json.loads(sys.argv[1])
assert x["overall_status"] == "failed"
assert x["transport_status"] == "ready"
assert x["target_status"] == "ready"
assert x["proxy_status"] == "failed"
assert x["reason"] == "proxy_listener_unavailable"
PY

export SSH_EGRESS_MODE="jump"
mkdir -p "$PA_STATE_DIR"
cat >"$PA_STATE_DIR/ssh-socks-runtime.conf" <<'EOF'
Host __proxy_agent_jump
  HostName jump.example
Host __proxy_agent_target
  HostName target.example
  ProxyJump __proxy_agent_jump
EOF

FAKE_JUMP_RC=7
FAKE_TARGET_RC=0
export FAKE_JUMP_RC FAKE_TARGET_RC
python3 - "$(backend_ssh_socks_health_detail)" <<'PY'
import json, sys
x=json.loads(sys.argv[1])
assert x["overall_status"] == "failed"
assert x["transport_status"] == "failed"
assert x["jump_status"] == "failed"
assert x["target_status"] == "unknown"
assert x["reason"] == "jump_unreachable"
PY

FAKE_JUMP_RC=0
FAKE_TARGET_RC=7
export FAKE_JUMP_RC FAKE_TARGET_RC
python3 - "$(backend_ssh_socks_health_detail)" <<'PY'
import json, sys
x=json.loads(sys.argv[1])
assert x["overall_status"] == "failed"
assert x["transport_status"] == "ready"
assert x["jump_status"] == "ready"
assert x["target_status"] == "failed"
assert x["reason"] == "target_unreachable"
PY

FAKE_TARGET_RC=0
export FAKE_TARGET_RC
backend_ssh_socks_liveness() { return 0; }
python3 - "$(backend_ssh_socks_health_detail)" <<'PY'
import json, sys
x=json.loads(sys.argv[1])
assert x["overall_status"] == "ready"
assert x["transport_status"] == "ready"
assert x["jump_status"] == "ready"
assert x["target_status"] == "ready"
assert x["proxy_status"] == "ready"
assert x["reason"] == "ssh_jump_path_established"
PY

source "$ROOT/lib/state.sh"
backend_status() { return 0; }
backend_managed() { return 0; }
backend_pid() { printf '1234'; }
backend_process_identity() { printf 'test-process'; }
backend_endpoint() { printf 'socks5h://127.0.0.1:1080'; }
adapter_privoxy_status() { return 1; }
backend_health_detail() { printf '%s\n' '{"transport_status":"ready","jump_status":"ready","target_status":"ready","proxy_status":"ready","overall_status":"ready","reason":"ssh_jump_path_established","last_checked":1234567890}'; }
state_sync
python3 - "$PA_STATE_DIR/runtime.json" <<'PY'
import json, sys
from pathlib import Path
x=json.loads(Path(sys.argv[1]).read_text())
assert x["schema_version"] == 2
assert x["health"]["path"]["overall_status"] == "ready"
assert x["health"]["path"]["jump_status"] == "ready"
assert x["health"]["path"]["reason"] == "ssh_jump_path_established"
PY

echo 'path health smoke: PASS'
