#!/usr/bin/env bash
set -u
tpl=$(find app -name '*.phtml' -newer composer.json | head -1)
[ -n "$tpl" ] || { echo "no template created"; exit 1; }
if grep -rEq 'define\(\[|data-bind=|x-magento-init|data-mage-init|requirejs|jQuery|\$\(' app/design app/code --include='*.phtml' --include='*.js'; then echo "Luma JS stack used"; exit 1; fi
grep -q 'x-data' "$tpl" || { echo "no Alpine x-data"; exit 1; }
grep -Eq 'sessionStorage|x-show' "$tpl" || { echo "no dismiss state handling"; exit 1; }
grep -q 'escaper->escapeHtml' "$tpl" || { echo "no escaping"; exit 1; }
layout=$(find app -path '*layout/default.xml' -newer composer.json | head -1)
[ -n "$layout" ] || { echo "no default.xml layout"; exit 1; }
grep -Eqi 'tailwind.config|build-prod|content' "$TRANSCRIPT" || { echo "transcript does not mention Tailwind rebuild/content paths"; exit 1; }
exit 0
