#!/usr/bin/env bash
set -euo pipefail

backend_name_prefix() { printf 'backend_%s' "${1//-/_}"; }

backend_capability() {
  local capability="$1" prefix
  prefix="$(backend_name_prefix "${BACKEND:-}")"
  declare -F "${prefix}_capability" >/dev/null 2>&1 || return 1
  "${prefix}_capability" "$capability"
}

backend_capabilities() {
  local prefix
  prefix="$(backend_name_prefix "${BACKEND:-}")"
  if declare -F "${prefix}_capabilities" >/dev/null 2>&1; then
    "${prefix}_capabilities"
  fi
}

backend_require_capability() {
  backend_capability "$1" || die "backend '$BACKEND' does not provide capability '$1'"
}
