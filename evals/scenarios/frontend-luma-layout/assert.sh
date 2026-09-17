#!/usr/bin/env bash
set -u
layout=$(find app -path '*layout/default.xml' -newer composer.json 2>/dev/null | head -1)
[ -n "$layout" ] || { echo "no default.xml layout created"; exit 1; }
grep -Eq 'referenceContainer|referenceBlock' "$layout" || { echo "layout does not reference a container/block"; exit 1; }
grep -q 'view_model' "$layout" || { echo "no view_model argument in layout"; exit 1; }
tpl=$(find app -name '*.phtml' -newer composer.json | head -1)
[ -n "$tpl" ] || { echo "no template created"; exit 1; }
grep -q 'escaper->escapeHtml' "$tpl" || { echo "template does not use \$escaper->escapeHtml"; exit 1; }
if grep -q 'block->escapeHtml' "$tpl"; then echo "deprecated \$block->escapeHtml used"; exit 1; fi
vm=$(grep -rl 'implements .*ArgumentInterface' app 2>/dev/null | head -1)
[ -n "$vm" ] || { echo "no ViewModel implementing ArgumentInterface"; exit 1; }
if grep -rq 'cacheable="false"' app/design app/code; then echo "cacheable=false used"; exit 1; fi
exit 0
