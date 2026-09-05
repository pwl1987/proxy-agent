#!/usr/bin/env bash
set -euo pipefail

ssh_reference_resolve() {
  local ref="$1" path
  [[ "$ref" == file:* ]] || die "不支持的 SSH reference: $ref"
  path="${ref#file:}"
  [[ -n "$path" ]] || die 'SSH file reference 为空'
  path="$(expand_home "$path")"
  [[ -f "$path" ]] || die "SSH reference 不存在: $path"
  [[ -r "$path" ]] || die "SSH reference 不可读: $path"
  printf '%s' "$path"
}

ssh_identity_resolve() {
  local ref="$1" path mode octal_mode
  path="$(ssh_reference_resolve "$ref")"
  mode="$(stat -c '%a' "$path" 2>/dev/null || true)"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "无法检查 SSH identity 权限: $path"
  octal_mode=$((8#$mode))
  (( (octal_mode & 0077) == 0 )) || die "SSH identity 权限过宽: $path"
  printf '%s' "$path"
}

ssh_known_hosts_resolve() {
  ssh_reference_resolve "$1"
}
