#!/usr/bin/env bash
set -euo pipefail

route_rule_match() {
  local host="${1,,}" matcher="$2" pattern="${3,,}"
  case "$matcher" in
    exact)
      [[ "$host" == "$pattern" ]]
      ;;
    suffix)
      pattern="${pattern#.}"
      [[ "$host" == "$pattern" || "$host" == *".$pattern" ]]
      ;;
    wildcard)
      local re="${pattern//./\\.}"
      re="${re//\*/.*}"
      [[ "$host" =~ ^${re}$ ]]
      ;;
    cidr)
      cidr_contains "$host" "$pattern"
      ;;
    *)
      return 1
      ;;
  esac
}

route_rule_line() {
  local line="$1" priority action matcher pattern
  IFS='|' read -r priority action matcher pattern <<< "$line"
  [[ "$priority" =~ ^[0-9]+$ ]] || return 1
  [[ "$action" == DIRECT || "$action" == PROXY ]] || return 1
  [[ "$matcher" == exact || "$matcher" == suffix || "$matcher" == wildcard || "$matcher" == cidr ]] || return 1
  [[ -n "$pattern" ]] || return 1
  printf '%s\t%s\t%s\t%s\n' "$priority" "$action" "$matcher" "$pattern"
}

route_explain() {
  local host="${1,,}" line priority action matcher pattern
  [[ -n "$host" ]] || { printf 'PROXY   (empty host)\n'; return 0; }
  local -a rules=()
  if [[ -n "${ROUTE_RULES:-}" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      if route_rule_line "$line" >/dev/null; then
        rules+=("$line")
      else
        warn "ignoring invalid ROUTE_RULES entry: $line"
      fi
    done <<< "${ROUTE_RULES}"
  fi

  if ((${#rules[@]})); then
    while IFS=$'\t' read -r priority action matcher pattern; do
      if route_rule_match "$host" "$matcher" "$pattern"; then
        printf '%s  %s  (rule %s: %s %s)\n' "$action" "$host" "$priority" "$matcher" "$pattern"
        return 0
      fi
    done < <(printf '%s\n' "${rules[@]}" | while IFS= read -r rule; do route_rule_line "$rule"; done | sort -n -k1,1)
  fi

  local item
  IFS=',' read -r -a items <<< "${DIRECT_DOMAINS:-}"
  for item in "${items[@]}"; do
    item="${item#.}"
    item="${item,,}"
    [[ -n "$item" ]] || continue
    if [[ "$host" == "$item" || "$host" == *".$item" ]]; then
      printf 'DIRECT  %s  (legacy domain policy: %s)\n' "$host" "$item"
      return 0
    fi
  done

  IFS=',' read -r -a items <<< "${DIRECT_CIDRS:-}"
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || continue
    if cidr_contains "$host" "$item"; then
      printf 'DIRECT  %s  (legacy CIDR policy: %s)\n' "$host" "$item"
      return 0
    fi
  done

  printf 'PROXY   %s  (default route)\n' "$host"
}
