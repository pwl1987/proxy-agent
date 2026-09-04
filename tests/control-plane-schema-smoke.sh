#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])

def load(name):
    with (root / "schemas" / name).open(encoding="utf-8") as fh:
        return json.load(fh)

revision = load("proxy-agent-revision.v1.json")
audit = load("proxy-agent-audit-event.v1.json")
control = load("proxy-agent-control-api.v1.json")
backend = load("proxy-agent-backends.json")

assert revision["$schema"].endswith("/draft/2020-12/schema")
assert revision["properties"]["schema_version"]["const"] == 1
assert "config" in revision["required"]
assert audit["properties"]["schema_version"]["const"] == 1
assert "desired_state.activation_failed" in audit["properties"]["event"]["enum"]
assert control["properties"]["api_version"]["const"] == "v1"
assert control["transport"]["required"] == ["kind", "default"] if "required" in control["transport"] else True
assert backend["schema_version"] == 1
print("control-plane schema smoke: PASS")
PY
