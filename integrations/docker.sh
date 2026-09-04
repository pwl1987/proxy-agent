#!/usr/bin/env bash
set -euo pipefail

integration_docker_print() {
  local proxy no_proxy
  proxy="$(integration_proxy_url)"
  no_proxy="$(integration_no_proxy)"
  cat <<EOF
# Docker daemon: create /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=$proxy"
Environment="HTTPS_PROXY=$proxy"
Environment="NO_PROXY=$no_proxy"

# Apply daemon configuration
sudo systemctl daemon-reload
sudo systemctl restart docker

# Remove daemon proxy override
sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
sudo systemctl daemon-reload
sudo systemctl restart docker
EOF
}
