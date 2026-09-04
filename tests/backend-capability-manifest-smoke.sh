#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/schemas/proxy-agent-backends.json"
SCHEMA="$ROOT/schemas/proxy-agent-backends.schema.json"

python3 - "$MANIFEST" "$SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
schema = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert manifest["schema_version"] == 1
assert schema["properties"]["schema_version"]["const"] == 1
assert schema["properties"]["backends"]["additionalProperties"]["$ref"] == "#/$defs/backend"
expected = {"ssh-socks", "local-endpoint", "sing-box", "mihomo", "http-connect"}
assert set(manifest["backends"]) == expected
for name, backend in manifest["backends"].items():
    assert isinstance(backend["managed"], bool)
    assert len(backend["capabilities"]) >= 1
    assert len({item["name"] for item in backend["options"]}) == len(backend["options"])
    for option in backend["options"]:
        assert option["type"] in {"string", "integer", "boolean", "secret_ref"}
        assert isinstance(option["required"], bool)
PY

source "$ROOT/lib/backend-capabilities.sh"
source "$ROOT/backends/ssh-socks.sh"
source "$ROOT/backends/sing-box.sh"
source "$ROOT/backends/mihomo.sh"
source "$ROOT/backends/http-connect.sh"
source "$ROOT/backends/local-endpoint.sh"

check_caps() {
  local backend="$1" expected="$2"
  BACKEND="$backend"
  local actual
  actual="$(backend_capabilities | paste -sd, -)"
  [[ "$actual" == "$expected" ]] || {
    echo "backend capability drift: $backend expected=$expected actual=$actual" >&2
    return 1
  }
}

check_caps ssh-socks 'socks5,dynamic_dns,stream_proxy'
check_caps sing-box 'socks5,stream_proxy'
check_caps mihomo 'socks5,stream_proxy'
check_caps http-connect 'http_native,stream_proxy'

BACKEND=local-endpoint
LOCAL_PROXY_URL='socks5h://127.0.0.1:1080'
[[ "$(backend_capabilities | paste -sd, -)" == 'socks5,stream_proxy' ]]
LOCAL_PROXY_URL='http://127.0.0.1:3128'
[[ "$(backend_capabilities | paste -sd, -)" == 'http_native,stream_proxy' ]]

printf 'backend capability manifest smoke: PASS\n'
