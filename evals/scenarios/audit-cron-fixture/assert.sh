#!/usr/bin/env bash
# The fixture's midnight batch (sales_clean_quotes + 4 aggregate jobs at 0 0 * * *) queues in cron:run, and
# acme_feed_export runs 25 minutes every 30 in default. The audit must name both, propose a checked schedule
# that moves no fixed job, brand the offline report, and touch nothing outside var/.
set -u
O=var/cron-audit
for f in jobs.json history.json proposal.json report.html summary.md; do
  [ -s "$O/$f" ] || { echo "missing $O/$f"; exit 1; }
done
py() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$O/$1"; }
[ "$(py jobs.json "d['source']")" = "static" ] || { echo "fixture should be read statically"; exit 1; }
[ "$(py history.json "d['source']")" = "csv" ] || { echo "history not used"; exit 1; }
[ "$(py jobs.json "any(j['name']=='acme_feed_export' for j in d['jobs'])")" = "True" ] || { echo "custom job not inventoried"; exit 1; }
[ "$(py jobs.json "[j.get('schedule') for j in d['jobs'] if j['name']=='acme_feed_stock_sync']")" = "['15 * * * *']" ] || { echo "multi-line job or its config.xml default schedule missed"; exit 1; }
[ "$(py jobs.json "any(j['name']=='cron_test_job' for j in d['jobs'])")" = "False" ] || { echo "inventoried a test-fixture module not in config.php"; exit 1; }
FIXED='consumers_runner indexer_clean_all_changelogs indexer_reindex_all_invalid indexer_update_all_views sales_grid_order_async_insert sales_grid_order_creditmemo_async_insert sales_grid_order_invoice_async_insert sales_grid_order_shipment_async_insert sales_send_order_creditmemo_emails sales_send_order_emails sales_send_order_invoice_emails sales_send_order_shipment_emails'
for j in $FIXED; do
  [ "$(py proposal.json "'$j' in d.get('jobs',{})")" = "False" ] || { echo "proposal moves fixed job $j"; exit 1; }
done
[ "$(py proposal.json "'acme_feed_export' in d['jobs'] or any(int(g.get('use_separate_process',0))==1 for g in d.get('groups',{}).values())")" = "True" ] || { echo "long feed job not addressed"; exit 1; }
[ "$(py proposal.json "d['figures']['proposed']['peak_load'] <= d['figures']['now']['peak_load'] and d['figures']['proposed']['worst_wait_s'] <= d['figures']['now']['worst_wait_s']")" = "True" ] || { echo "proposal not checked better"; exit 1; }
grep -q 'acme_feed_export' "$O/summary.md" || { echo "feed job not named in summary"; exit 1; }
grep -Eq 'aggregate_sales_report|sales_clean_quotes' "$O/summary.md" || { echo "midnight batch not named in summary"; exit 1; }
grep -q '<job name=' "$O/summary.md" || { echo "no crontab.xml change given"; exit 1; }
grep -q 'Acme Agency' "$O/report.html" || { echo "brand missing from report"; exit 1; }
grep -q 'id="heat-current"' "$O/report.html" || { echo "current calendar missing"; exit 1; }
grep -q 'id="heat-proposed"' "$O/report.html" || { echo "proposed calendar missing"; exit 1; }
if grep -Eq 'https?://' "$O/report.html"; then echo "report references an external URL"; exit 1; fi
if grep -qi '<script' "$O/report.html"; then echo "report has a script"; exit 1; fi
[ -z "$(git status --porcelain)" ] || { echo "audit changed files outside var/:"; git status --porcelain; exit 1; }
exit 0
