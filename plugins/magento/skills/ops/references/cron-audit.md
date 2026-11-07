# Cron audit rules

Used by `/magekwik-magento:audit cron` and the `magekwik-magento:cron-auditor` agent. The audit has no scripts: it reads the store's config files, runs read-only commands and SQL, and works out the week from the schedules and measured run times. Everything it writes goes to `var/cron-audit/`.

## Inventory (`jobs.json`)

- **Jobs:** every `etc/crontab.xml` under `app/code` and `vendor` (`find app/code vendor -path '*/etc/crontab.xml'`), parsed as XML, never line by line: `<job>` attributes are often split over several lines, and a line grep loses those jobs. Parse each file with `python3 -I -c` and `xml.etree.ElementTree` (iterate `group` → `job`; read `name`, `instance`, `method`, and the `schedule` or `config_path` child). A job belongs to its `<group id>`; with neither `<schedule>` nor `<config_path>` it never runs on its own; list it as unscheduled. The module name is in the folder's `etc/module.xml`. When `app/etc/config.php` lists modules, keep only those it lists as `1`: that skips disabled modules and the test fixtures some packages ship under `vendor/*/tests/`. When the same group and job name appear twice, the later module in `config.php`'s order wins.
- **Overrides:** when `bin/magento` runs (through the environment's prefix), `bin/magento config:show` lines starting `crontab/` override schedules (`crontab/<group>/jobs/<job>/schedule/cron_expr`). A `crontab/<group>/jobs/<job>/run/model` line with no `crontab.xml` entry is a job defined in config only (scheduled import/export operations); add it with that schedule. Each `config_path` resolves with `bin/magento config:show <config_path>`, which returns database values only: when it says the path doesn't exist, the value is the `<default>` in the owning module's `etc/config.xml` (find it with `ElementTree`'s `find('default/<path>')` over `vendor` and `app/code`), and with no default anywhere the job never runs. When `bin/magento` does not run, use the XML, `app/etc/config.php`'s `system` values and the `config.xml` defaults, and say so (`source: static`). Record where each `config_path` schedule came from (`db`, `config.xml`, `none`).
- **Groups:** `etc/cron_groups.xml` (core `default`: `schedule_lifetime` 15 on a real store; read the values, never assume) and `config:show system/cron/` overrides; `use_separate_process` decides who runs the group.
- **Timezone:** the store's `general/locale/timezone` (`config:show`, else `app/etc/config.php`), else UTC.

Write `var/cron-audit/jobs.json`: `{"source":"magento|static","timezone":"…","groups":{"<g>":{settings}},"jobs":[{"name","group","instance","method","schedule","config_path","class","module"}]}` in file order.

## Measured run times (`history.json`)

Successful rows live in `cron_schedule` only `history_success_lifetime` minutes (60 in core), failures 3 days, so a store's own table usually holds about an hour of successes. Use what there is; for a measured week, the owner sets `bin/magento config:set system/cron/default/history_success_lifetime 10080`, waits a week, and runs the audit again (say so in the summary when history is short).

Sources, first that works: `--history <file>` (a CSV or TSV export with `job_code,status,scheduled_at,executed_at,finished_at`; read it with `awk`/`sort`, never into the chat whole); else the environment's own database command — Warden `warden db connect -e "<SQL>"`, DDEV `ddev mysql -e "<SQL>"`, docker-magento `bin/mysql -e "<SQL>"` — which use the environment's local login; else none (native and plain Docker: never read `app/etc/env.php` for a password; tell the user how to export the table with the query below and re-run with `--history`). Never connect to a remote database.

Per job (all from `cron_schedule`, prefix the table if the store uses one):

```sql
SELECT job_code, status, COUNT(*) AS n,
  ROUND(AVG(TIMESTAMPDIFF(SECOND, executed_at, finished_at))) AS avg_s,
  MAX(TIMESTAMPDIFF(SECOND, executed_at, finished_at)) AS max_s,
  MAX(TIMESTAMPDIFF(SECOND, scheduled_at, executed_at)) AS max_late_s,
  MIN(scheduled_at) AS first_at, MAX(scheduled_at) AS last_at
FROM cron_schedule GROUP BY job_code, status ORDER BY job_code, status;
```

