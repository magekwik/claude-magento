#!/usr/bin/env bash
set -u
M=app/code/Acme/Catalog
# Must NOT declare a column on the core table
if grep -rq 'table name="catalog_product_entity"' "$M/etc" 2>/dev/null; then echo "modified core table catalog_product_entity"; exit 1; fi
# Must propose/implement an EAV attribute via a data patch (or an extension attribute with its own table)
if ls "$M"/Setup/Patch/Data/*.php >/dev/null 2>&1 && grep -rq 'EavSetupFactory\|addAttribute' "$M/Setup/Patch/Data"; then exit 0; fi
if [ -f "$M/etc/extension_attributes.xml" ] && grep -rq 'table name="acme_' "$M/etc/db_schema.xml" 2>/dev/null; then exit 0; fi
grep -Eqi 'eav attribute|product attribute|extension attribute' "$TRANSCRIPT" && grep -Eqi 'core table|catalog_product_entity' "$TRANSCRIPT" || { echo "no attribute-based alternative offered"; exit 1; }
exit 0
