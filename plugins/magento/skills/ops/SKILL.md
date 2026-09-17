---
name: ops
description: Running and debugging Magento 2 — bin/magento workflows (setup:upgrade, di:compile, static-content:deploy, cache, indexers, modes), reading var/log and var/report, Xdebug, cache layers (FPC, Varnish, LiteMage, Redis), dev environments (Warden, DDEV, Docker), version upgrades and security patches. Use when something must be run, deployed, upgraded or diagnosed in Magento Open Source 2.4.
---

# Magento 2 operations

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).*

Rules: see `magento:conventions` A6, A7, P3, P5, L5. This skill cites them by ID and does not restate them.

Every `bin/magento` line below is written as `$MAGE bin/magento …`. `$MAGE` is the command prefix for the project's environment — empty for a native install, `warden env exec php-fpm` for Warden, `ddev exec` for DDEV, `docker compose exec <php-service>` for a plain Compose stack; `references/dev-envs.md` says how to tell which one you are in. Composer, `php` and `grunt`/`npm` run behind the same prefix (inside the container, never on the host against the container's files).

## When to use

- Deciding which commands to run after a code, schema, config or theme change — and in which order.
- Deploying to production; switching modes; compiling; deploying static content; enabling/disabling caches and indexers.
- Diagnosing a 500, a blank page, "Area code is not set", a class that "does not exist", stale styles, cron that does not run, a slow page, a page that is not cached.
- Cache layers: built-in FPC vs Varnish vs LiteMage, Redis/Valkey for cache and sessions, what invalidates what.
- Running the project in Warden, DDEV, docker-magento or a hand-written Docker Compose stack; Xdebug.
- Version upgrades (2.4.x → 2.4.y), security patch releases (`-pN`), Quality Patches Tool, Composer patches.

## When not to

- Writing the module, schema, API or theme code itself → `magento:module`, `magento:data`, `magento:api`, `magento:frontend-luma`, `magento:frontend-hyva`.
- Coding-standard checks, tests, review → `magento:quality`.
- Adobe Commerce on cloud infrastructure (`ece-tools`, `.magento.env.yaml`, Fastly) — out of scope; this skill is on-premises Open Source.

## Decision guide

### After a change, what to run

| You changed | Developer mode | Production mode (inside `maintenance:enable` … `maintenance:disable`) |
|---|---|---|
| New module, `etc/module.xml`, module enabled/disabled | `module:enable Acme_Catalog` then `setup:upgrade` | same, then `setup:di:compile`, `setup:static-content:deploy -f <locales>` if it ships `view/*/web` files, `cache:flush` |
| `etc/db_schema.xml` (add, change or drop anything) | `setup:db-declaration:generate-whitelist --module-name=Acme_Catalog` first (A6, commit the JSON), **then** `setup:upgrade` | the same two commands; run `setup:upgrade --dry-run=1` first and read `var/log/dry-run-installation.log` |
| Data or schema patch added | `setup:upgrade`, then `cache:clean` (caches are cleaned *before* patches run, so a patch that writes config leaves the `config` cache stale) | same |
| `etc/di.xml` (plugin, preference, argument, virtual type) | `cache:clean config compiled_config` — the plugin list lives in `compiled_config`, the rest in `config`. `setup:di:compile` is **not needed** in developer mode; it is only needed in production mode | `setup:di:compile` then `cache:flush` |
| `events.xml`, `crontab.xml`, `routes.xml`, `acl.xml`, `system.xml`, `config.xml`, `extension_attributes.xml`, any other `etc/*.xml` | `cache:clean config` (`webapi.xml`: also `config_webservice`; `schema.graphqls`: `config`) | same, plus `setup:di:compile` if `di.xml` also changed |
| PHP class body | nothing — unless a constructor signature changed and an interceptor/proxy for that class already exists in `generated/code` (generated files are never regenerated once present) or `generated/metadata` exists from an earlier compile: delete the generated file(s), or simply `rm -rf generated/code generated/metadata` | `setup:di:compile` (regenerates interceptors, factories, proxies and the compiled DI) |
| New PHP class, new `XxxFactory`/`\Proxy`/interceptor target | nothing — generated on demand into `generated/code/` | `setup:di:compile` |
| Layout XML, `.phtml`, ViewModel output, CMS blocks | `cache:clean layout block_html full_page` | same |
| LESS, CSS, JS, `web/template/*.html`, `requirejs-config.js`, fonts, images (anything under `view/*/web/`) | nothing — served on demand; to force a LESS recompile delete `pub/static/frontend/<Vendor>/<theme>/<locale>` and `var/view_preprocessed`, or run `grunt exec && grunt less` (Luma) / `npm run build` in `web/tailwind` (Hyvä) | `setup:static-content:deploy -f <locales> --theme <Vendor>/<theme>` then `cache:flush` |
| Product/category attribute, attribute set, price/stock/search settings | `indexer:reindex catalog_product_attribute catalogsearch_fulltext` (or the indexer that owns the data) and `cache:clean` | same, from the deploy or cron — never from request code (P5) |
| `app/etc/config.php` pulled from git (module list, theme, scopes, `system` values) | `setup:upgrade` (it runs `app:config:import`), or `app:config:import` alone when nothing else changed | same |
| `app/etc/env.php` `system` values, cache/session backends, `MAGE_MODE` | `cache:clean config` (`MAGE_MODE`: `deploy:mode:set developer`) | `deploy:mode:set production` — it recompiles and redeploys everything, run it deliberately |
| Composer packages (`composer require`/`update`) | `composer install`, `setup:upgrade`, `cache:clean` | see the production sequence below |

