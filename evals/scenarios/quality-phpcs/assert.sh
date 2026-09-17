#!/usr/bin/env bash
set -u
grep -q 'magento/magento-coding-standard' "$TRANSCRIPT" || { echo "coding standard package not mentioned"; exit 1; }
grep -q -- '--standard=Magento2' "$TRANSCRIPT" || { echo "--standard=Magento2 not shown"; exit 1; }
t=$(find app/code/Acme/Catalog/Test/Unit -name '*Test.php' 2>/dev/null | head -1)
[ -n "$t" ] || { echo "no unit test created under Test/Unit"; exit 1; }
grep -Eq 'extends TestCase|PHPUnit\\Framework\\TestCase' "$t" || { echo "test does not extend TestCase"; exit 1; }
grep -q 'declare(strict_types=1)' "$t" || { echo "test lacks strict_types"; exit 1; }
exit 0
