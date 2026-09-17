# Debugging: logs, reports, Xdebug, profiling, reading traces

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (A1 DI, A2 plugins, S4 no secrets in logs).

Paths are relative to the Magento root; prefix `bin/magento` with the environment prefix from `references/dev-envs.md`, and remember that inside a container the log files live in the container's `var/` (a bind mount in Warden/DDEV/Compose, a synced volume in docker-magento — `bin/copyfromcontainer var/log` there).

## Where things are written

| File | What lands there | Notes |
|---|---|---|
| `var/log/system.log` | every `LoggerInterface` call at `info` and above (`info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency`) that has no exception in its context | Monolog `Magento\Framework\Logger\Handler\System`, level `INFO` |
| `var/log/exception.log` | records whose context contains an exception — logging a `\Throwable` as the message (`$logger->error($e)`) or passing `['exception' => $e]`; uncaught exceptions in production/default mode with the `report_id` | `Handler\Exception`, level `INFO`; the `System` handler forwards to it |
| `var/log/debug.log` | `$logger->debug()` calls — including every SQL statement when `dev:query-log` is *not* used but a module logs at debug — noisy | `Magento_Developer`'s `Handler\Debug`; **written only when `dev/debug/debug_logging` is `1` in `env.php`, or the key is absent and the mode is not production**. Enable in production: `bin/magento setup:config:set --enable-debug-logging=1` (writes `'dev' => ['debug' => ['debug_logging' => 1]]`); disable again afterwards |
| `var/log/cron.log`, `var/log/magento.cron.log` | the cron runner's own logger (`Magento_Cron` `di.xml` handler) / stdout+stderr of the crontab line written by `cron:install` | `cron:run` prints "Ran jobs by schedule" per run |
| `var/log/dry-run-installation.log` | DDL from `setup:upgrade --dry-run=1` | |
| `var/log/patch.log` | Quality Patches Tool operations | |
| `var/log/profiler.csv` | `dev:profiler:enable csvfile` output | |
| `var/debug/db.log` | SQL from `dev:query-log:enable` | |
| `var/report/<id>` (or `var/report/xx/yy/<id>` with `dir_nesting_level` in `pub/errors/local.xml`) | serialised exception report for a request that failed outside developer mode; the storefront shows "Error log record number: `<id>`" | `pub/errors/processor.php`; `MAGE_ERROR_REPORT_DIR_NESTING_LEVEL` overrides the nesting; `pub/errors/local.xml.sample` can email reports instead |
| `var/log/litemage.log`, other `var/log/<module>.log` | extension loggers with their own handlers (`Magento\Framework\Logger\Handler\Base` with a `fileName` argument in `di.xml`) | |
| PHP-FPM error log, web-server error log | fatals before Magento's handler runs: memory exhaustion, parse errors, missing extensions, `Allowed memory size`, `Maximum execution time` | `docker compose logs php-fpm`, `warden env logs php-fpm nginx`, `ddev logs`, `/var/log/php*-fpm.log`, `journalctl -u php8.x-fpm` |

`setup:config:set --enable-syslog-logging=1` (`dev/syslog/syslog_logging`) sends everything to syslog (`LOG_USER`) as well. Log through the injected `Psr\Log\LoggerInterface` (A1), never `error_log()`/`file_put_contents`; never log tokens, passwords or card data (S4). Log files are not rotated by Magento — logrotate them.

Modes change who sees what (`deploy:mode:show`): **developer** prints uncaught exceptions with the trace in the browser (`MAGE_DEBUG_SHOW_ARGS=1` in the server environment adds method arguments to traces), sends `X-Magento-*` debug headers, and writes verbose reports; **default** and **production** log to `var/report` + `exception.log` and show the generic error page. `MAGE_MODE` as a server variable (`fastcgi_param MAGE_MODE developer`, `SetEnv MAGE_MODE developer`) beats `env.php`.

## Template hints

`bin/magento dev:template-hints:enable` sets `dev/debug/template_hints_storefront` = 1 in the DB; follow with `bin/magento cache:clean config full_page` (and `block_html`), reload, and every block is outlined with its template path and — with *Add Block Class Type to Hints* (`dev/debug/template_hints_blocks`) — the block class. *Enable Hints for Storefront with URL Parameter* + *Parameter Value* (`dev/debug/template_hints_storefront_show_with_parameter`, `dev/debug/template_hints_parameter_value`) restrict hints to requests carrying `?templatehints=<value>` so they can be left on in staging; `dev/debug/template_hints_admin` covers the admin. All of these live under *Stores > Configuration > Advanced > Developer*, a section hidden in production mode — set them from the CLI (`config:set`) or the developer-mode admin. `dev:template-hints:disable` and `dev:template-hints:status` complete the set. Hints work on Hyvä pages too (the hint decorator wraps the template engine, not the theme).