`setup:upgrade` = declarative schema for all modules → schema patches → data patches → `app:config:import`; it also cleans every cache type and deletes `generated/code` and `generated/metadata` unless `--keep-generated` is passed. `setup:db:status` tells you whether it is needed at all.

When answering "what do I run" for a developer-mode project, state explicitly that neither `setup:di:compile` (interceptors, factories and proxies are generated on demand) nor `setup:static-content:deploy` (static files are materialised on request) is needed in developer mode — both are required only in production mode. Do not list either as a step; mention them only to say they are not needed.

### Where to look when it breaks

| Symptom | Look at / do |
|---|---|
| 500, "There has been an error processing your request … Error log record number: `<id>`" | `var/report/<id>` (nested under `var/report/xx/yy/` when `dir_nesting_level` is set in `pub/errors/local.xml`) and `var/log/exception.log`; developer mode prints the trace instead |
| Completely blank page | PHP fatal before Magento's handler (memory, parse error): PHP-FPM and web-server error logs (`docker compose logs`, `warden env logs php-fpm nginx`, `ddev logs`) |
| `Area code is not set` in a CLI command, cron job or consumer | the code needs `State::emulateAreaCode()` (or `setAreaCode()` once) — `magento:module` `cron-and-cli.md` |
| `Class "Acme\…" does not exist`, `Source class "…" for "…Factory" generation does not exist` | typo in the `type`/`class` string, namespace ≠ path under `app/code/`, module not registered/enabled, or stale `generated/`: `rm -rf generated/code generated/metadata` (developer) / `setup:di:compile` (production) |
| "Too few arguments to … ::__construct()" or a TypeError creating an object after a constructor change | stale interceptor/proxy in `generated/code`, or stale `generated/metadata` — same fix |
| A `di.xml`/plugin change is ignored | `cache:clean config compiled_config`; if `generated/metadata/global.php` exists the compiled DI wins regardless of `MAGE_MODE` — delete it or recompile |
| Styles/JS do not update | delete `pub/static/<area>/<Vendor>/<theme>/<locale>` and `var/view_preprocessed`; `pub/static/deployed_version.txt` + `dev/static/sign` bust browser caches; production needs a new `setup:static-content:deploy` |
| Cron does not run / emails, indexing, sitemaps stall | `cron_schedule` table (`status` `pending|running|success|missed|error`, `messages`), `crontab -l` for the `#~ MAGENTO START` block, `var/log/cron.log`, `var/log/magento.cron.log`; run `cron:run` twice by hand (first run only schedules) |
| "Reindex required", stale prices/stock/search | `indexer:status`; `indexer:reset <name>` then `indexer:reindex <name>`; in `schedule` mode the `index` cron group and the `<indexer>_cl` changelog tables must be alive |
| Slow page | built-in profiler (`MAGE_PROFILER=html` server variable, or `dev:profiler:enable html` → `var/profiler.flag`), `dev:query-log:enable` → `var/debug/db.log`, `var/log/debug.log` (`dev/debug/debug_logging` in `env.php`), MySQL slow log, FPC header `X-Magento-Cache-Debug: HIT|MISS` (built-in FPC adds it in developer mode only; Varnish always) |
| Page never cached | a `cacheable="false"` block somewhere in the merged layout (P3), a controller setting `Cache-Control: no-cache`, POST/non-GET, or maintenance mode; inspect `X-Magento-Tags` and `X-Magento-Cache-Debug` |
| 404 on a new route/controller/admin page | `cache:clean config`, then check `routes.xml` `frontName`, `module:status Acme_Catalog`, ACL resource of the admin controller |
| Unexpected 503 maintenance page | `var/.maintenance.flag`; `maintenance:status`; `var/.maintenance.ip` for exempt IPs |

