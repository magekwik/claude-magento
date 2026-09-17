#!/usr/bin/env bash
set -u
M=app/code/Acme/Catalog
[ -f "$M/etc/webapi.xml" ] || { echo "no webapi.xml"; exit 1; }
grep -q 'url="/V1/acme/brands"' "$M/etc/webapi.xml" || { echo "route missing"; exit 1; }
grep -q 'method="GET"' "$M/etc/webapi.xml" || { echo "GET missing"; exit 1; }
grep -q '<resource ref="' "$M/etc/webapi.xml" || { echo "no <resource ref>"; exit 1; }
if grep -q 'ref="anonymous"' "$M/etc/webapi.xml"; then echo "anonymous resource used"; exit 1; fi
ls "$M"/Api/*Interface.php >/dev/null 2>&1 || { echo "no Api/*Interface.php"; exit 1; }
[ -f "$M/etc/acl.xml" ] || { echo "no acl.xml"; exit 1; }
grep -q '<preference for="Acme\\Catalog\\Api\\[A-Za-z]' "$M/etc/di.xml" || { echo "no di.xml preference for the Api interface"; exit 1; }
exit 0
