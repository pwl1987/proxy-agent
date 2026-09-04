#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="$ROOT/schemas/proxy-agent-config.schema.json"
FIXTURE="$ROOT/examples/proxy-agent.typed.json"

python3 - "$SCHEMA" "$FIXTURE" <<'PY'
import json
import sys
from pathlib import Path

schema_path = Path(sys.argv[1])
fixture_path = Path(sys.argv[2])

schema = json.loads(schema_path.read_text(encoding="utf-8"))
fixture = json.loads(fixture_path.read_text(encoding="utf-8"))

assert schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema"
assert schema.get("type") == "object"
assert schema.get("additionalProperties") is False
assert schema["properties"]["schema_version"]["const"] == 1

required = set(schema["required"])
assert required <= fixture.keys(), f"fixture missing required fields: {sorted(required - fixture.keys())}"
assert fixture["schema_version"] == 1
assert fixture["security"]["allow_public_listener"] is False
assert fixture["backend"]["type"] == "local-endpoint"
assert fixture["listeners"]["socks5"]["port"] in range(1, 65536)
assert fixture["listeners"]["http"]["enabled"] is False

print("typed config smoke: PASS")
PY
