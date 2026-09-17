#!/usr/bin/env bash
set -u
M=app/code/Acme/Catalog
[ -f "$M/etc/events.xml" ] || { echo "no events.xml"; exit 1; }
grep -q 'sales_order_place_after' "$M/etc/events.xml" || { echo "events.xml lacks sales_order_place_after"; exit 1; }
obs=$(grep -rl 'implements .*ObserverInterface' "$M/Observer" 2>/dev/null | head -1)
[ -n "$obs" ] || { echo "no observer implementing ObserverInterface under $M/Observer"; exit 1; }
grep -q 'LoggerInterface' "$obs" || { echo "observer does not inject LoggerInterface"; exit 1; }
if grep -rq 'ObjectManager::getInstance' "$M"; then echo "ObjectManager::getInstance used"; exit 1; fi
grep -q 'declare(strict_types=1)' "$obs" || { echo "observer lacks strict_types"; exit 1; }
exit 0
