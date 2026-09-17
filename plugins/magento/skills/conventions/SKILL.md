---
name: conventions
description: The Magento 2 rulebook — architecture, security, performance, Luma/Hyvä frontend and quality rules with rationale and the PHPCS sniff that enforces each. Read before writing or reviewing any Magento Open Source 2.4 code; other magento skills link here instead of restating rules.
---

# Magento 2 conventions

Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.4. Rules are numbered so reviews and other skills can cite them. Sniff names are from `magento/magento-coding-standard` (the `Magento2` ruleset); `PHPCS: —` means no sniff covers the rule and review must catch it by hand.

## Architecture

- **A1.** Never call `ObjectManager::getInstance()` or inject `ObjectManagerInterface` outside factories, proxies, setup/patch bootstrap and test code — *constructor DI keeps dependencies explicit, testable and compilable.* PHPCS: Magento2.Templates.ObjectManager (.phtml only; no sniff covers PHP classes)
- **A2.** Change behaviour with plugins (`before`/`after`; `around` only when the original must be skipped), never by editing or copying core classes; use a `preference` only to swap an implementation wholesale. Plugins cannot target `final`, `private`, `static` or constructors — *interceptors compose; preferences conflict.* PHPCS: —
- **A3.** Observers only react to events (side effects); they never return values or replace business logic — *the dispatcher ignores return values and observer order is undefined.* PHPCS: —
- **A4.** Expose module functionality through service contracts (`Api/*Interface`, `Api/Data/*Interface`); other modules depend on interfaces, never on models, resource models or collections — *contracts are the backward-compatibility boundary.* PHPCS: —
- **A5.** No raw SQL. Use resource models, collections, `SearchCriteriaBuilder` and repositories; if a connection is unavoidable use `getConnection()` with bound parameters, never string interpolation — *injection and index bypass.* PHPCS: Magento2.SQL.RawQuery
- **A6.** Schema is declarative only: `etc/db_schema.xml` + `db_schema_whitelist.json`; data changes are `DataPatchInterface` classes. No `InstallSchema`/`UpgradeSchema`/`InstallData`/`UpgradeData` in new code — *legacy scripts are deprecated since 2.3 and do not diff.* PHPCS: Magento2.Legacy.InstallUpgrade
- **A7.** Never edit `vendor/` or `app/code/Magento`, and never alter a core table's schema — extend with your own table, an EAV attribute or an extension attribute; patch third-party code only via `cweagans/composer-patches` with the `.patch` file committed — *edits vanish on the next `composer install`; core schema changes break upgrades.* PHPCS: —
- **A8.** Declare every module dependency in both `etc/module.xml` `<sequence>` and `composer.json` `require`; no circular dependencies — *load order and installation both depend on it.* PHPCS: —
- **A9.** Constructor injection only; use generated `Factory` classes for non-injectable objects (models, DTOs) and `Proxy` (declared in `di.xml`, never type-hinted) for heavy dependencies of frequently instantiated classes — *`new` bypasses DI; unproxied heavy deps slow every request.* PHPCS: Magento2.Classes.DiscouragedDependencies
- **A10.** Read configuration through `ScopeConfigInterface` with an explicit scope and a class constant for the path; no hard-coded store/website IDs — *multi-store correctness.* PHPCS: —

## Security

- **S1.** Every admin controller declares `ADMIN_RESOURCE` and every REST route declares `<resource>` in `webapi.xml` (`anonymous` only for genuinely public reads); resources live in `etc/acl.xml` — *authorization is opt-in.* PHPCS: —
- **S2.** Frontend controllers that mutate state implement `HttpPostActionInterface` (and `CsrfAwareActionInterface` only when a custom check is needed); GET never mutates — *form-key validation runs only on POST; the interface makes the router reject other methods, so a mutating action cannot be reached by GET.* PHPCS: —
- **S3.** Escape all template output with `$escaper->escapeHtml`/`escapeHtmlAttr`/`escapeUrl`/`escapeJs`; never echo raw request or entity data; `$block->escapeHtml` is deprecated — *XSS.* PHPCS: Magento2.Security.XssTemplate, Magento2.Legacy.EscapeMethodsOnBlockClass
- **S4.** Store secrets through `EncryptorInterface` / `Magento\Config\Model\Config\Backend\Encrypted`; never log credentials or PII — *`var/log` is world-readable in many deployments.* PHPCS: —
- **S5.** No `eval`, `exec`, `system`, `serialize`/`unserialize` on untrusted data; use `SerializerInterface` (Json) — *remote code execution.* PHPCS: Magento2.Security.InsecureFunction
- **S6.** Cast and validate every request parameter; whitelist uploads by extension and MIME; no user-controlled file paths — *path traversal and type confusion.* PHPCS: —

## Performance

