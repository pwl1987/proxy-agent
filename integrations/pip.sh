#!/usr/bin/env bash
set -euo pipefail

integration_pip_print() {
  local proxy
  proxy="$(integration_proxy_url)"
  cat <<EOF
# pip (current user)
python -m pip config set global.proxy "$proxy"

# Remove pip proxy setting
python -m pip config unset global.proxy || true
EOF
}
