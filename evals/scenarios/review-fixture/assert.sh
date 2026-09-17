#!/usr/bin/env bash
set -u
T="$TRANSCRIPT"
grep -q 'Save.php:12' "$T" || { echo "ObjectManager line (12) not reported"; exit 1; }
grep -q 'Save.php:14' "$T" || { echo "raw SQL line (14) not reported"; exit 1; }
grep -Eqi 'ObjectManager' "$T" || { echo "ObjectManager not named"; exit 1; }
grep -Eqi 'HttpPostActionInterface|CSRF' "$T" || { echo "CSRF/HttpPost issue not reported"; exit 1; }
n=$(grep -Ec '^\[(blocker|major)\]' "$T")
[ "$n" -ge 3 ] || { echo "expected >=3 blocker/major findings, got $n"; exit 1; }
grep -Eq '^Verdict: .* — not mergeable as is' "$T" || { echo "verdict missing or wrong"; exit 1; }
grep -q 'PHPCS: not run' "$T" || { echo "PHPCS-unavailable line missing (fixture has no vendor/bin/phpcs)"; exit 1; }
# read-only: the bad file must be unchanged
grep -q 'ObjectManager::getInstance' app/code/Acme/Catalog/Controller/Index/Save.php || { echo "reviewer modified the file"; exit 1; }
exit 0
