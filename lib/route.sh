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
  local line="$1" priority action matcher pattern extra
  IFS='|' read -r priority action matcher pattern extra <<< "$line"
  [[ -z "${extra:-}" && -n "${pattern:-}" ]] || return 1
  [[ "$priority" =~ ^[0-9]+$ ]] || return 1
  [[ "$action" == DIRECT || "$action" == PROXY ]] || return 1
  [[ "$matcher" == exact || "$matcher" == suffix || "$matcher" == wildcard || "$matcher" == cidr ]] || return 1
  printf '%s\t%s\t%s\t%s\n' "$priority" "$action" "$matcher" "$pattern"
}

route_validate_rules() {
  local line priority action matcher pattern extra line_no=0 errors=0
  [[ -z "${ROUTE_RULES:-}" ]] && return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    [[ -z "$line" ]] && continue
    IFS='|' read -r priority action matcher pattern extra <<< "$line"
    if [[ -n "${extra:-}" || -z "${pattern:-}" ]]; then
      printf '[config] ERROR: ROUTE_RULES line %d must be priority|action|matcher|pattern\n' "$line_no" >&2
      errors=$((errors + 1))
      continue
    fi
    if [[ ! "$priority" =~ ^[0-9]+$ ]]; then
      printf '[config] ERROR: ROUTE_RULES line %d has invalid priority: %s\n' "$line_no" "$priority" >&2
      errors=$((errors + 1))
    fi
    if [[ "$action" != DIRECT && "$action" != PROXY ]]; then
      printf '[config] ERROR: ROUTE_RULES line %d has invalid action: %s\n' "$line_no" "$action" >&2
      errors=$((errors + 1))
    fi
    case "$matcher" in
      exact|suffix|wildcard)
        [[ "$pattern" != *[[:space:]]* ]] || {
          printf '[config] ERROR: ROUTE_RULES line %d pattern contains whitespace\n' "$line_no" >&2
          errors=$((errors + 1))
        }
        ;;
      cidr)
        valid_ipv4_cidr "$pattern" || {
          printf '[config] ERROR: ROUTE_RULES line %d has invalid CIDR: %s\n' "$line_no" "$pattern" >&2
          errors=$((errors + 1))
        }
        ;;
      *)
        printf '[config] ERROR: ROUTE_RULES line %d has invalid matcher: %s\n' "$line_no" "$matcher" >&2
        errors=$((errors + 1))
        ;;
    esac
  done <<< "$ROUTE_RULES"
  return "$errors"
}

route_explain() {
  local host="${1,,}" line priority action matcher pattern
  [[ -n "$host" ]] || { printf '代理   （主机名为空）\n'; return 0; }
  local -a rules=()
  if [[ -n "${ROUTE_RULES:-}" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      if route_rule_line "$line" >/dev/null; then
        rules+=("$line")
      else
        warn "忽略无效的 ROUTE_RULES 规则：$line"
      fi
    done <<< "${ROUTE_RULES}"
  fi

  if ((${#rules[@]})); then
    while IFS=$'\t' read -r priority action matcher pattern; do
      if route_rule_match "$host" "$matcher" "$pattern"; then
        if [[ "$action" == DIRECT ]]; then
          printf '直连  %s  （规则 %s：%s %s）\n' "$host" "$priority" "$matcher" "$pattern"
        else
          printf '代理  %s  （规则 %s：%s %s）\n' "$host" "$priority" "$matcher" "$pattern"
        fi
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
      printf '直连  %s  （兼容域名策略：%s）\n' "$host" "$item"
      return 0
    fi
  done

  IFS=',' read -r -a items <<< "${DIRECT_CIDRS:-}"
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || continue
    if cidr_contains "$host" "$item"; then
      printf '直连  %s  （兼容 CIDR 策略：%s）\n' "$host" "$item"
      return 0
    fi
  done

  printf '代理  %s  （默认策略）\n' "$host"
}
