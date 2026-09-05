#!/usr/bin/env bash
set -euo pipefail

# Apply the same profile/state/log resolution used by proxy-ctl and
# proxy-agent-health. The caller must source common.sh and profile.sh first.
profile_apply_context() {
  local name="$1"
  profile_load "$name"
  if [[ "${PA_STATE_DIR_EXPLICIT:-false}" != true ]]; then
    PA_STATE_DIR="${PA_STATE_DIR}/${name}"
  fi
  if [[ "${PA_LOG_DIR_EXPLICIT:-false}" != true ]]; then
    PA_LOG_DIR="${PA_LOG_DIR}/${name}"
  fi
  # PA_STATE_DIR and PA_LOG_DIR are now fully resolved profile paths. Mark
  # them explicit so downstream processes (notably the reconciler) consume
  # the resolved paths rather than appending the profile name a second time.
  PA_STATE_DIR_EXPLICIT=true
  PA_LOG_DIR_EXPLICIT=true
  PA_PROFILE="$name"
  export PA_PROFILE PA_ACTIVE_PROFILE PA_CONFIG PA_STATE_DIR PA_LOG_DIR
  export PA_STATE_DIR_EXPLICIT PA_LOG_DIR_EXPLICIT
}
