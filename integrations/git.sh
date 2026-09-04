#!/usr/bin/env bash
set -euo pipefail

integration_git_print() {
  local proxy no_proxy
  proxy="$(integration_proxy_url)"
  no_proxy="$(integration_no_proxy)"
  cat <<EOF
# Git (current user)
git config --global http.proxy "$proxy"
git config --global https.proxy "$proxy"
git config --global http.noProxy "$no_proxy"
git config --global https.noProxy "$no_proxy"

# Remove Git proxy settings
git config --global --unset http.proxy || true
git config --global --unset https.proxy || true
git config --global --unset http.noProxy || true
git config --global --unset https.noProxy || true
EOF
}
