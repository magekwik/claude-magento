# Caching: cache types, full-page cache, Varnish, LiteMage, Redis/Valkey

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (P3 page cacheability, P7 tagged application cache).

Three layers, top to bottom: the HTTP full-page cache (built-in PHP FPC, Varnish or LiteMage — one of them), the application cache types behind `bin/magento cache:*` (file system by default, Redis/Valkey in production), and the browser/CDN cache driven by `Cache-Control` and static-file versioning. Each has its own invalidation path; most "I cleared the cache and nothing changed" tickets are about the wrong layer.

## Application cache types and what invalidates them

| Type | Holds | Invalidated by |
|---|---|---|
| `config` | merged XML of every enabled module (`di.xml`, `events.xml`, `system.xml`, `config.xml`, `acl.xml`, `routes.xml`, `crontab.xml`, `webapi.xml` routes, `schema.graphqls`), `config.php`/`env.php` `system` values and `core_config_data` | `cache:clean config`; admin config saves clean it; `setup:upgrade` |
| `compiled_config` | plugin lists and interception data built at runtime in developer mode (`generated/metadata` replaces it after `setup:di:compile`) | `cache:clean compiled_config`; deleting `generated/` |
| `layout` | merged layout XML per handle set | `cache:clean layout`; saving a CMS page/block or a widget instance |
| `block_html` | rendered output of blocks with a cache key (`cache_lifetime`) | `cache:clean block_html`; entity saves through `getIdentities()` tags |
| `full_page` | built-in FPC pages (`var/page_cache/` or the `page_cache` frontend in `env.php`) | `cache:clean full_page`; entity tags; `cache:flush`; `clean_cache_by_tags` observers |
| `collections` | collection data marked cacheable | `cache:clean collections` |
| `reflection` | API interface reflection (`webapi`, REST/SOAP data interfaces) | `cache:clean reflection` after changing an `Api/Data` interface |
| `db_ddl` | `DESCRIBE`/index metadata | `cache:clean db_ddl` after schema changes (`setup:upgrade` does it) |
| `eav` | entity types and attribute metadata | `cache:clean eav` after `EavSetup` patches |
| `config_webservice` | `webapi.xml` merged config, WSDL | `cache:clean config_webservice` |
| `translate` | translation dictionaries | `cache:clean translate` after `i18n/*.csv` or inline translation changes |
| `customer_notification`, `config_integration`, `config_integration_api`, `graphql_query_resolver_result` (2.4.7+) | as named | `cache:clean <type>` |

Entities implementing `Magento\Framework\DataObject\IdentityInterface::getIdentities()` return tags (`cat_p_42`, `cat_c_7`, `cms_p_3`, `cms_b_5`); saving the entity dispatches `clean_cache_by_tags`, which cleans `block_html` and `full_page` entries carrying those tags and, with Varnish, sends `PURGE` requests with `X-Magento-Tags-Pattern`. A block that renders an entity must return the same tags from its own `getIdentities()` (the core product view block returns `$this->getProduct()->getIdentities()`) — that is how one product save purges every page that showed it. Own caches (P7) go through `CacheInterface::save($data, $id, $tags, $lifetime)` with entity tags so they ride the same invalidation.

`cache:clean [types]` deletes entries tagged with the listed types; `cache:flush [types]` clears the backend storage behind them — on 2.4.4–2.4.8 `FLUSHDB` on Redis/Valkey (everything in that database, other applications included); on 2.4.9 the Symfony frontend's `cleanAll()` calls `clear()`, which deletes only the keys under the store's `id_prefix` (Magento generates one when `env.php` sets none), so a shared database is no longer wiped. Enabling a disabled type cleans it. In production mode cache types can only be enabled/disabled from the CLI (the admin *Cache Management* toggles are hidden); the admin *Flush Magento Cache* button is `cache:clean` for every type.

## Full-page cache

`system/full_page_cache/caching_application`: `1` = built-in, `2` = Varnish (LiteMage registers a third value when LiteSpeed is detected). `system/full_page_cache/ttl` (default `86400`) is the public TTL sent as `Cache-Control: public, max-age=…, s-maxage=…`. FPC applies only to GET/HEAD responses of pages whose merged layout has no `cacheable="false"` block and that were not marked private (`Layout::isCacheable()`; P3) and only while `full_page` is an enabled cache type (`cache:status`, `cache:enable full_page`) — with Varnish, a disabled `full_page` type means no public headers and no caching.