## Rules that bite

1. `cache:clean [types]` removes only entries tagged by the listed Magento cache types; `cache:flush [types]` clears the storage behind them — on 2.4.4–2.4.8 that is Redis `FLUSHDB`, which also erases anything another application keeps in that database; on 2.4.9 (Symfony Cache) it deletes only the keys under the store's `id_prefix`. Default to `clean`; reach for `flush` when `clean` did not help or the storage is dedicated.
2. **A6** — Every `db_schema.xml` change is followed by `setup:db-declaration:generate-whitelist --module-name=…` *before* `setup:upgrade`, and the regenerated `db_schema_whitelist.json` is committed. Without the whitelist entry, drops are silently skipped and changed indexes/FKs fail on the duplicate name.
3. In production `setup:upgrade` runs between `maintenance:enable` and `maintenance:disable`. Add `--keep-generated` only when `generated/` was compiled from the code you are deploying (build server, or you compiled first) — otherwise it keeps stale interceptors and the site breaks. Without the flag it deletes `generated/` and reminds you to run `setup:di:compile`.
4. `deploy:mode:set production` wipes `var/cache`, `generated/code`, `generated/metadata`, `var/view_preprocessed` and `pub/static`, then compiles and deploys static content for the store-view locales plus the admin users' interface locales — all of it inside maintenance mode, which the command enables and disables itself; `-s` only writes `MAGE_MODE`. Run it deliberately. `deploy:mode:set developer` clears the same directories before writing the mode (the docs additionally tell you to `rm -rf generated/metadata/* generated/code/*` first).
5. **L5** — `setup:static-content:deploy` refuses to run outside production mode without `-f`; pass the locales you serve and `--theme Acme/default`. With no arguments it builds every registered theme for the locales in use (store-view locales for `frontend`; `en_US` plus each admin user's interface locale for `adminhtml`) — which includes `Magento/luma` and `Magento/blank` unless you `--exclude-theme` them. `pub/static`, `var/view_preprocessed` and `generated/` are build output — never committed.
6. `generated/` is disposable, and `generated/metadata/global.php` alone switches the object manager to compiled mode whatever `MAGE_MODE` says. `setup:di:compile` deletes `var/cache` and `generated/metadata` before it writes; it never touches Redis.
7. `app/etc/config.php` is committed (module list, `scopes`, `themes`, shared `system` values); `app/etc/env.php` is not (DB, crypt key, `MAGE_MODE`, cache/session backends, `system` overrides). `config:set --lock-env path value` writes an environment-specific value to `env.php`, `--lock-config` to `config.php`; locked fields are read-only in the admin. `CONFIG__DEFAULT__<SECTION>__<GROUP>__<FIELD>` environment variables override both.
8. **P5** — `indexer:set-mode schedule` for every indexer in production and keep the `index` cron group running; reindex from the deploy or cron, never from request code. Customer Grid supports `schedule` only from 2.4.8 — on 2.4.4–2.4.7 it is `realtime`. Before switching modes, enable maintenance and stop cron (triggers are created/dropped).
9. `var/log/*.log`, `var/report/`, `var/debug/db.log` and `var/log/profiler.csv` grow without limit — logrotate them; `debug.log` is off in production unless `dev/debug/debug_logging` is `1` in `env.php`; run `dev:query-log:disable` and `dev:profiler:disable` when you are done.
10. Compile and static deploy need memory: Adobe recommends `memory_limit` 1G for those, 2G for debugging; `php -d memory_limit=-1 bin/magento setup:di:compile` when the CLI `php.ini` (not the FPM one) is too tight. Long-running commands run in `nohup`/`screen` or a job runner, never a browser.
11. **A7** — Third-party and core files are changed only through `cweagans/composer-patches`: `extra.patches` in `composer.json` maps `vendor/package` → `{ "description": "patches/composer/<file>.patch" }`, the `.patch` is committed, `"composer-exit-on-patch-failure": true` is set, and `composer install` applies it. Adobe-published fixes go through `magento/quality-patches` (`vendor/bin/magento-patches status|apply|revert`), which also logs to `var/log/patch.log`.
12. Version upgrades (any 2.4.4–2.4.9 target; Composer 2 throughout): `composer require magento/composer-root-update-plugin ~2.0 --no-update && composer update`, then `composer require-commerce magento/product-community-edition 2.4.9 --no-update && composer update` (same syntax for `2.4.9-p1` security releases), then the production sequence below. Plain `composer require magento/product-community-edition=2.4.9 --no-update` still resolves, but does not reconcile the root `composer.json` — `require-commerce` does.

## Minimal correct example

Developer mode, after pulling code that added a module, changed `db_schema.xml`, added a data patch and edited `di.xml`:

```bash
$MAGE composer install                                                          # composer.lock is the source of truth
$MAGE bin/magento module:enable Acme_Catalog                                    # only for a module not yet in app/etc/config.php
$MAGE bin/magento setup:db-declaration:generate-whitelist --module-name=Acme_Catalog   # A6: before setup:upgrade, commit the JSON
$MAGE bin/magento setup:upgrade                                                 # schema → patches → app:config:import; cleans caches, deletes generated/
$MAGE bin/magento cache:clean                                                   # patches ran after the clean; also covers di.xml (config + compiled_config)
$MAGE bin/magento indexer:reindex catalog_product_attribute catalogsearch_fulltext   # only when the change touched attributes or search
```

`setup:di:compile` is not needed in developer mode (interceptors, factories and proxies are generated on demand) and `setup:static-content:deploy` is not needed in developer mode (static files are materialised on request) — both are required only in production mode.

Production, single machine, `en_US` only, Redis dedicated to this store (the build-server variant runs the first three `bin/magento` lines on the build host and ships `generated/` and `pub/static` with the release):

```bash
$MAGE bin/magento maintenance:enable
$MAGE composer install --no-dev --prefer-dist --no-interaction
$MAGE bin/magento setup:di:compile                                              # compiled DI + interceptors from the new code
$MAGE bin/magento setup:static-content:deploy -f en_US --theme Acme/default --theme Magento/backend
$MAGE bin/magento setup:upgrade --keep-generated                                # DB moves last; keeps what was just compiled
$MAGE bin/magento cache:flush                                                   # cache:clean if the Redis DB is shared
$MAGE bin/magento maintenance:disable
```

Why this shape: `composer install` (never `update`) reproduces the tested lock file; compiling and deploying before `setup:upgrade` makes the database the last thing to move, which is what `--keep-generated` assumes — the only wrong combination is `--keep-generated` with a `generated/` older than the code (Adobe's single-machine order `setup:upgrade` → compile → deploy → `cache:clean`, without the flag, is also correct). Stop cron and queue consumers first (`cron:remove`; `cron:run --group=consumers` drains queues).

## Routing table

| For | Read |
|---|---|
| Every command and its options: `setup:*`, `module:*`, `cache:*` and the cache type list, `indexer:*`, `deploy:mode:*`, `config:*`, `app:config:*`, `maintenance:*`, `cron:*`, `admin:user:*`, `dev:*`, `catalog:images:resize`, `info:*`, `queue:consumers:*` | `references/bin-magento.md` |
| Cache types and what invalidates them, built-in FPC vs Varnish vs LiteMage, VCL export, `X-Magento-*` headers, ESI/`ttl`, private content, `getIdentities()`, Redis/Valkey for cache, page cache and sessions (2.4.9 changed the backend names), L2 cache, CDN, warming | `references/caching.md` |
| Log files and levels, `var/report`, enabling `debug.log` in production, template hints, Xdebug 3 in Warden/DDEV/docker-magento, query log, profiler, n98-magerun2, reading a trace through `\Interceptor` frames, common exceptions and causes | `references/debugging.md` |
| Minor/patch upgrades with `require-commerce`, pre-checks, release types (`-pN`, isolated patches, hotfixes), Quality Patches Tool, `cweagans/composer-patches`, verifying patches, rollback, extension compatibility | `references/upgrades-and-patches.md` |
| Detecting Warden, DDEV, docker-magento, plain Docker Compose or native; the exact `bin/magento` prefix per environment; shells, DB access, logs, Xdebug toggles, where Composer runs | `references/dev-envs.md` |
