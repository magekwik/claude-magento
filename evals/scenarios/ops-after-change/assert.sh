#!/usr/bin/env bash
set -u
grep -q 'db-declaration:generate-whitelist' "$TRANSCRIPT" || { echo "whitelist regeneration not mentioned"; exit 1; }
grep -q 'setup:upgrade' "$TRANSCRIPT" || { echo "setup:upgrade not mentioned"; exit 1; }
grep -Eq 'cache:(clean|flush)' "$TRANSCRIPT" || { echo "cache clean/flush not mentioned"; exit 1; }
# whitelist must come before setup:upgrade
wl=$(grep -n 'db-declaration:generate-whitelist' "$TRANSCRIPT" | head -1 | cut -d: -f1)
su=$(grep -n 'setup:upgrade' "$TRANSCRIPT" | head -1 | cut -d: -f1)
[ "$wl" -lt "$su" ] || { echo "whitelist not before setup:upgrade"; exit 1; }
# developer mode: di:compile must not be presented as required
if grep -Eq 'setup:di:compile' "$TRANSCRIPT" && ! grep -Eqi 'not (needed|required)|only in production|production mode' "$TRANSCRIPT"; then echo "di:compile presented as required in developer mode"; exit 1; fi
exit 0