### Built-in (PHP) FPC

`Magento\PageCache\Model\App\FrontController\BuiltinPlugin` looks the page up in the `full_page` type before routing. Blocks whose class sets `$_isScopePrivate = true` (a handful of core blocks — cart, checkout, captcha, admin notifications; the property is documented as obsolete, so do not use it in new code) are replaced by `<!-- BLOCK name -->…<!-- /BLOCK name -->` placeholders and refetched by the `mage.pageCache` widget through `GET /page_cache/block/render?blocks=…&handles=…`, which answers with private headers; new code uses customer-data sections instead. Developer mode adds `X-Magento-Cache-Debug: HIT|MISS` and, on a MISS, `X-Magento-Cache-Control` (the `Cache-Control` value Magento sent) — both only in developer mode; default and production modes send neither. Backend: file system under `var/page_cache/` unless `env.php` defines the `page_cache` frontend (below). Adobe calls it "much slower than Varnish" and recommends Varnish for production.

### Varnish

Supported VCL templates on 2.4.4–2.4.9: Varnish 6 and 7 (`varnish6.vcl`, `varnish7.vcl` in `Magento_PageCache/etc`; the admin also offers a Varnish 5/4 export on older lines; 2.4.9's requirements list Varnish 8, which runs the 7 template). Export the VCL from the CLI instead of the admin:

```bash
bin/magento varnish:vcl:generate --export-version=7 --backend-host=127.0.0.1 --backend-port=8080 --access-list=127.0.0.1 --grace-period=300 --output-file=/etc/varnish/default.vcl
```

Defaults: `--export-version=6`, `--backend-host=localhost`, `--backend-port=8080`, `--access-list=localhost`, `--grace-period=300`. `--input-file` takes a custom template. Then `bin/magento config:set system/full_page_cache/caching_application 2`, set the same host/port/access list under *Stores > Configuration > Advanced > System > Full Page Cache > Varnish Configuration* (or `system/full_page_cache/varnish/backend_host|backend_port|access_list|grace_period`), and register the Varnish hosts so cache cleans purge them: `bin/magento setup:config:set --http-cache-hosts=192.0.2.100,192.0.2.155:6081` (comma-separated `host[:port]`, no spaces; port 80 may be omitted). Typical layout: Varnish on :80/:443 termination in front, nginx on :8080 as the backend (`nginx.conf.sample`), `web/secure/offloader_header` = `X-Forwarded-Proto`.

What the shipped VCL does: hashes on URL + host + the `X-Magento-Vary` cookie (customer group, store, currency, login state — `Magento\Framework\App\Http\Context::getVaryString()`), passes everything that is not GET/HEAD and every URL matching `/customer` or `/checkout`, strips tracking parameters (`utm_*`, `gclid`, `fbclid`, …) from the hash; polls `pub/health_check.php` every 5 s (grace mode serves stale for `grace_period` seconds when the backend is unhealthy); accepts `PURGE` from the access list with `X-Magento-Tags-Pattern` (regex over the page's `X-Magento-Tags` header — `.*` on *Flush Magento Cache*) or `X-Pool`; on the way out sets `X-Magento-Cache-Debug: HIT|MISS|UNCACHEABLE`, rewrites `Cache-Control` to `no-store` for the browser (the public TTL is for Varnish only), and removes `X-Magento-Tags`, `X-Magento-Debug`, `Age` (kept only when Magento sent `X-Magento-Debug`, i.e. developer mode), `Via`, `X-Varnish`, `Server`. `cache:clean full_page` / *Flush Magento Cache* ban everything; product, category and CMS saves purge by tag. `service varnish restart` after the upgrade of any Magento version (the generated VCL may change); regenerate the VCL after every Magento upgrade.

Verify: `curl -sI https://store.example/ | grep -i x-magento` on a category page twice — `MISS` then `HIT`, plus `X-Magento-Cache-Control: max-age=86400, public, s-maxage=86400` and `Age` growing. `varnishlog`, `varnishstat` and `varnishadm 'ban req.url ~ .'` (Warden: `warden env exec -T varnish varnishadm …`) for the server side.

### ESI and private content with Varnish

A layout block with a `ttl` attribute (`<block … ttl="3600"/>`, e.g. `catalog.topnav` in `Magento_Theme/layout/default.xml`) is rendered as `<esi:include src="…/page_cache/block/esi/blocks/…/handles/…"/>` when Varnish is the caching application; Varnish assembles it with its own TTL and its tags are excluded from the page's `X-Magento-Tags`. `system/full_page_cache/handles_size` (default `100`) caps the handles accepted by that endpoint. The ESI URL is forced to `http` — Varnish does not fetch ESI over TLS, so the backend must answer plain HTTP on the backend port. Everything customer-specific stays client-side: customer-data sections (Luma; `etc/frontend/sections.xml` lists the POST/PUT actions that invalidate each section, the `private_content_version` cookie versions them) or Hyvä private content — `magento:frontend-luma`/`magento:frontend-hyva`, H4/P3. Do not put per-customer data in an ESI block; it would be cached per URL like any other fragment.

### Common FPC mistakes

- `cacheable="false"` in a `default.xml` or any handle that every page loads disables FPC site-wide (P3); use it only on inherently private pages (checkout, account) — core does exactly that.
- A controller returning a page with `Cache-Control: no-store` (e.g. `$page->setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0', true)`) is uncacheable by design — meant for AJAX data sources and payment return pages, not catalog pages.
- Reading `$_GET`/cookies in a block and rendering different output without adding a context variable (`Http\Context::setValue()` in a `beforeGetVaryString` plugin) leaks one user's variant to everyone; a *per-user* context value defeats the cache entirely.
- GraphQL: `Magento_GraphQlCache` sends public headers and `X-Magento-Tags` for cacheable queries (never for mutations), but Varnish and the built-in FPC only store GET/HEAD — so send cacheable storefront queries as GET; POST queries always reach PHP, which is what the 2.4.7+ `graphql_query_resolver_result` cache type is for. `X-Magento-Cache-Id` (a hash of the customer context — store, currency, customer group, tax, logged-in state — salted by `cache/graphql/id_salt` in `env.php`) is the extra hash key that separates GET-query variants; the VCL bypasses authenticated GraphQL requests that lack it.
- Maintenance mode disables public headers, so nothing is cached while `.maintenance.flag` exists.

## LiteMage (LiteSpeed Enterprise)

`litespeed/module-litemage` (Composer) or `app/code/Litespeed/Litemage` replaces the Varnish option with *LiteMage Cache Built-in to LiteSpeed Server* in the *Caching Application* list; the option appears only when the server sets `X-LITEMAGE` (LiteSpeed Enterprise with the LiteMage licence feature; `LiteMage on` inside `<IfModule LiteSpeed>` in the root `.htaccess`, which needs `AllowOverride All`). Install: `composer require litespeed/module-litemage`, `module:enable Litespeed_Litemage`, `setup:upgrade`, `setup:di:compile` in production; then select it as the caching application and refresh the *Configuration* and *Page Cache* types (`full_page` must be enabled). It honours the same layout rules as Varnish (`cacheable="false"`, `ttl` for ESI: `<esi:include … cache-control="no-vary,…"/>`), with ESI assembled by the web server — private blocks are ESI'd rather than fetched by JavaScript.

Headers: `X-LiteSpeed-Cache: miss,litemage` on the first hit, `hit,litemage` afterwards; the response also carries `X-LiteSpeed-Cache-Control: public,max-age=<ttl>` and `X-LiteSpeed-Tag: …` (Magento's identity tags). Set *LiteMage Cache > Developer Settings > Enable Debug* to *Yes and set X-LiteMage-Debug response headers* to see `X-LiteMage-Debug-Info|CC|Vary|Tag` and `X-LiteMage-Debug-Purge`; debug messages go to `var/log/litemage.log`. Purging is tag-based (`X-LiteSpeed-Purge`), triggered by the same `clean_cache_by_tags` events and by `bin/magento cache:clean full_page`; the *Disable CLI Purge* setting silences CLI-triggered purges during ERP syncs. Extra commands: `cache:litemage:flush:tags|prods|cats <ids>` and `cache:litemage:cli-flush`. Warming: LiteSpeed's `M2-crawler.sh <sitemap-url>` walks the sitemap (`-m` mobile view, `-i` interval); run it after catalog updates because every product save purges its tags. Magento's own `X-Magento-Cache-Debug` header is not set under LiteMage.

## Redis / Valkey for cache, page cache and sessions

The application cache, the built-in FPC and sessions are separate configurations and use **different Redis databases** (or instances) — sharing a database means `cache:flush` wipes sessions.

```bash
bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=127.0.0.1 --cache-backend-redis-db=0
bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=127.0.0.1 --page-cache-redis-db=1 --page-cache-redis-compress-data=1
bin/magento setup:config:set --session-save=redis --session-save-redis-host=127.0.0.1 --session-save-redis-db=2 --session-save-redis-log-level=4
```

Those write `env.php`:

```php
'cache' => [
    'frontend' => [
        'default'    => ['backend' => 'Magento\\Framework\\Cache\\Backend\\Redis', 'backend_options' => ['server' => '127.0.0.1', 'port' => '6379', 'database' => '0']],
        'page_cache' => ['backend' => 'Magento\\Framework\\Cache\\Backend\\Redis', 'backend_options' => ['server' => '127.0.0.1', 'port' => '6379', 'database' => '1', 'compress_data' => '1']],
    ],
],
'session' => ['save' => 'redis', 'redis' => ['host' => '127.0.0.1', 'port' => '6379', 'database' => '2', 'log_level' => '4', 'disable_locking' => '0']],
```

Version notes: 2.4.4–2.4.8 use the Zend-based backends and the full class names above (`Magento\Framework\Cache\Backend\Redis`, and `…\Valkey` on releases that ship it; `Cm_Cache_Backend_Redis` still works). **2.4.9 moved the cache to Symfony Cache**: the `backend` value is the short name `valkey`, `redis`, `file`, `memcached` or `database` (the factory lowercases the value and maps unknown strings — including the old class names — to the file backend, so upgrade `env.php` when you upgrade), `setup:config:set` accepts `--cache-backend=valkey --cache-backend-valkey-*`, `--page-cache=valkey`, `--session-save=valkey`, and Adobe states Redis is not supported on 2.4.9 nor on patch releases later than 2.4.5-p16, 2.4.6-p14, 2.4.7-p9 and 2.4.8-p4 (i.e. from p17/p15/p10/p5): use Valkey. `id_prefix` (`--cache-id-prefix`) keeps two stores apart in one database — but give them separate databases anyway.

L2 cache (multi-node): before 2.4.9 `backend` = `\Magento\Framework\Cache\Backend\RemoteSynchronizedCache` with `remote_backend` (Redis/Valkey) + `local_backend` = `Cm_Cache_Backend_File` on `/dev/shm/`; 2.4.9+ `backend` = `symfony_l2` with Valkey. `use_stale_cache => true` on the frontend serves stale entries while one process regenerates — Adobe recommends it for `block_html`, `config_integration`, `config_integration_api`, `full_page`, `layout`, `reflection` and `translate`, and explicitly not for the `default` cache type. Cloud (`ece-tools`) generates all of this from `.magento.env.yaml` — do not hand-edit there.

Preload (`'preload_keys' => [...]` under the default frontend's `backend_options`) fetches listed keys in one round trip at bootstrap — Adobe suggests the `EAV_ENTITY_TYPES`, `GLOBAL_PLUGIN_LIST`, `DB_IS_UP_TO_DATE`, `SYSTEM_DEFAULT` family, prefixed by the `id_prefix`.

## Static files, browsers and CDNs

`pub/static/deployed_version.txt` plus `dev/static/sign` = `1` put `/static/version<N>/` into every static URL, so a new `setup:static-content:deploy` (or `--refresh-content-version-only`) busts browser and CDN caches without purging; `nginx.conf.sample` and `.htaccess` add long `Cache-Control` for `/static/` and `/media/`. A CDN in front of Varnish/LiteMage caches HTML only if you let it: keep the CDN on `/static/` and `/media/` unless it understands `X-Magento-Tags` purges (Fastly does, on cloud). `Vary`, `X-Magento-Vary` and the `private_content_version`/`form_key` cookies must reach the origin unchanged; the `X-Forwarded-Proto` header must be set by the edge so `web/secure/offloader_header` works.

Warming: any crawler that hits the sitemap URLs with a desktop user agent (LiteSpeed's `M2-crawler.sh`, `wget -r -l1 --spider`, a `curl` loop over `sitemap.xml`); warm after deploys and catalog imports, and warm each `X-Magento-Vary` variant you care about (store view, currency) by sending the cookie.

## Sources

- https://developer.adobe.com/commerce/php/development/cache/page/ — Page caching overview (built-in vs Varnish, `cacheable="false"` makes the whole page uncacheable, public vs private content, GET/HEAD only)
- https://developer.adobe.com/commerce/php/development/cache/page/public-content — Public content (`cacheable="false"` in `default.xml` disables site-wide, `Cache-Control` no-store from a controller, `X-Magento-Vary`/context variables, `IdentityInterface`/`getIdentities()` on entity and block, tag count advice)
- https://developer.adobe.com/commerce/php/development/cache/page/private-content — Private content (customer-data sections, `sections.xml`, `private_content_version` cookie, `$_isScopePrivate` obsolete)
- https://developer.adobe.com/commerce/php/development/cache/partial/database-caching — Custom cache types and `CacheInterface` usage
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/manage-cache — Manage the cache (types list, clean vs flush, production-mode enable/disable restriction)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/cache-types — Configure cache types and frontends in `env.php` (2.4.9 Symfony implementation note)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/cache-options — Cache backend options (file/Redis/Valkey/database; class names before 2.4.9, short names from 2.4.9; Redis unsupported on 2.4.9 and listed patch releases)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/redis/redis-pg-cache — Use Redis for default and page cache (`setup:config:set --cache-backend=redis …`, `--page-cache=redis …`, database numbers must differ, `compress_data`, preload keys, 2.4.9 Valkey note)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/redis/redis-session — Use Redis for session storage (`--session-save=redis …`, `env.php` shape, `disable_locking`, `log_level`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/level-two-cache — L2 cache (`RemoteSynchronizedCache` before 2.4.9, `symfony_l2` from 2.4.9, `use_stale_cache` recommendations)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/varnish/config-varnish — Configure and use Varnish (recommended for production, nginx on 8080, health check)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/varnish/configure-varnish-commerce — Configure Commerce to use Varnish (admin fields, `config:set … caching_application 2`, VCL export, `acl purge`, restart)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/varnish/config-varnish-server — Configure nginx for Varnish (backend port, `varnishlog` sample with `X-Magento-Cache-Debug: HIT`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/varnish/config-varnish-final — Verify Varnish (`X-Magento-Cache-Control`, `Age`, `X-Magento-Cache-Debug: MISS`/`HIT`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/varnish/config-varnish-advanced — Advanced Varnish (health check every 5 s on `pub/health_check.php`, grace period 300 s, saint mode, multiple backends)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cache/varnish/use-varnish-cache — Cache clearing with Varnish (`setup:config:set --http-cache-hosts=…`, purge on clean/flush)
- https://docs.litespeedtech.com/lscache/litemage/ — LiteMage overview (LiteSpeed Enterprise requirement)
- https://docs.litespeedtech.com/lscache/litemage/installation/ — LiteMage installation (`composer require litespeed/module-litemage`, `module:enable Litespeed_Litemage`, `.htaccess` `LiteMage on`, `AllowOverride All`, `X-LiteSpeed-Cache: miss|hit, litemage`, `X-LiteSpeed-Cache-Control`, `X-LiteSpeed-Tag`)
- https://docs.litespeedtech.com/lscache/litemage/settings/ — LiteMage configuration (caching application selection, TTL, purge tuning, *Disable CLI Purge*, debug headers option)
- https://docs.litespeedtech.com/lscache/litemage/crawler/ — LiteMage crawler script (`M2-crawler.sh`, options, purge-on-product-update behaviour)
- https://docs.litespeedtech.com/lscache/litemage/faq/ — LiteMage FAQ
