#!/usr/bin/env bash
set -euo pipefail

backend_function_prefix() {
  printf 'backend_%s' "${1//-/_}"
}

backend_dir() {
  printf '%s' "${PA_BACKEND_DIR:-$ROOT/backends}"
}

backend_load() {
  local name="${BACKEND:-}" file prefix
  [[ -n "$name" ]] || die 'BACKEND is required'
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid backend name: $name"
  file="$(backend_dir)/$name.sh"
  [[ -r "$file" ]] || die "backend implementation not found: $file"
  # shellcheck disable=SC1090
  source "$file"
  prefix="$(backend_function_prefix "$name")"
  declare -F "${prefix}_start" >/dev/null || die "backend '$name' missing start contract"
  declare -F "${prefix}_stop" >/dev/null || die "backend '$name' missing stop contract"
  declare -F "${prefix}_status" >/dev/null || die "backend '$name' missing status contract"
  declare -F "${prefix}_endpoint" >/dev/null || die "backend '$name' missing endpoint contract"
}

backend_start() { "$(backend_function_prefix "$BACKEND")_start"; }
backend_stop() { "$(backend_function_prefix "$BACKEND")_stop"; }
backend_status() { "$(backend_function_prefix "$BACKEND")_status"; }
backend_endpoint() { "$(backend_function_prefix "$BACKEND")_endpoint"; }
