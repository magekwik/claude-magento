#!/usr/bin/env bash
set -u
[ -f CLAUDE.md ] || { echo "CLAUDE.md missing"; exit 1; }
[ "$(grep -c '<!-- magento:begin -->' CLAUDE.md)" = "1" ] || { echo "begin marker count != 1"; exit 1; }
grep -q 'Mage-OS 3\.5\.0' CLAUDE.md || { echo "Mage-OS edition/version missing"; exit 1; }
grep -q 'Magento 2\.4\.9 base' CLAUDE.md || { echo "base release missing"; exit 1; }
if grep -Eq 'edition unknown|Magento Open Source|Adobe Commerce' CLAUDE.md; then echo "wrong edition"; exit 1; fi
grep -q 'Acme_Catalog' CLAUDE.md || { echo "module missing"; exit 1; }
[ -f .claude/rules/magento.md ] || { echo "rules file missing"; exit 1; }
exit 0