## Xdebug 3

Settings (php.ini / `99-xdebug.ini`): `xdebug.mode=debug` (add `,develop` for better `var_dump`, `,profile` for cachegrind files), `xdebug.client_host=<IDE host>` (`host.docker.internal` from a container on macOS/Windows; the host's bridge IP on Linux), `xdebug.client_port=9003` (the Xdebug 3 default; 9000 was Xdebug 2), `xdebug.start_with_request=trigger` (default — start only when a trigger is present) or `yes` (every request), `xdebug.idekey=PHPSTORM` (only matters for `xdebug.trigger_value`), `xdebug.discover_client_host=1` when the IDE shares the subnet. Triggers: the `XDEBUG_SESSION` cookie (set by the *Xdebug Helper* browser extension, or `XDEBUG_SESSION_START=<key>` once in the URL), or `XDEBUG_SESSION=1` in the environment for CLI runs (`XDEBUG_SESSION=1 php bin/magento indexer:reindex`). `XDEBUG_CONFIG="client_host=… idekey=…"` overrides settings per process. The IDE maps the container path `/var/www/html` (Warden, DDEV, docker-magento) to the project root.

Per environment:

- **Warden** — two FPM containers: `php-fpm` (no Xdebug) and `php-debug` (Xdebug installed); nginx routes to `php-debug` when the `XDEBUG_SESSION` cookie is set. `PHP_XDEBUG_3=1` in `.env` selects Xdebug 3 (port 9003). CLI: `warden debug` opens a shell in `php-debug`, so `warden debug` → `bin/magento …` steps into commands. PhpStorm server name is `<WARDEN_ENV_NAME>-docker`, path mapping `/var/www/html`.
- **DDEV** — `ddev xdebug on|off|toggle|status`; Xdebug is off by default for speed. IDE listens on 9003 (`.ddev/php/xdebug_client_port.ini` to change it). CLI debugging works after `ddev xdebug on` with `ddev exec bin/magento …` or inside `ddev ssh`; `ddev logs` shows "Could not connect to debugging client" when the firewall blocks 9003.
- **docker-magento** — a dedicated `phpfpm-xdebug` container is selected by the `XDEBUG_SESSION` cookie (nginx routing set up by `bin/setup-nginx`); `bin/debug-cli bin/magento indexer:reindex` runs a CLI command inside it; `bin/xdebug` is deprecated; `bin/configure-linux` opens port 9003 on Linux hosts.
- **Native / plain Compose** — install `xdebug` in the PHP image, mount the ini, set `client_host=host.docker.internal` (`extra_hosts: ["host.docker.internal:host-gateway"]` on Linux).

Breakpoints in a plugin class or in a class that is wrapped by an interceptor sit in `generated/code/...`-adjacent frames — set them in your own class file; PhpStorm resolves them. When a breakpoint never triggers, check the trace: the method may run inside a `___callPlugins` chain or in a cron/consumer process that was not started with the trigger.

## Query log and profiler

```bash
bin/magento dev:query-log:enable --include-all-queries=true --query-time-threshold=0.001 --include-call-stack=true   # writes the db_logger block to env.php
bin/magento dev:query-log:disable
bin/magento dev:profiler:enable html      # var/profiler.flag; also `csvfile` → var/log/profiler.csv
bin/magento dev:profiler:disable
```

The query log goes to `var/debug/db.log` with timing and, with `--include-call-stack`, the PHP trace of every statement — it grows fast; `--include-index-check=true` runs `EXPLAIN` on each query. The profiler renders a timing tree at the bottom of every HTML page (or the CSV) while `var/profiler.flag` exists **or** the request carries a `MAGE_PROFILER` server variable (`fastcgi_param MAGE_PROFILER html;`, `SetEnv MAGE_PROFILER html`, or a JSON driver config); it only activates for requests whose `Accept` contains `text/html`. Both are developer tools — never leave them on in production. For real profiling use Blackfire, Tideways or SPX (Warden and docker-magento ship SPX/Blackfire toggles), and MySQL's slow query log for the database side.

## n98-magerun2

Install `n98-magerun2.phar` (`files.magerun.net`) or `composer require n98/magerun2-dist`; run it from the Magento root behind the same prefix as `bin/magento`. Highlights: `dev:console` (interactive PHP with the object manager bootstrapped — the fastest way to poke at a repository or config value), `sys:cron:list` / `sys:cron:run <job_code>` / `sys:cron:history`, `db:query "SELECT …"` / `db:console` / `db:dump --strip="@development"` (sensitive tables stripped), `sys:info`, `sys:check`, `sys:maintenance`, `sys:url:list`, `dev:module:list`, `dev:theme:list`, `dev:template-hints`, `dev:di:preferences:list`, `cache:list`, `config:store:get|set`, `config:env:set`, `admin:user:change-password`, `customer:create`, `indexer:list`, `generation:flush`. It bootstraps Magento the same way `bin/magento` does, so it needs the same PHP and database access.

## Reading a stack trace through interceptors

Every class with a plugin is instantiated as `<Class>\Interceptor` (generated into `generated/code/<Vendor>/<Module>/…/Interceptor.php`, extending the original and implementing `InterceptorInterface`). A trace through a plugged method therefore reads:

```
#0 …/Plugin/NormalizeProductName.php(24): …                                  ← your plugin (before/around/after)
#1 vendor/magento/framework/Interception/Interceptor.php(138): …->___callPlugins('save', Array, Array)
#2 generated/code/Magento/Catalog/Model/ProductRepository/Interceptor.php(…): …->___callPlugins(...)
#3 vendor/magento/module-catalog/Model/ProductRepository.php(…): …\ProductRepository\Interceptor->save(...)
```

`___callPlugins` walks the plugin list for the method; `___callParent` reaches the original implementation. Frames whose file is under `generated/code` are machine-made: look one frame up for the plugin (`Plugin/`) or one frame down for the real class. `bin/magento dev:di:info 'Magento\Catalog\Api\ProductRepositoryInterface'` lists the preference, constructor arguments and every plugin on the class in sort order — use it before touching an `around` plugin. Factories (`…Factory`) and proxies (`…\Proxy`) are generated the same way; a trace inside `generated/code/.../Proxy.php` means the real object was instantiated lazily at that call.

## Common exceptions and causes

| Message | Cause | Fix |
|---|---|---|
| `Area code is not set` | CLI command, cron job, consumer or unit test touched area-scoped config, layout, design or URLs with no area | `State::emulateAreaCode()` around the code, or `setAreaCode()` once (`magento:module` `cron-and-cli.md`) |
| `Area code is already set` | `setAreaCode()` called twice (framework already set it) | use `emulateAreaCode()`, or wrap in `try/catch LocalizedException` |
| `Class "Acme\Catalog\Model\Foo" does not exist` (`ReflectionException`) | typo in `di.xml`/layout/`webapi.xml` class string; namespace does not match `app/code/<Vendor>/<Module>/` path; module disabled; `registration.php` missing | fix the string/path; `module:status`; `cache:clean config` |
| `Source class "…" for "…Factory" generation does not exist` | a `*Factory` type-hint for a class that is not there | create the class or fix the name; then delete the stale `generated/code/.../Factory.php` |
| `Type Error occurred when creating object: …, Argument #N ($x) must be of type …` / `Too few arguments to function …::__construct()` | `di.xml` argument does not match the constructor, or a stale interceptor/proxy/`generated/metadata` after a constructor change | fix the wiring; `rm -rf generated/code generated/metadata` (developer) / `setup:di:compile` (production) |
| `Circular dependency: …` | two classes inject each other | inject a `\Proxy` for one side (A9), or a factory |
| `Class "Acme\\…\\Plugin\\X" does not exist` when a plugged method runs, or a plugin that silently never fires | `di.xml` plugin `type` wrong; plugin declared on a `final`, `static`, `private`/`protected` method or a constructor — the interceptor generator skips those methods without an error (A2); `sortOrder`/`disabled` on another plugin | fix the target (`dev:di:info <class>` shows what is wired); `cache:clean config compiled_config` |
| `Invalid method …::…` / `Call to undefined method …\Interceptor::…()` | calling a method the subject does not have (plugin on a wrong class or interface) | check the interface; `dev:di:info` |
| `Element 'block', attribute 'x': The attribute 'x' is not allowed` / `Invalid XML in file …` | XML fails XSD validation in developer mode | fix the XML; `dev:urn-catalog:generate` for IDE validation |
| `The store that was requested wasn't found` / `Store code … not found` | `MAGE_RUN_CODE`/`MAGE_RUN_TYPE` in the server config point at a store that does not exist, or `store` table out of sync with `config.php` `scopes` | fix the env vars; `app:config:import` |
| `Front controller reached 100 router match iterations` | a router loops on a rewrite (`url_rewrite` or `routes.xml`) | inspect the `url_rewrite` row for the request path |
| `Notice: Undefined index` / `Warning: … in …\Interceptor` after upgrade | stale `generated/` or third-party module not yet compatible | regenerate; check the extension's release notes |
| `Allowed memory size of … bytes exhausted` | CLI `memory_limit` too low for compile/deploy/import | `php -d memory_limit=2G bin/magento …`; raise the CLI `php.ini` |
| `SQLSTATE[HY000] [2002] … getaddrinfo for db failed` (or `Connection refused`) | running `bin/magento` on the host with `env.php` pointing at the container's DB host | run it behind the environment prefix (`references/dev-envs.md`) |
| `Consumer "…" skipped as required connection "amqp" is not configured` | `queue/amqp` missing in `env.php` | configure RabbitMQ or leave consumers on the DB connection |
| `The default website isn't defined` / blank admin after DB import | `core_config_data` base URLs or `store`/`store_website` rows from another environment | `config:set --lock-env web/unsecure/base_url …`, `app:config:import` |

## Sources

- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/setup/application-modes — Application modes (what developer/default/production show, `var/report` verbosity, `X-Magento-*` headers)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/setup/initialization — Application initialization and bootstrap (default exception handling per mode, `MAGE_RUN_CODE`/`MAGE_RUN_TYPE` in the `$_SERVER` params)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/logs/custom-logging — Custom logging (Monolog handlers, `Magento\Framework\Logger\Handler\Base`, per-module log files via `di.xml`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/set-mode — Set the operation mode (`deploy:mode:show`, environment variables override `env.php`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/manage-cache — Manage the cache (`cache:clean config full_page` after enabling hints)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/prerequisites/php-settings — Required PHP settings (memory limits for compile/deploy/debugging)
- https://experienceleague.adobe.com/en/docs/commerce-operations/upgrade-guide/prepare/prerequisites — Upgrade prerequisites (`config:show catalog/search/engine`)
- https://xdebug.org/docs/step_debug — Xdebug step debugging (`xdebug.mode=debug`, `client_host`/`client_port` 9003, `discover_client_host`, `start_with_request`, `XDEBUG_SESSION` cookie/env var, `XDEBUG_SESSION_START`, `xdebug_break()`)
- https://xdebug.org/docs/all_settings — Xdebug settings reference (`XDEBUG_CONFIG`, `xdebug.idekey`, `xdebug.client_port` default 9003)
- https://docs.warden.dev/configuration/xdebug.html — Warden Xdebug (`php-fpm` vs `php-debug`, cookie routing, ports 9000/9003, `warden debug`, VS Code and PhpStorm mappings, `WARDEN_ENV_NAME-docker`)
- https://docs.ddev.com/en/stable/users/debugging-profiling/step-debugging/ — DDEV step debugging (`ddev xdebug on|off|toggle|status`, port 9003, `.ddev/php/xdebug_client_port.ini`, firewall troubleshooting, path mapping `/var/www/html`)
- https://github.com/markshust/docker-magento/blob/master/README.md — docker-magento README (`phpfpm-xdebug` container, `XDEBUG_SESSION` cookie, `bin/debug-cli`, `bin/xdebug` deprecated, `bin/setup-nginx`, `bin/configure-linux`, `bin/log`, `bin/spx`, `bin/blackfire`, `bin/n98-magerun2`, `bin/devconsole`)
- https://github.com/netz98/n98-magerun2/blob/develop/README.md — n98-magerun2 README (install via phar or `n98/magerun2-dist`, command groups)
- https://netz98.github.io/n98-magerun2/command-docs/development/ — n98-magerun2 dev commands (`dev:console`, `dev:module:list`, `dev:theme:list`, `dev:template-hints`, `dev:di:preferences:list`)
- https://netz98.github.io/n98-magerun2/command-docs/system/ — n98-magerun2 sys commands (`sys:info`, `sys:check`, `sys:cron:list|run|history`, `sys:maintenance`, `sys:url:list`)
- https://netz98.github.io/n98-magerun2/command-docs/db/ — n98-magerun2 db commands (`db:query`, `db:console`, `db:dump`, `db:import`, `db:info`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/tools/quality-patches-tool/usage — Quality Patches Tool usage (`var/log/patch.log`)
