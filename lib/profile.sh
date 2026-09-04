#!/usr/bin/env bash
set -euo pipefail

profile_dir() {
  if [[ -n "${PA_PROFILE_DIR:-}" ]]; then
    printf '%s' "$PA_PROFILE_DIR"
  elif (( EUID == 0 )); then
    printf '%s' /etc/proxy-agent/profiles
  else
    printf '%s/proxy-agent/profiles' "${XDG_CONFIG_HOME:-$HOME/.config}"
  fi
}

profile_path() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid profile name: $name"
  printf '%s/%s.conf' "$(profile_dir)" "$name"
}

profile_exists() { [[ -r "$(profile_path "$1")" ]]; }

profile_list() {
  local dir
  dir="$(profile_dir)"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' 2>/dev/null |
    sed 's/\.conf$//' | sort
}

profile_load() {
  local name="$1" path
  path="$(profile_path "$name")"
  [[ -r "$path" ]] || die "profile not found: $name ($path)"
  require_secure_config_file "$path"
  # shellcheck disable=SC1090
  source "$path"
  PA_ACTIVE_PROFILE="$name"
  PA_CONFIG="$path"
}
