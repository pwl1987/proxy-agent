#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/route.sh"

assert_match() {
  route_rule_match "$1" "$2" "$3"
}

assert_no_match() {
  if route_rule_match "$1" "$2" "$3"; then
    printf 'unexpected route match: %s %s %s\n' "$1" "$2" "$3" >&2
    return 1
  fi
}

assert_match 'api.example.com' wildcard '*.example.com'
assert_no_match 'api.example.com' wildcard 'api.+.example.com'
assert_match 'api.+.example.com' wildcard 'api.+.example.com'
assert_no_match 'apiXexampleYcom' wildcard 'api.example.com'
assert_match 'foo(bar).example.com' wildcard 'foo(bar).example.com'
assert_no_match 'fooxbarx.example.com' wildcard 'foo(bar).example.com'
assert_match 'a+b.example.com' wildcard 'a+b.example.com'
assert_match 'x?a.example.com' wildcard 'x?a.example.com'

ROUTE_RULES=$'10|DIRECT|wildcard|api.+.example.com\n20|PROXY|wildcard|*.example.com'
route_validate_rules

printf 'route matcher smoke: PASS\n'
