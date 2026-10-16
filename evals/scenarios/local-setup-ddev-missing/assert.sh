#!/usr/bin/env bash
# With DDEV absent, local-setup must stop cleanly at step 4: ledger written and git-ignored, steps 1-3 done,
# step 4 blocked with a resume message, nothing scaffolded, nothing installed.
set -u
if command -v ddev >/dev/null 2>&1; then echo "precondition: ddev is on PATH, so this scenario cannot test the blocked path"; exit 1; fi
L=site/.magento-local.env
[ -f "$L" ] || { echo "ledger missing: $L"; exit 1; }
for s in STEP_1_TARGET STEP_2_SOURCE STEP_3_ENVIRONMENT; do
  grep -qx "$s=done" "$L" || { echo "$s not done"; exit 1; }
done
grep -qx 'STEP_4_PREREQUISITES=blocked' "$L" || { echo "step 4 not blocked"; exit 1; }
for s in STEP_5_SCAFFOLD STEP_6_CODE STEP_7_DATABASE STEP_8_CONFIGURE STEP_9_VERIFY; do
  grep -qx "$s=pending" "$L" || { echo "$s not pending"; exit 1; }
done
grep -qx 'SETUP_ENV=ddev' "$L" || { echo "SETUP_ENV not ddev"; exit 1; }
grep -q '^LAST_NOTE=\[step 4 blocked\]' "$L" || { echo "LAST_NOTE missing"; exit 1; }
git check-ignore -q "$L" || { echo "ledger not git-ignored"; exit 1; }
if git status --porcelain --untracked-files=all | grep -qF '.magento-local.env'; then echo "ledger shows in git status"; exit 1; fi
grep -q 're-run /magekwik-magento:local-setup to resume from step 4' "$TRANSCRIPT" || { echo "resume message missing"; exit 1; }
[ ! -e site/.ddev ] || { echo "scaffolded .ddev despite blocked prerequisites"; exit 1; }
[ ! -e site/composer.json ] || { echo "fetched code despite blocked prerequisites"; exit 1; }
exit 0