Export for `--history`: `SELECT job_code, status, scheduled_at, executed_at, finished_at FROM cron_schedule` to CSV with a header line. Write `var/cron-audit/history.json`: `{"source":"csv|database|none","window":{"from","to"},"jobs":{"<job>":{"runs","avg_s","max_s","max_late_s","missed","errors","pending"}}}` — `missed` and `errors` are the counts of those statuses.

## How cron:run really executes (2.4.x core)

- Every minute the system crontab starts one `bin/magento cron:run`. It first starts a background `cron:run --group=<g>` for each group whose `system/cron/<g>/use_separate_process` is 1 (core: `index`, `consumers`, `analytics`). It then handles **every other group itself, one after another**, `default` included.
- When a process reaches a group it loads **every pending row of that group**, from its own minute or any earlier one, and goes through them oldest first. A row another process has already started is skipped. A row whose job is still running elsewhere (its lock is held) stays pending for a later process. Each job runs at most once per pass. A row older than the group's `schedule_lifetime` (minutes; 15 in core's `default`) is marked **missed** and never runs.
- So a job queued behind a long one does not wait for it: the next minute's `cron:run` finds the row still pending and starts it. That has three consequences. A batch of heavy jobs due in the same minute ends up running **at the same time**, one per process, which is the real load spike (core's midnight batch). Each long job ahead of a row pushes it back about a minute, and a row not started within `schedule_lifetime` is missed. And because a pass runs a job only once, oldest row first, an every-minute job that falls behind **stays behind**: it keeps running that many minutes late, up to `schedule_lifetime`, beyond which its oldest rows are missed.
- The real problems are therefore load spikes, late or missed runs, and jobs that cannot keep up: a job still running when its next row is due, or with missed rows, is a **self-overlap**. A run that starts more than 60 s late is **delayed**.
- Schedules are in the admin store timezone. Day-of-week `7` never matches (Magento compares it to 0–6), so `0 0 * * 7` never runs.
- Successful history is kept for `history_success_lifetime` minutes (60 by default). An audit with little history uses the weight classes below.

## Weight classes

Default durations are used when a job has fewer than 3 measured successful runs: light 5 s (weight 1), medium 2 min (2), heavy 10 min (4), very heavy 30 min (8). A measured job takes the weight of its duration (under 1 min 1, under 5 min 2, under 20 min 4, else 8). An unknown job is light. Raise it only on evidence: a measured duration, or, for a job that runs hourly or less often, a class or job name containing `Export`, `Feed`, `Import`, `Sync`, `Reindex` or `Generate` (heavy). A job due every few minutes that really took 10 minutes would show in the history as missed or erroring rows, so a name alone never makes a frequent job heavy. Say in the summary how many jobs are measured and how many use a class.

<!-- classes:begin -->
| Job | Class |
|---|---|
| `aggregate_sales_report_bestsellers_data` | heavy |
| `aggregate_sales_report_coupons_data` | medium |
| `aggregate_sales_report_invoiced_data` | medium |
| `aggregate_sales_report_order_data` | heavy |
| `aggregate_sales_report_refunded_data` | medium |
| `aggregate_sales_report_shipment_data` | medium |
| `aggregate_sales_report_tax_data` | medium |
| `analytics_collect_data` | heavy |
| `captcha_delete_expired_images` | light |
| `captcha_delete_old_attempts` | light |
| `catalog_product_alert` | medium |
| `catalog_product_frontend_actions_flush` | light |
| `catalog_product_outdated_price_values_cleanup` | light |
| `catalogrule_apply_all` | very_heavy |
| `consumers_runner` | light |
| `currency_rates_update` | light |
| `indexer_clean_all_changelogs` | light |
| `indexer_reindex_all_invalid` | light |
| `indexer_update_all_views` | light |
| `newsletter_send_all` | medium |
| `sales_clean_quotes` | heavy |
| `sales_grid_order_async_insert` | light |
| `sales_grid_order_creditmemo_async_insert` | light |
| `sales_grid_order_invoice_async_insert` | light |
| `sales_grid_order_shipment_async_insert` | light |
| `sales_send_order_creditmemo_emails` | light |
| `sales_send_order_emails` | light |
| `sales_send_order_invoice_emails` | light |
| `sales_send_order_shipment_emails` | light |
| `sitemap_generate` | heavy |
<!-- classes:end -->

## Never move

These jobs' timing is their function, and nothing in the `index` group moves either. A proposal that changes one is wrong; drop that change.

