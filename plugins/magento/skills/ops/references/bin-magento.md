# `bin/magento` command reference

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (A6 schema, L5 build output, P5 indexers).

Options and defaults below are from `bin/magento <command> --help` on 2.4.9 and the Experience League CLI pages; where a release differs it is said. Run everything as the file-system owner, from the Magento root, behind the environment prefix (`references/dev-envs.md`). `bin/magento list` prints every command the enabled modules register (`--raw` for a plain list); `--help` on any command is authoritative for the release you are on. Every command accepts `-n` (no interaction), `-q`, `-v|-vv|-vvv` and `--magento-init-params='MAGE_MODE=developer&MAGE_DIRS[cache][path]=/tmp/cache'` to override bootstrap parameters for that one run.

## Setup

| Command | Notes |
|---|---|
| `setup:install [options]` | First-time install. Essentials: `--db-host --db-name --db-user --db-password`, `--backend-frontname=admin_x` (generated if omitted), `--admin-user --admin-password --admin-email --admin-firstname --admin-lastname`, `--search-engine=opensearch --opensearch-host --opensearch-port` (2.4.6+; on 2.4.4–2.4.5 OpenSearch is configured as `--search-engine=elasticsearch7` with the `--elasticsearch-*` options; 2.4.9 accepts only `elasticsearch8` and `opensearch`), `--cleanup-database`, `--use-sample-data`. `--base-url`, `--language`, `--currency`, `--timezone`, `--use-rewrites`, `--use-secure*` are accepted but marked deprecated on 2.4.9 in favour of `config:set` (`web/unsecure/base_url`, `general/locale/code`, `currency/options/*`, `general/locale/timezone`, `web/seo/use_rewrites`). Cache/session/queue/lock backends take the same `--cache-backend*`, `--page-cache*`, `--session-save*`, `--amqp-*`, `--lock-provider` options as `setup:config:set`. |
| `setup:config:set [options]` | Rewrites `app/etc/env.php` sections from the same option set as `setup:install` (DB, backend frontname, `--cache-backend=redis|valkey`, `--page-cache=redis|valkey`, `--session-save=redis|valkey`, `--http-cache-hosts=host:port,…` for Varnish purging, `--enable-debug-logging=1`, `--enable-syslog-logging`, `--document-root-is-pub=true`). `-s` skips DB validation. |
| `setup:upgrade [--keep-generated] [--dry-run=1] [--safe-mode=1] [--data-restore=1] [--convert-old-scripts=1]` | Declarative schema for every module → schema patches → data patches → `app:config:import`; refreshes the module list in `config.php`; cleans all caches; deletes `generated/code` and `generated/metadata` unless `--keep-generated` (the help says: "We discourage using this option except when deploying to production"). In production mode without the flag it prints "Please re-run Magento compile command". `--dry-run=1` writes the DDL to `var/log/dry-run-installation.log` and touches nothing; `--safe-mode=1` dumps dropped tables/columns to `var/declarative_dumps_csv/`; `--data-restore=1` reads them back. |
| `setup:db-declaration:generate-whitelist [--module-name=Acme_Catalog]` | Regenerates `etc/db_schema_whitelist.json`; default `--module-name=all`. Always before `setup:upgrade` after a `db_schema.xml` change (A6). |
| `setup:db-declaration:generate-patch <module> <patch>` | Scaffolds a patch class from the two required arguments (`Acme_Catalog AddBrandAttribute`); `--revertable=true`, `--type=data|schema` (default `data`). |
| `setup:db:status` | "All modules are up to date." or the modules needing `setup:upgrade`; exit code `2` when an upgrade is pending (`1` when not installed) — use it in deploy scripts. |
| `setup:db-schema:upgrade`, `setup:db-data:upgrade` | The two halves of `setup:upgrade` for scripted deploys. |
| `setup:di:compile` | Single-tenant compiler: deletes `var/cache` and `generated/metadata`, then generates factories/proxies/interceptors into `generated/code` and the per-area DI into `generated/metadata/*.php`. Needs `memory_limit` ≥ 1G (2G recommended); takes minutes. Required in production after any PHP or `di.xml` change; not needed in developer mode. |
| `setup:static-content:deploy [-f] [<languages>...] [-t\|--theme <Vendor/theme>]... [--exclude-theme ...] [-a\|--area frontend\|adminhtml] [-l\|--language xx_XX] [-j\|--jobs N] [-s\|--strategy quick\|standard\|compact] [--no-parent] [--symlink-locale] [--content-version=...] [--refresh-content-version-only] [--no-javascript --no-js-bundle --no-css --no-less --no-images --no-fonts --no-html --no-misc --no-html-minify] [--max-execution-time=900]` | Writes `pub/static/<area>/<Vendor>/<theme>/<locale>/` and `var/view_preprocessed/`. Without `-f` it aborts outside production mode ("Manual static content deployment is not required in default and developer modes"). No language argument = the locales in use (store views for frontend; `en_US` + admin users' interface locales for adminhtml). `-j 4` parallelises; `--no-parent` (2.4.2+) skips parent themes; `--refresh-content-version-only` bumps `pub/static/deployed_version.txt` so browsers and CDNs refetch without a full deploy. |
| `setup:backup [--code] [--media] [--db]`, `setup:rollback -c\|-m\|-d <file>` | Writes `var/backups/<timestamp>_*`; deprecated since 2.3.0 and documented as able to fail silently on rollback — use `mysqldump`/XtraBackup and the file system instead. |
| `setup:uninstall`, `setup:performance:generate-fixtures` | Wipe the install (interactive confirm) / generate performance-test data. |

## Modules

| Command | Notes |
|---|---|
| `module:status [--enabled] [--disabled] [<name>...]` | Lists enabled and disabled modules from `config.php`. |
| `module:enable [-f] [--all] [-c\|--clear-static-content] <name>...`, `module:disable …` | Writes `config.php` `modules`; then `setup:upgrade`. `-c` deletes static files so a module's `view/*/web` files are re-materialised; `-f` bypasses dependency checks (do not). Prints "To make sure that the enabled modules are properly registered, run 'setup:upgrade'." |
| `module:uninstall [-r\|--remove-data] [--backup-code --backup-media --backup-db] [--non-composer] [-c] <name>...` | Composer-installed modules only unless `--non-composer`; `-r` runs `Setup/Uninstall.php` and revertable data patches; also removes the package from `composer.json`. |
| `module:config:status` | Whether `config.php` module list matches the DB `setup_module` state. |

## Cache

| Command | Notes |
|---|---|
| `cache:status` | Cache type → `1`/`0`. |
| `cache:enable [types]`, `cache:disable [types]` | Writes `cache_types` in `env.php`; enabling also cleans the type. Disable `block_html full_page` while developing templates, never in production. |
| `cache:clean [types]` | Removes entries tagged by the given types (all enabled types when omitted). Safe on shared storage. |
| `cache:flush [types]` | Clears the *storage* behind the types. 2.4.4–2.4.8: Redis `FLUSHDB`, including other applications' keys in that database. 2.4.9: Symfony Cache `clear()` deletes only the keys under the store's `id_prefix` (auto-generated when not configured), so other prefixes survive. |

Core cache types on 2.4.4–2.4.9 (`cache_types` in `env.php`; extensions add their own): `config` (merged XML configuration, `di.xml`, `events.xml`, `system.xml`, `acl.xml`, `routes.xml`, `crontab.xml`, env/config overrides), `layout` (merged layout XML), `block_html` (block output), `collections` (collection data), `reflection` (API interface reflection), `db_ddl` (DESCRIBE results), `compiled_config` (plugin lists and interception data in developer mode), `eav` (entity types and attributes), `customer_notification`, `config_integration`, `config_integration_api`, `graphql_query_resolver_result` (2.4.7+), `full_page` (built-in FPC), `config_webservice` (`webapi.xml`, WSDL), `translate` (translation dictionaries).

## Indexers

| Command | Notes |
|---|---|
| `indexer:info` | Indexer code → title. Core 2.4.9: `cataloginventory_stock`, `design_config_grid`, `customer_grid`, `catalog_category_product`, `catalog_product_category`, `catalogrule_rule`, `catalog_product_attribute`, `inventory`, `catalog_product_price`, `catalogrule_product`, `catalogsearch_fulltext`, `salesrule_rule`; `*_data_exporter` indexers (`sales_order_data_exporter`, `store_data_exporter`, …) appear when the `magento/module-*-data-exporter` packages pulled in by Payment Services and other SaaS connectors are installed. |
| `indexer:status [name...]` | Status (`Ready`, `Reindex required`, `Processing`), mode, schedule backlog per indexer. |
| `indexer:reindex [name...]` | Full reindex; all indexers when omitted. `MAGE_INDEXER_THREADS_COUNT=3 php bin/magento indexer:reindex catalogsearch_fulltext` parallelises by dimension where supported; `indexer:set-dimensions-mode catalog_product_price website` enables per-website price indexing. |
| `indexer:set-mode realtime\|schedule [name...]`, `indexer:show-mode [name...]` | `schedule` adds the mview triggers and `<indexer>_cl` changelog tables, `realtime` drops them (P5). Enable maintenance mode and stop cron while switching. Customer Grid supports `schedule` only from 2.4.8. |
| `indexer:reset [name...]` | Marks the indexer invalid so the next `indexer:reindex` (or the `indexer_reindex_all_invalid` cron job) rebuilds it. |
| `indexer:set-status invalid\|suspended\|valid [name...]` | 2.4.7+. `suspended` pauses cron-driven updates during imports. |

## Deploy modes

| Command | Notes |
|---|---|
| `deploy:mode:show` | "Current application mode: developer. (Note: Environment variables may override this value.)" — `MAGE_MODE` in `$_SERVER` beats `env.php`. |
| `deploy:mode:set developer\|production [-s\|--skip-compilation]` | Production: inside maintenance mode (enabled/disabled by the command itself) clears `var/cache`, `generated/code`, `generated/metadata`, `var/view_preprocessed`, `pub/static`, writes `MAGE_MODE`, runs `setup:di:compile` and `setup:static-content:deploy -f <store-view locales + admin interface locales>`; `-s` only writes the mode. Developer: clears the same directories, then writes the mode (the docs additionally say `rm -rf generated/metadata/* generated/code/*` first). `default` mode exists but is not something you set on purpose. |

## Configuration

| Command | Notes |
|---|---|
| `config:show [path] [--scope=default\|websites\|stores --scope-code=<code>]` | Saved values; encrypted values print as asterisks. |
| `config:set [--scope --scope-code] [-e\|--lock-env] [-c\|--lock-config] <path> <value>` | Without a lock: writes `core_config_data`, editable in the admin. `--lock-env`: `env.php` `system` array (environment-specific, read-only in admin). `--lock-config`: `config.php` (shared, committed). `--lock` alone is deprecated. |
| `config:sensitive:set [-i] [--scope --scope-code] <path> [<value>]` | Sensitive paths (declared via `Magento\Config\Model\Config\TypePool` in `di.xml`) — written to `env.php`; `-i` walks through all of them. |
| `app:config:dump [scopes system themes i18n]` | Writes admin settings to `config.php` (shared) and `env.php` (sensitive/system-specific); the dumped fields become read-only in the admin. Run on the environment you edited in; commit `config.php`. |
| `app:config:import [-n]` | Imports `scopes` (websites/groups/stores) and `themes` from `config.php` into the DB; `system` values are read directly and are not imported. Run by `setup:upgrade`. |
| `app:config:status` | Whether `app:config:import` is needed. |

Precedence when the same path is set in several places: environment variables (`CONFIG__DEFAULT__<SECTION>__<GROUP>__<FIELD>`, `CONFIG__WEBSITES__<CODE>__…`, `CONFIG__STORES__<CODE>__…`) → `env.php` → `config.php` → database.

## Maintenance mode

`maintenance:enable [--ip=1.2.3.4 --ip=…]`, `maintenance:disable`, `maintenance:status`, `maintenance:allow-ips <ip>... [--none] [--add]`. On: `var/.maintenance.flag`; exempt IPs: `var/.maintenance.ip`; visitors get the `pub/errors/503.php` page. `--ip=none` clears the list. Enable it around production `setup:upgrade`, mode switches and indexer mode switches.

## Cron

`cron:install [-f\|--force] [-d\|--non-optional]` writes the `#~ MAGENTO START … #~ MAGENTO END` block into the file-system owner's crontab (`* * * * * php bin/magento cron:run 2>&1 | grep -v "Ran jobs by schedule" >> var/log/magento.cron.log`); `cron:remove` deletes the block; `cron:run [--group=<id>] [--exclude-group=<id>]` schedules pending rows then runs those that are due — run it twice by hand to see a job execute. `cron_schedule` and `var/log/cron.log` are the audit trail. Job authoring is in `magento:module` `cron-and-cli.md`.

## Admin users

`admin:user:create --admin-user=… --admin-password=… --admin-email=… --admin-firstname=… --admin-lastname=…` (all five required; password rules apply); `admin:user:unlock <username>` after too many failed logins. Admin URL: `info:adminuri`. Two-factor auth cannot be bypassed from the CLI in 2.4.x — for local development disable the module (`module:disable Magento_TwoFactorAuth Magento_AdminAdobeImsTwoFactorAuth`, then `setup:upgrade`).

## Developer commands (`Magento_Developer`; hidden when the module is disabled)

| Command | Notes |
|---|---|
| `dev:template-hints:enable\|disable\|status` | Sets `dev/debug/template_hints_storefront` in `core_config_data`; then `cache:clean config full_page`. Admin hints, "show with parameter" and the parameter value (`dev/debug/template_hints_admin`, `…_storefront_show_with_parameter`, `…_parameter_value`) are admin-only settings — the whole *Advanced > Developer* section is hidden in production mode. |
| `dev:query-log:enable [--include-all-queries=true] [--query-time-threshold=0.001] [--include-call-stack=true] [--include-index-check=false]`, `dev:query-log:disable` | Writes the `db_logger` block into `env.php`; SQL goes to `var/debug/db.log`. |
| `dev:profiler:enable [html\|csvfile]`, `dev:profiler:disable` | Writes `var/profiler.flag`; `csvfile` outputs to `var/log/profiler.csv`. Same effect as the `MAGE_PROFILER` server variable. |
| `dev:di:info <class> [<area>]` | Preference, constructor arguments (with configured values) and plugins for a class in an area — the fastest way to see which plugins wrap a method and in what order. |
| `dev:urn-catalog:generate <path> [--ide=phpstorm\|vscode]` | XSD catalog for XML autocompletion: `.idea/misc.xml` for PhpStorm. |
| `dev:source-theme:deploy [--type=less] [--locale=en_US] [--area=frontend] [--theme=Vendor/theme] [css/styles-m css/styles-l]` | Publishes LESS sources to `pub/static` for Grunt/client-side compilation. |
| `dev:xml:convert`, `dev:tests:run`, `dev:email:*-compatibility-check` | Rarely needed. |

## Catalog and info

`catalog:images:resize [-a\|--async] [--skip_hidden_images]` regenerates every product image cache (slow; `-a` queues the work on the `media.storage.catalog.image.resize` topic for the consumer of the same name). `catalog:product:attributes:cleanup` removes orphaned attribute values.

`info:adminuri`, `info:currency:list`, `info:language:list`, `info:timezone:list`, `info:backups:list`, `info:dependencies:show-modules [-o file]`, `info:dependencies:show-framework`, `info:dependencies:show-modules-circular` (CSV reports; the circular one is the A8 check). `store:list`, `store:website:list`.

## Queues, encryption, i18n

`queue:consumers:list`; `queue:consumers:start <consumer> [--max-messages=N] [--batch-size=N] [--single-thread] [--multi-process=N] [--area-code=…]` — consumers normally start from the `consumers` cron group; `cron:run --group=consumers` drains queues before an upgrade. `encryption:key:change [-k]` rotates the crypt key in `env.php` and re-encrypts stored values. `i18n:collect-phrases [-m] [-o file]`, `i18n:pack <source.csv> <locale> [-m replace|merge]`, `i18n:uninstall`.

## Sources

- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/config-cli — Command-line configuration overview (file-system owner, `bin/magento list`, PATH)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/manage-cache — Manage the cache (`cache:status|enable|disable|clean|flush`, clean vs flush on shared storage, cache type list)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/manage-indexers — Manage the indexers (`indexer:info|status|reindex|reset|set-mode|show-mode|set-status|set-dimensions-mode`, `MAGE_INDEXER_THREADS_COUNT`, Customer Grid 2.4.8 change, triggers on `schedule`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/set-mode — Set the operation mode (`deploy:mode:show|set`, directories cleared, `-s`, developer switch clean-up)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/setup/application-modes — Application modes (default/developer/production/maintenance behaviour)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/static-view/static-view-file-deployment — Deploy static view files (every option, `-f` outside production, locale defaults, examples)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/static-view/static-view-file-strategy — Static file deployment strategies (quick/standard/compact)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/code-compiler — Code compiler (`setup:di:compile`, what it generates)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/configure-cron-jobs — Configure and run cron jobs (`cron:install|remove|run`, crontab block, run twice, `cron.log`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/configuration-management/set-configuration-values — Set configuration values (`config:set|sensitive:set|show`, `--lock-env`/`--lock-config`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/configuration-management/export-configuration — Export the configuration (`app:config:dump`, `config.php` vs `env.php`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/configuration-management/import-configuration — Import the configuration (`app:config:import`, what is imported)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/deployment/technical-details — Pipeline deployment technical details (override precedence: env vars → `env.php` → `config.php` → DB; build vs production steps; `--keep-generated`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/deployment/examples/example-environment-variables — Environment variable format `CONFIG__DEFAULT__…`
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/tutorials/maintenance-mode — Enable or disable maintenance mode (`.maintenance.flag`, `.maintenance.ip`, `--ip`, `allow-ips`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/tutorials/backup — Back up and roll back (`setup:backup|rollback`, deprecation notice)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/tutorials/manage-modules — Enable or disable modules (`module:enable|disable|status`, `--clear-static-content`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/tutorials/uninstall-modules — Uninstall modules (`module:uninstall` options)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/tutorials/extensions — Install an extension (`composer require`, `module:enable --clear-static-content`, `setup:upgrade`, `setup:di:compile`, `cache:clean`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/prerequisites/php-settings — Required PHP settings (`memory_limit` 1G compile/deploy, 2G debugging; `realpath_cache`, `opcache.save_comments`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/upgrade-guide/prepare/prerequisites — Upgrade prerequisites (`config:show catalog/search/engine` values per release: `elasticsearch7` before 2.4.6, `opensearch` from 2.4.6)
