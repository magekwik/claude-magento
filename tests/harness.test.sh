#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
tmp=$(mktemp -d)
printf '{"a":{"b":[1,2,{"c":true}]},"n":null}' > "$tmp/x.json"
assert_eq "$(json_get "$tmp/x.json" a.b.2.c)" "true" "json bool"
assert_eq "$(json_get "$tmp/x.json" n)" "null" "json null"
assert_eq "$(json_get "$tmp/x.json" a.b.0)" "1" "json index"
echo "hello world" > "$tmp/f"
assert_contains "$tmp/f" "^hello" "contains"
assert_not_contains "$tmp/f" "goodbye" "not contains"
report
