---
name: audit
description: Audit a Magento 2 store from its code, config and cron history. `cron` inventories every cron job, works out the week's load from the schedules and measured run times, and writes a client-ready report (24/7 calendar, overlaps, a proposed lower-load schedule) plus the exact changes for a developer. Read-only; writes only var/cron-audit/. User-invoked only.
argument-hint: "cron [--history <csv|tsv>] [--quiet-hours HH-HH] [--brand \"<name>\"] [--logo <svg|png|jpg>]"
disable-model-invocation: true
---

# /magekwik-magento:audit

Arguments given: `$ARGUMENTS`

Rules for the whole run: work from the Magento root. Write nothing outside `var/cron-audit/`; change nothing in the store, its database or its config. Never read `app/etc/env.php` whole, never look for the user's Composer keys, and never connect to a live or remote database. The plugin ships no scripts: you use read-only commands, the environment's own tools and the SQL in the reference.

## 1. Area

The first argument is the area. `cron` is the only one available: anything else (or nothing) → print `Available audits: cron (more areas arrive in later releases)` and stop.

## 2. Project and environment

The project is Magento when `bin/magento` exists or `composer.json` requires a `magento/` or `mage-os/` package; otherwise print `not a Magento root: <path>` and stop. ENV, first match: `warden` (`.warden/`, or `.env` with a `WARDEN_ENV_TYPE=` line) → `ddev` (`.ddev/`) → `docker-magento` (a compose file and `bin/clinotty`) → `docker` (a compose file) → `native`. The CLI prefix is `warden env exec -T php-fpm`, `ddev exec`, none for docker-magento (`bin/magento` is its wrapper) and native, and for `docker` `docker compose exec -T <service>` with the service whose name contains `php` (ask if there is none or more than one). For Warden, DDEV and docker-magento the environment must be running; if a command says it is not, tell the user to start it (`warden env start`, `ddev start`, `bin/start`) and stop.

OUT = `var/cron-audit` (create it). QUIET = `--quiet-hours` or `01-05`. Options may be typed with a space or `=` (`--history cron_schedule.csv`, `--brand "Acme Agency"`, `--logo logo.svg`).

## 3. Inventory and history

Read `${CLAUDE_PLUGIN_ROOT}/skills/ops/references/cron-audit.md` in full, then:

1. Build `OUT/jobs.json` as its *Inventory* section says. If `bin/magento` does not run, tell the user in one line that the audit is built from the `crontab.xml` files only, and continue.
2. Build `OUT/history.json` as its *Measured run times* section says (`--history` file, else the environment's database command, else none — then tell the user how to export `cron_schedule` and that class durations are used meanwhile).

## 4. Analyse

Dispatch the `magekwik-magento:cron-auditor` agent with DIR (the Magento root), OUT, QUIET, the brand and the logo path. Wait for its two-line reply. If `OUT/summary.md` or `OUT/report.html` is missing when it returns, ask it for the missing file's full text and write it yourself — nothing else.

## 5. Hand-over

Print:

```
Cron audit written to var/cron-audit/
  report.html   for the client: open in a browser, print to PDF to send
  summary.md    for the developer: findings and the exact changes
Nothing in the store was changed.
```

Then the agent's two lines. Then one line: `Run it again after deploying the changes to see the new calendar.`