<!-- fixed:begin -->
- `consumers_runner`: starts the message-queue consumers
- `indexer_clean_all_changelogs`
- `indexer_reindex_all_invalid`
- `indexer_update_all_views`: keeps prices, stock and search current
- `sales_grid_order_async_insert`
- `sales_grid_order_creditmemo_async_insert`
- `sales_grid_order_invoice_async_insert`
- `sales_grid_order_shipment_async_insert`
- `sales_send_order_creditmemo_emails`
- `sales_send_order_emails`: customer order emails
- `sales_send_order_invoice_emails`
- `sales_send_order_shipment_emails`
<!-- fixed:end -->

## Safe moves, in order of preference

1. **Take heavy and long jobs out of `default`.** A long job in a group that runs inside `cron:run` (`default` and any custom group with `use_separate_process` 0) ties up that minute's `cron:run`, so every row after it, including the every-minute order emails and grid inserts, waits for the next minute's process, and an every-minute job pushed back that way stays behind. Give such jobs their own group with `use_separate_process` 1: one group per family, such as `reports` for `sales_clean_quotes` and the `aggregate_sales_report_*` jobs, or one for a feed export. Copy the `default` group's settings and set `use_separate_process` to 1 (applied with the plugin under *Ready-to-apply changes*). Separating a job mostly changes who waits, not the load: the job already ran alongside the jobs due with it (picked up by the next minute's process), and in its own group it still does. To lower a load peak, also give it a slot clear of the other heavy jobs (move 2). Always re-measure; if separating raises the peak or the waits, leave the job in `default` and re-time it instead.
2. **Spread jobs that share a minute within their group.** Jobs due in the same minute in one group start a minute or so apart and then run side by side, so a shared minute is a load spike. Give daily heavy jobs slots in the quiet window, by default 01:00–05:00 store time (`--quiet-hours`), at least their run time apart. Keep them clear of other heavy jobs' windows (for example `catalogrule_apply_all`, 01:00 for about 30 minutes), so the load peak does not rise. Reports aggregated at 02:00 instead of 00:00 still cover the whole previous day.
3. **Shift the minute offset** of hourly and `*/n` jobs that land together on `:00`, keeping their frequency.
4. **Lower the frequency** only for jobs that tolerate it (cleanup and report jobs), never for anything a customer or the admin waits on.

Every proposed schedule must be a valid expression that matches at least one minute of a normal week and does not depend on the day of month or the month (no `0 0 1 * *`, no day-of-week `7`).

## Working out the week

For each job: its run time is the measured `avg_s` (3+ successful runs) or its class duration; its run minutes come from the schedule (`*/n`, lists, ranges and steps per field; store time). Use exact arithmetic (`awk`, `bc` or `python3 -c` for sums), never estimates in your head. For every hour of the week (7 × 24, Monday first):

- **load** = the sum of `weight × seconds running in that hour` over all jobs, divided by 3600 (a run that crosses the hour counts in each hour it runs; a heavy job running 10 minutes adds 0.67; a light 5-second job every minute adds 0.08). Count seconds, not whole minutes: a store with dozens of every-minute jobs otherwise shows a flat, high load that hides the real peaks;
- **jobs due together** = the largest number of jobs in one group due in the same minute of that hour;
- **late risk** = a minute where an inline group (`use_separate_process` 0) has a job of 2 minutes or more due together with others: each job behind it starts about a minute later per long job ahead; behind more than `schedule_lifetime` minutes, it is missed.

