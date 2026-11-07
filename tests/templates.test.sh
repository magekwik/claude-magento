#!/usr/bin/env bash
# The rules templates shipped in the plugin must equal a fresh render of the conventions skill.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
bash "$ROOT/tools/build-templates.sh" "$tmp"
for v in luma hyva hyva-luma; do
  if cmp -s "$tmp/rules-$v.md" "$ROOT/plugins/magento/templates/rules-$v.md"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: templates/rules-$v.md is stale — run tools/build-templates.sh"; fi
done
assert_contains "$ROOT/plugins/magento/templates/rules-luma.md" "^## Frontend — Luma" "luma template has Luma"
assert_not_contains "$ROOT/plugins/magento/templates/rules-luma.md" "^## Frontend — Hyvä" "luma template has no Hyvä"
assert_not_contains "$ROOT/plugins/magento/templates/rules-hyva.md" "^## Frontend — Luma" "hyva template has no Luma"
assert_contains "$ROOT/plugins/magento/templates/rules-hyva-luma.md" "^## Frontend — Hyvä" "both template has Hyvä"
rm -rf "$tmp"
report
