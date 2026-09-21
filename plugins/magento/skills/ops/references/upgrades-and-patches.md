# Upgrades and patches

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magekwik-magento:conventions` (A7 never edit `vendor/`, patch through Composer).

## Release types

Adobe's version scheme (the marketing version, not the per-module semver): `2` major, `2.4` minor, `2.4.8` patch release (quality + security, may add backward-compatible features), `2.4.8-p1` security patch release (security and compliance fixes on top of the previous full patch release; `pN` counts up per line, e.g. `2.4.4-p18`), `2.4.8-alpha1`/`-beta1` pre-releases. Outside the version stream: **isolated security patch files** (non-cumulative `.patch` files for one or more CVEs, released between `-pN` versions, applied only on top of the *latest* `-pN` of the line, folded into the next security release), **hotfixes** (high-impact fixes delivered through the Quality Patches Tool and rolled into the next patch release; may be backward-incompatible) and **individual patches** (low-impact quality fixes via the Quality Patches Tool; backward compatible). Minor releases can break code (new PHP, new dependencies); patch releases avoid breaking changes "on an exceptional basis".

Each 2.4.x line supports a fixed PHP/DB/search set — do not tabulate it from memory, read the matrix: https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/system-requirements (at the time of writing 2.4.9 is tested with PHP 8.5, MariaDB 12.3 / MySQL 8.4, OpenSearch 3, Valkey 9, Varnish 8, Composer 2.10; 2.4.4-p18 with PHP 8.1, MariaDB 10.6, OpenSearch 2, Redis 7.2). Upgrading Magento usually means upgrading PHP, the database, the search engine and the cache store in the same window — plan them together and read the *PHP migration appendices* for the target PHP.

## Pre-checks

1. **Search engine**: `bin/magento config:show catalog/search/engine` — `elasticsearch7` (also used for OpenSearch before 2.4.6), `opensearch` (2.4.6+), `elasticsearch8` (2.4.6+); `mysql` means a 2.3-era install that must move to OpenSearch first. 2.4.9 supports only `opensearch` and `elasticsearch8`.
2. **Composer**: Composer 2 (the whole 2.4.4–2.4.9 range; the version each release is tested with is in the requirements matrix). Install the root update plugin once: `composer require magento/composer-root-update-plugin ~2.0 --no-update && composer update`. Keep `repo.magento.com` credentials in `auth.json` (never committed) — needed even for Open Source packages hosted there.
3. **Extensions**: for every third-party package check its `composer.json` constraints against the target (`composer why-not magento/product-community-edition 2.4.9` lists the blockers), read the vendor's compatibility notes, and grep `app/code` for deprecated/removed APIs (Zend → Laminas moves, `Magento\Framework\Serialize\Serializer\Serialize`, jQuery/UI component removals). Adobe's **Upgrade Compatibility Tool** (`magento/upgrade-compatibility-tool`, `bin/uct upgrade:check <dir> --coming-version=2.4.9`, plus `bin/uct dbschema:diff 2.4.8 2.4.9`) is documented for Adobe Commerce instances only and needs `repo.magento.com` Commerce keys; on Open Source rely on `composer why-not`, PHPCompatibility sniffs and the release notes.
4. **Custom code**: `vendor/bin/phpcs --standard=Magento2` and the PHPCompatibility standard for the target PHP; `setup:di:compile` on the new code in a throwaway environment catches constructor and DI breakage before production does.
5. **Data**: full database backup (`mysqldump --single-transaction --routines --triggers`, or XtraBackup — `setup:backup` is deprecated and documented as unreliable on rollback), `app/etc/env.php`, `pub/media`, and `composer.json` + `composer.lock` committed at the current version so a rollback is `git checkout` + `composer install`.
6. **Staging first**, on a copy of the production database; measure `setup:upgrade` duration there (declarative schema and data patches on large `sales_*`/`catalog_*` tables can take an hour).

## Minor / patch upgrade flow (Composer install)

```bash
bin/magento maintenance:enable
bin/magento cron:remove                                   # or comment the crontab line; stop queue consumers
bin/magento cron:run --group=consumers                    # drain message queues, wait for `ps aux | grep 'bin/magento queue'` to empty
cp composer.json composer.json.bak
composer require magento/composer-root-update-plugin ~2.0 --no-update && composer update     # once per project
composer require-commerce magento/product-community-edition 2.4.9 --no-update   # or 2.4.9-p1 for a security release
composer update                                           # resolves; --with-all-dependencies if third-party packages pin old libs
rm -rf var/cache/* var/page_cache/* generated/code/*      # the doc's step; also flush Redis/Valkey if you use it
bin/magento setup:upgrade                                 # schema + patches for the new version; deletes generated/
bin/magento setup:di:compile                              # production mode
bin/magento setup:static-content:deploy -f en_US --theme Acme/default --theme Magento/backend
bin/magento cache:flush
bin/magento maintenance:disable
bin/magento cron:install                                  # restore the crontab
service varnish restart                                   # if Varnish; regenerate the VCL when the Magento version changed
```

`composer require-commerce` (provided by the root update plugin) rewrites the root `composer.json` the way the new metapackage expects (`autoload`, `replace`, `config.allow-plugins`, scripts) and reports conflicting customisations; `--interactive-root-conflicts` walks through them, `--force-root-updates` overwrites them. Without the plugin `composer require magento/product-community-edition=2.4.9 --no-update` still resolves the package but leaves root-level drift in place — Adobe's current instructions use `require-commerce` for every 2.4 target. `composer show magento/product-community-edition 2.4.* --available | grep -m 1 versions` lists what is available. Sample data packages are upgraded in the same `require --no-update` step (`magento/module-*-sample-data:100.4.*`). 2.4.6-p13 lacks `magento/inventory-composer-installer` — `composer require magento/inventory-composer-installer` first when coming from 2.3.

A **security patch release** (`2.4.9-p1`) is the same procedure with the `-pN` version; it is a full Composer release, so `setup:upgrade`, compile and static deploy are still required. An **isolated security patch file** (from the Security Center / KB article) is a `.patch` applied with `cweagans/composer-patches` or `patch -p1` on top of the latest `-pN` — not a Composer version.

After the upgrade: `bin/magento setup:db:status` (expect "All modules are up to date"), `module:status` for anything that got disabled, `indexer:status` + `indexer:reindex` when the release notes say so, re-apply Quality Patches Tool patches that the new version does not include (`vendor/bin/magento-patches status`), regenerate and reinstall the Varnish VCL, check `var/log/exception.log` and the storefront + admin + checkout. If the storefront fails with "We're sorry, an error has occurred while generating this email", fix file ownership/permissions and clear `var/cache`, `var/page_cache`, `generated/code`.

## Quality Patches Tool (`magento/quality-patches`)

Adobe's channel for individual patches, hotfixes and some security fixes on Open Source and Commerce. Needs `git` or `patch` on the box.

```bash
composer require magento/quality-patches            # adds vendor/bin/magento-patches
vendor/bin/magento-patches status                   # Id | Title | Type (Optional/Deprecated) | Status (Applied/Not applied/N/A) | Details
vendor/bin/magento-patches apply MCLOUD-5650 ACSD-12345
bin/magento cache:clean
vendor/bin/magento-patches revert ACSD-12345        # --all reverts everything
composer update magento/quality-patches             # fetch newly released patches, then `status` again
```

Patches are applied to `vendor/` in place and are lost whenever Composer reinstalls the affected package (`composer update`, a fresh `composer install` on another machine, a build server) — `status` shows them as *Not applied* again, so run `apply` from the deploy script, not by hand. `N/A` means the patch conflicts with something already applied; *Required patches* in the *Details* column are dependencies. Keep the list of applied IDs in the repo (`patches.txt`, or a deploy script that runs `apply` idempotently): after a version upgrade, patches already merged upstream disappear from `status` and the rest must be re-applied one by one. Do not accumulate dozens of QPT patches — Adobe warns it makes the next upgrade harder. Log: `var/log/patch.log`.

## Custom patches with `cweagans/composer-patches` (A7)

For fixes Adobe has not shipped (a merged GitHub PR, a vendor's hotfix, your own change to a third-party module). Never edit `vendor/` — the next `composer install` reverts it.

1. Create the patch relative to the package root: take the GitHub commit or PR URL with `.diff` appended, or `git diff` the module inside `vendor/` and strip `app/code/Vendor/Module/` (source repo layout) so paths are relative to `vendor/vendor-name/module-name/`. Store it in the repo, e.g. `patches/composer/github-issue-6474.diff`; never point at a live PR URL (its content can change).
2. `composer require cweagans/composer-patches` (1.x; `~2.0` adds `patches.lock.json` and `composer patches-relock|patches-repatch|patches-doctor`), then in `composer.json`:

```json
"extra": {
    "composer-exit-on-patch-failure": true,
    "patches": {
        "magento/module-payment": {
            "MAGETWO-56934: Checkout page freezes with invalid credit card": "patches/composer/github-issue-6474.diff"
        }
    }
}
```

3. `composer install` (or `composer -v install` to watch it apply) and `composer update --lock`. One patch file per package — a diff touching two modules is two patches. Composer 2.2+ also needs `"config": {"allow-plugins": {"cweagans/composer-patches": true}}`. `patches-file` can move the map to `composer.patches.json`.
4. Commit the `.patch`, `composer.json` and `composer.lock`. Failed hunks abort the install because of `composer-exit-on-patch-failure` — which is what you want in CI.

Patches for core modules are also the answer for an isolated security patch file when you cannot yet move to the `-pN` release; drop them when you upgrade to a version that contains the fix (the hunk will fail loudly). Patching a dependency's `composer.json` does not work (metadata comes from the repository, not the file).

## Verifying what is applied

- `vendor/bin/magento-patches status` for QPT; `composer patches-doctor`/`PATCHES.txt` next to each patched package (1.x writes it, 2.x writes `patches.lock.json`) for Composer patches; `git diff --no-index` between a clean `composer create-project` of the same version and `vendor/` finds hand edits.
- `bin/magento --version`, `composer show magento/product-community-edition`, and `composer show -i | grep magento/` for the installed line; `setup:db:status` and `module:status` for consistency; `module:config:status` for `config.php` drift.
- `composer validate --no-check-all`, `composer audit` (Composer ≥ 2.4) for advisories on third-party packages.

## Rollback

Code: `git checkout <previous tag>` + `composer install` (the old `composer.lock`) + `setup:di:compile` + `setup:static-content:deploy -f …` — never `composer update` during a rollback. Database: declarative schema is one-way (`setup:upgrade` on the old code will not drop columns that the old declaration never had) and data patches do not revert; restore the dump taken before the upgrade, then optionally `bin/magento setup:upgrade --keep-generated` on the old code — `setup_module` and `patch_list` come back with the dump, so this only re-runs `app:config:import` and cleans caches. `--safe-mode=1` on the upgrade and `--data-restore=1` on the way back recover only data from tables/columns that declarative schema dropped. Keep the pre-upgrade `env.php` (cache backend names changed in 2.4.9) and the VCL. Practise the rollback on staging as part of the upgrade rehearsal.

## Extension compatibility checklist

- `composer why-not magento/product-community-edition <target>`; then `composer update --dry-run` with the new constraint.
- Vendor changelog for the target line; Marketplace extensions publish a supported-version list.
- PHP: every extension must load on the target PHP (PHPCompatibility sniff; `php -l` is not enough — deprecations become fatals across 8.x).
- Frontend: Luma extensions vs Hyvä (`magekwik-magento:frontend-hyva` H2), jQuery/RequireJS changes between releases; layout `htmlClass` values are validated by `htmlClassType` in `Magento/Framework/View/Layout/etc/elements.xsd`, whose pattern changed in 2.4.7 (2.4.6: `[a-zA-Z][a-zA-Z\d\-_:]*(\s…)*`; 2.4.7+: `[a-zA-Z\d\-_/:.\[\]&@() ]*`), so Tailwind class lists that validate on 2.4.7+ fail developer-mode XSD validation on 2.4.4–2.4.6.
- Run the integration/MFTF suites you have; at minimum place an order end-to-end on staging with every payment/shipping method.
- Third-party modules that ship `InstallSchema`/`UpgradeSchema` still run on 2.4 but block `--dry-run` accuracy — ask the vendor for declarative schema (A6).

## Sources

- https://experienceleague.adobe.com/en/docs/commerce-operations/upgrade-guide/implementation/perform-upgrade — Perform the upgrade (Composer 2 from 2.4.2, `composer require-commerce magento/<product> <version> --no-update` with `--interactive-root-conflicts`/`--force-root-updates`, `composer update`, maintenance mode, `cron:remove`, `cron:run --group=consumers`, `var/cache` + `var/page_cache` + `generated/code` clean-up, `setup:upgrade`, `maintenance:disable`, Varnish restart, 2.4.6-p13 inventory-composer-installer note, quality vs security patch examples)
- https://experienceleague.adobe.com/en/docs/commerce-operations/upgrade-guide/prepare/prerequisites — Upgrade prerequisites (search engine check via `config:show catalog/search/engine`, OpenSearch/Elasticsearch 8 support from 2.4.6, `composer require magento/composer-root-update-plugin ~2.0 --no-update`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/system-requirements — System requirements matrix per release line (PHP, MariaDB/MySQL, OpenSearch/Elasticsearch, Valkey/Redis, Varnish, Composer, nginx; required PHP extensions)
- https://experienceleague.adobe.com/en/docs/commerce-operations/release/planning/versioning-policy — Versioning policy (minor/patch/security patch `-pN`, isolated security patch files, hotfixes, individual patches, alpha/beta)
- https://experienceleague.adobe.com/en/docs/commerce-operations/upgrade-guide/upgrade-compatibility-tool/overview — Upgrade Compatibility Tool overview (Adobe Commerce only)
- https://experienceleague.adobe.com/en/docs/commerce-operations/upgrade-guide/upgrade-compatibility-tool/run — Run the Upgrade Compatibility Tool (`bin/uct upgrade:check <dir> -c <version>`, `dbschema:diff`, `core:code:changes`, 2 GB RAM)
- https://experienceleague.adobe.com/en/docs/commerce-operations/tools/quality-patches-tool/usage — Quality Patches Tool usage (`composer require magento/quality-patches`, `magento-patches status|apply|revert [--all]`, `cache:clean`, `composer update magento/quality-patches`, re-apply after upgrade, `var/log/patch.log`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/upgrade-guide/patches/overview — How patches work (hotfixes, individual, custom; creating a `.diff` from a GitHub commit and stripping `app/code/<VENDOR>/<PACKAGE>`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/upgrade-guide/patches/apply — Apply patches (`composer require cweagans/composer-patches`, `extra.composer-exit-on-patch-failure`/`patches` map, `composer -v install`, `composer update --lock`, `patch < file`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/deployment/single-machine — Single-machine deployment (`require-commerce` → `composer update` → `setup:upgrade` → `setup:di:compile` → `setup:static-content:deploy` → `cache:clean` inside maintenance mode)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/tutorials/backup — Back up and roll back (`setup:backup`/`setup:rollback` deprecated since 2.3.0; use external tools)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/tutorials/extensions — Install/update an extension (`composer require <vendor>/<module>`, `composer update vendor/module-name`, `module:enable --clear-static-content`, `setup:upgrade`, `setup:di:compile`, `cache:clean`)
- https://github.com/cweagans/composer-patches/blob/1.x/README.md — composer-patches 1.x README (`extra.patches` compact format, `patches-file`, `enable-patching`, `composer-exit-on-patch-failure`, `PATCHES.txt`, cannot patch a dependency's `composer.json`)
- https://docs.cweagans.net/composer-patches/getting-started/installation/ — composer-patches 2.x install (`composer require cweagans/composer-patches:~2.0`)
- https://docs.cweagans.net/composer-patches/usage/defining-patches/ — composer-patches 2.x patch definitions (compact/expanded formats, local paths, `sha256`, `depth`, `patches.json`, warning about PR URLs)
- https://docs.cweagans.net/composer-patches/usage/commands/ — composer-patches 2.x commands (`patches-relock`, `patches-repatch`, `patches-doctor`)
- https://raw.githubusercontent.com/magento/magento2/2.4.6/lib/internal/Magento/Framework/View/Layout/etc/elements.xsd and https://raw.githubusercontent.com/magento/magento2/2.4.7/lib/internal/Magento/Framework/View/Layout/etc/elements.xsd — `htmlClassType` pattern before/after the 2.4.7 change (2.4.9 vendor copy matches 2.4.7)