Report the **peak load** (highest hourly load, with its day and hour), the **worst wait** (the longest expected delay, with the job and the hour), **self-overlaps** (`avg_s` or class duration ≥ the job's interval, or measured `missed` > 0) and the **largest batch** (jobs due together). Measured `max_late_s`, `missed` and `errors` from `history.json` come first; the worked-out figures fill the gaps, and the summary says which is which.

## Checking a proposal

Work the week out again with the proposed schedules and groups. Keep the proposal only when no fixed job or `index`-group job changed, every schedule is valid (above), and the peak load and worst wait are each no higher than now, with at least one lower or a self-overlap removed. Otherwise undo the change that made a figure worse and check again — at most two revisions; then propose nothing and say no safe improvement was found.

## Writing findings

Each finding is written for the store owner first: `impact` says what a customer, the admin or the server experiences ("order confirmation emails can arrive up to 14 minutes late around midnight"), and `fix` says the change in one sentence. Severity: **high** for anything customers notice (late emails, stale prices or stock) or a self-overlap, **medium** for admin-facing delays or load peaks above 8, **low** for tidy-ups. Use the figures worked out above and the measured ones from `history.json`, and say which is which.

## Ready-to-apply changes (summary.md)

**Re-timing jobs** goes in a small module of the developer's own. It loads after the modules that own the jobs (`sequence`). The job keeps its `instance` and `method`, and only `schedule` changes (moving a job to another group is covered below):

```xml
<!-- app/code/<Vendor>/CronSchedule/etc/crontab.xml -->
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:module:Magento_Cron:etc/crontab.xsd">
    <group id="default">
        <job name="aggregate_sales_report_order_data" instance="Magento\Sales\Model\CronJob\AggregateSalesReportOrderData" method="execute">
            <schedule>10 1 * * *</schedule>
        </job>
    </group>
</config>
```

```xml
<!-- app/code/<Vendor>/CronSchedule/etc/module.xml -->
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Module/etc/module.xsd">
    <module name="<Vendor>_CronSchedule">
        <sequence><module name="Magento_Sales"/></sequence>
    </module>
</config>
```

**Moving a job to another group** cannot be done in `crontab.xml`: Magento merges cron config by group id and job name, so a job declared under a second group runs in both. Move it with a small plugin on the cron config instead, in the same module:

```xml
<!-- app/code/<Vendor>/CronSchedule/etc/di.xml -->
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:ObjectManager/etc/config.xsd">
    <type name="Magento\Cron\Model\ConfigInterface">
        <plugin name="vendor_cron_schedule_regroup" type="Vendor\CronSchedule\Plugin\RegroupCronJobs"/>
    </type>
</config>
```

```php
<?php
// app/code/<Vendor>/CronSchedule/Plugin/RegroupCronJobs.php
declare(strict_types=1);

namespace Vendor\CronSchedule\Plugin;

use Magento\Cron\Model\ConfigInterface;

class RegroupCronJobs
{
    /** job code => the group it runs in */
    private const MOVES = ['acme_feed_export' => 'acme_feed'];

    public function afterGetJobs(ConfigInterface $subject, array $jobs): array
    {
        foreach (self::MOVES as $code => $target) {
            foreach ($jobs as $group => $groupJobs) {
                if ($group !== $target && isset($groupJobs[$code])) {
                    $jobs[$target][$code] = $groupJobs[$code];
                    unset($jobs[$group][$code]);
                }
            }
        }
        return $jobs;
    }
}
```

Re-time a moved job with the `crontab.xml` override under its **original** group (the plugin carries the new schedule across). Declare the new group in the module's `etc/cron_groups.xml`, with every setting copied from `default` and `use_separate_process` set to 1. `<Vendor>` and `Vendor` are placeholders for the developer's own vendor name.

**Jobs whose schedule comes from `config_path`** are changed with `bin/magento config:set <config_path> "<expr>"` (lock it with `--lock-env` to keep it in `env.php`).

**Deploy:** in developer mode `bin/magento setup:upgrade` then `bin/magento cache:clean config compiled_config`; in production use your normal deploy pipeline, or `bin/magento setup:upgrade`, `bin/magento setup:di:compile`, `bin/magento setup:static-content:deploy` (the regroup plugin is a `di.xml` change, so production needs the compile). Old pending rows in `cron_schedule` expire on their own.

## The client report (`report.html`)

One self-contained HTML file, written with the Write tool: inline `<style>`, no scripts, no external URLs, no web fonts, readable when printed to PDF. In order:

1. Header: the brand (`--brand`, else "Cron audit"), the store or folder name, the date, and the logo when `--logo` was given (copy the file into `var/cron-audit/` and reference it by file name).
2. The verdict paragraph and a table of the key figures, now → proposed: peak load, worst wait, self-overlaps, largest batch, plus measured late and missed runs when history exists.
3. Two calendars, `<table id="heat-current">` and `<table id="heat-proposed">`: rows Monday–Sunday, columns 00–23, each cell the hourly load (one decimal) with a background from white (0) to deep red (the highest value of both calendars), so the two compare by colour. Omit the proposed one when nothing was proposed.
4. The findings, numbered, each with severity, impact and fix.
5. The jobs table: name, group, schedule now → proposed, run time and whether it was measured or a class default.
6. A footer: where the run times come from (history window or class defaults), the timezone, and "Nothing in the store was changed."
