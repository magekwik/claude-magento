#!/usr/bin/env bash
set -u
[ "$(grep -c '<!-- magento:begin -->' CLAUDE.md)" = "1" ] || { echo "begin marker count != 1 after two runs"; exit 1; }
[ "$(grep -c '<!-- magento:end -->' CLAUDE.md)" = "1" ] || { echo "end marker count != 1 after two runs"; exit 1; }
grep -q 'Team note: keep me.' CLAUDE.md || { echo "user text outside the block was lost"; exit 1; }
grep -q 'Hyvä' CLAUDE.md || { echo "Hyvä not detected"; exit 1; }
grep -q 'ddev exec' CLAUDE.md || { echo "DDEV prefix missing"; exit 1; }
grep -q 'production' CLAUDE.md || { echo "mode missing"; exit 1; }
R=.claude/rules/magento.md
grep -q '^## Frontend — Hyvä' "$R" || { echo "Hyvä section missing"; exit 1; }
if grep -q '^## Frontend — Luma' "$R"; then echo "Luma section present on Hyvä-only project"; exit 1; fi
exit 0