- **P1.** Never load a model inside a loop; fetch sets with collections or repositories and page them — *N+1.* PHPCS: —
- **P2.** Do not load a collection to count it; use `getSize()`; do not call `getSize()` and then iterate the same collection without `setPageSize` — *two queries and full loads.* PHPCS: —
- **P3.** Keep pages full-page-cacheable: no `cacheable="false"` on layout blocks unless the whole page is inherently private (checkout, account); per-user fragments on cacheable pages go through customer-data sections (Luma) or private content (Hyvä) — *one uncacheable block disables FPC for the page.* PHPCS: —
- **P4.** No I/O or heavy work in constructors; plugins on hot paths (`ProductRepository::get`, `Layout::renderElement`) must be cheap — *injected dependencies are constructed eagerly, used or not.* PHPCS: —
- **P5.** Indexers run `Update by Schedule` in production; never invalidate or reindex from request code — *reindexing blocks the site.* PHPCS: —
- **P6.** Cron jobs are idempotent, bounded and assigned to a group; long-running jobs get their own group with `use_separate_process` — *one stuck job blocks the default group.* PHPCS: —
- **P7.** Cache expensive computed values with `CacheInterface` and entity tags so they invalidate correctly — *avoid recomputation; avoid staleness.* PHPCS: —

## Frontend — Luma

- **L1.** Change pages via layout XML (`referenceBlock`, `referenceContainer`, `move`, `remove`, arguments) before overriding templates; override a template only when markup must change — *smaller diffs survive upgrades.* PHPCS: —
- **L2.** Templates use `$block` and `$escaper` only; presentation logic goes in a ViewModel implementing `ArgumentInterface` passed via layout `<argument name="view_model">`, not a custom Block class — *ViewModels are testable and reusable.* PHPCS: Magento2.Templates.ThisInTemplate
- **L3.** JavaScript is RequireJS modules configured via `requirejs-config.js`, initialised with `x-magento-init`/`data-mage-init`; extend core widgets with mixins; no inline globals — *load order and the jQuery lifecycle.* PHPCS: —
- **L4.** Styles go in `web/css/source/_module.less` (module) or `_extend.less`/`_theme.less` (theme); no inline styles — *the LESS pipeline compiles per theme.* PHPCS: —
- **L5.** Never commit `pub/static`, `var/view_preprocessed` or `generated/`; production runs `setup:static-content:deploy` — *build outputs.* PHPCS: —

## Frontend — Hyvä

- **H1.** No RequireJS, Knockout, jQuery, `x-magento-init` or UI components; behaviour is Alpine.js (`x-data`) and styling is Tailwind utilities — *Hyvä removed the Luma JS stack.* PHPCS: —
- **H2.** Before writing any frontend for a third-party module, check for a Hyvä compatibility module (`hyva-themes/magento2-*` or a `*-hyva` module) and follow its patterns — *Luma templates from extensions render broken in Hyvä (no RequireJS, no CSS).* PHPCS: —
- **H3.** Tailwind must be able to see every template: add module paths to the theme's `tailwind.config.js` `content` and rebuild (`npm run build-prod` in `web/tailwind`) — *unseen classes are purged.* PHPCS: —
- **H4.** Data comes from ViewModels; per-customer data comes through private content (customer-data sections delivered by the `private-content-loaded` event), never Knockout `customer-data` bindings — *FPC-safe.* PHPCS: —
- **H5.** Override templates in the child theme mirroring the parent path; never copy the whole parent theme — *upgradability.* PHPCS: —

## Quality

- **Q1.** Run `vendor/bin/phpcs --standard=Magento2 <changed paths>` before finishing; fix all errors, justify any warning left — *the standard is the review baseline.* PHPCS: —
- **Q2.** New PHP files start with `declare(strict_types=1);` and use typed properties, parameters and returns; the syntax floor is PHP 8.1 — *catches type bugs at the boundary.* PHPCS: —
- **Q3.** Logic gets a unit test (`Magento\Framework\TestFramework\Unit\Helper\ObjectManager` wires constructors); resource/plugin behaviour gets an integration test — *DI-heavy code is cheap to unit-test and expensive to debug.* PHPCS: —
- **Q4.** Public service contracts carry `@api`; removals carry `@deprecated` + `@see`; never remove or change a public method signature in a minor release — *backward compatibility policy.* PHPCS: —
- **Q5.** User-facing strings go through `__()` with entries in `i18n/en_US.csv`; never concatenate translated fragments — *translation lookup and `%1` placeholder reordering.* PHPCS: —
- **Q6.** Admin config uses `etc/adminhtml/system.xml` with defaults in `etc/config.xml` and an ACL resource per section — *discoverable, scoped, secured.* PHPCS: —

## How this file is used

The `magento:code-reviewer` agent (behind `/magento:review`) reads it as its checklist and cites findings by rule ID.
`/magento:init` copies its body into the project's `.claude/rules/magento.md`, dropping the Hyvä section when no theme is Hyvä-based and the Luma section when every theme's parent chain is Hyvä.
Other `magento:*` skills cite rules by ID (for example "see conventions A1") instead of restating them.
