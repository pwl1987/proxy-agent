#!/usr/bin/env bash
set -euo pipefail

integration_npm_print() {
  local proxy
  proxy="$(integration_proxy_url)"
  cat <<EOF
# npm (current user)
npm config set proxy "$proxy"
npm config set https-proxy "$proxy"

# Remove npm proxy settings
npm config delete proxy
npm config delete https-proxy
EOF
}
