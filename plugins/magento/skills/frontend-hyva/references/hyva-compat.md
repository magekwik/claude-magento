# Compatibility modules, `hyva_*` handles and the fallback modules

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release); Hyvä Theme 1.2–1.5.* Rules cited by ID are in `magento:conventions` (H1, H2, H3, H5 apply throughout).

## Why a Luma-built extension breaks on Hyvä

A Hyvä store view is a different theme tree, not a restyled Luma: `Hyva/default` does not inherit from `Magento/blank`, no RequireJS, jQuery, Knockout or `mage/*` script is on the page, and the theme's `styles.css` contains only the Tailwind utilities found in *its* scanned files. Since 1.3.21/1.4.0 `hyva-themes/magento2-base-layout-reset` (before that, the `Hyva/reset` parent theme from `hyva-themes/magento2-reset-theme` did the same job with static override files) also generates block-free copies of the base layout of every `Magento_*` module and of the bundled extensions it lists (Amazon Pay, Braintree, Klarna, Dotdigital, Vertex, …) in `var/hyva-layout-resets/`, so core Luma blocks never enter the merged layout of a Hyvä page — Hyvä re-adds its own blocks under `hyva_*` handles. Third-party modules are not reset, which is why their pages *look* half-present:

- Their layout XML and `.phtml` files do load and print markup.
- Any `x-magento-init`, `data-mage-init`, `require([...])`, `define([...])`, `data-bind` or Knockout `.html` template does nothing, and `require is not defined` / `$ is not defined` appears in the console (H1).
- Their `_module.less`/CSS is never compiled or loaded, and any Tailwind classes they might use are absent from `styles.css` unless the module is registered for the build (H3).
- Prices, forms, modals, sliders and messages that relied on Luma widgets (`priceBox`, `validation`, `modal`, `mage/translate`) are inert.

So before writing frontend code for any extension (H2): check whether a compatibility module exists, install it, and follow its patterns; only then fill the gaps.

## Finding an existing compatibility module

1. In the project: `ls app/code/Hyva vendor/hyva-themes` and `composer show | grep -E 'hyva-themes/|magento2-hyva-'`; `app/etc/hyva-themes.json` lists every module already registered for the Tailwind build; `grep -rl CompatModuleRegistry app/code vendor --include=di.xml` finds registrations.
2. In the Hyvä ecosystem: the Compatibility Module Tracker board (`https://gitlab.hyva.io/hyva-public/module-tracker/-/boards`, public) shows for each original module whether a compat module is requested, in progress or published; published ones install from `hyva-themes.repo.packagist.com` with a Hyvä licence (`composer require hyva-themes/magento2-<vendor>-<module>`), open-source ones from Packagist or GitHub.
3. From the vendor: many extension vendors ship their own (`<vendor>/magento2-hyva-<module>` or a `*-hyva` package), and some modules are "Hyvä-ready" without a separate package — they carry `hyva_*` layout files and Alpine templates themselves and register with `hyva-themes.json` (see below).

Naming (from the guidelines): module name `Hyva_<OriginalVendor><OriginalModule>` (`Smile_ElasticSuite` → `Hyva_SmileElasticSuite`, `Mirasvit_Gdpr` → `Hyva_MirasvitGdpr`); composer name `hyva-themes/magento2-<vendor>-<module>` when hosted on gitlab.hyva.io, otherwise `<vendor>/magento2-hyva-<module>`; one compat module may cover several original modules and one original module may have several compat modules (a checkout-specific one, for instance).

## Anatomy of a compatibility module

The skeleton the Hyvä team hands out (also what `hyva-themes/magento2-compat-module-fallback` expects):

```
magento2-mirasvit-gdpr/
├── composer.json           # "name": "hyva-themes/magento2-mirasvit-gdpr", type magento2-module,
│                           # require hyva-themes/magento2-compat-module-fallback
├── README.md, LICENSE.md
└── src/
    ├── registration.php    # Hyva_MirasvitGdpr
    ├── etc/module.xml      # <sequence><module name="Mirasvit_Gdpr"/><module name="Hyva_Theme"/></sequence>
    ├── etc/frontend/di.xml # CompatModuleRegistry registration (below)
    ├── etc/frontend/events.xml   # optional: hyva_config_generate_before observer
    ├── view/frontend/layout/hyva_default.xml, hyva_<route_controller_action>.xml
    ├── view/frontend/templates/…     # mirrors the ORIGINAL module's template paths
    ├── view/frontend/tailwind/module.css (1.4+) or tailwind.config.js + tailwind-source.css (1.3)
    └── view/frontend/web/svg/…       # optional icons
```

`etc/frontend/di.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:ObjectManager/etc/config.xsd">
    <type name="Hyva\CompatModuleFallback\Model\CompatModuleRegistry">
        <arguments>
            <argument name="compatModules" xsi:type="array">
                <item name="mirasvit_gdpr" xsi:type="array">
                    <item name="original_module" xsi:type="string">Mirasvit_Gdpr</item>
                    <item name="compat_module" xsi:type="string">Hyva_MirasvitGdpr</item>
                </item>
            </argument>
        </arguments>
    </type>
</config>
```

What that registration buys (from `magento2-compat-module-fallback`, a plugin on `Magento\Framework\View\Design\Fallback\Rule\ModularSwitch`):

- **Automatic template override.** `Mirasvit_Gdpr::cookie_bar.phtml` resolves to `Hyva/MirasvitGdpr/view/frontend/templates/cookie_bar.phtml` when that file exists — no layout XML, no `di.xml` plugin, even for blocks the original module creates programmatically. The resolved template still belongs to `Mirasvit_Gdpr`, so a *theme* override goes in `app/design/frontend/Acme/default/Mirasvit_Gdpr/templates/cookie_bar.phtml`, not under `Hyva_MirasvitGdpr`. Price renderer templates are the documented exception: override them with layout XML.
- **Automatic Tailwind registration.** Registered compat modules are added to `app/etc/hyva-themes.json` without an observer of their own.
- What it does *not* do: it bridges no JavaScript. `hyva-themes/magento2-compat-module-fallback` is a view-file fallback, not a RequireJS or jQuery shim — every widget still has to be rewritten in Alpine.

Layout: everything Hyvä-specific goes into `hyva_`-prefixed files (`view/frontend/layout/hyva_default.xml`, `hyva_catalog_product_view.xml`, `hyva_checkout_cart_index.xml`). On a Hyvä store view every handle on the page gets a `hyva_<handle>` twin loaded *after* the originals (`default` → `hyva_default`, `cms_index_index` → `hyva_cms_index_index`, `customer_logged_out` → `hyva_customer_logged_out`), and Luma store views never load them — so a module can serve both themes from one package, and a compat module can `<referenceBlock name="…" remove="true"/>` the Luma block and add its own without touching Luma. When a core block the extension hooks into was removed by the base-layout reset (`Magento_Banner`'s `banner.data`, for example), re-declare it in `hyva_default.xml`. PHP that must branch on the theme injects `Hyva\Theme\Service\CurrentTheme` and calls `isHyva()`; never test for a theme path starting with `Hyva/` (child themes are `Acme/default`; 1.4+ also exposes `Hyva\Theme\Service\HyvaThemes::isHyvaTheme()`). The cart page exists in two flavours — server-rendered PHP cart (default since 1.1.15) and the optional GraphQL cart (`hyva-themes/magento2-graphql-cart`) — with handles `hyva_checkout_cart_type_php.xml` / `hyva_checkout_cart_type_graphql.xml` and config flags `hyva_themes_cart/general/php_cart_enabled` / `graphql_cart_enabled` for `ifconfig`; put PHP-cart templates in a `php-cart/` subdirectory.

## Registering a module's templates and CSS with the Tailwind build (H3)

The theme's build only scans the theme. Every module whose templates use Tailwind classes, or that ships its own CSS, must be listed in `app/etc/hyva-themes.json` (Magento root):

```json
{
    "extensions": [
        { "src": "vendor/hyva-themes/magento2-theme-module/src" },
        { "src": "app/code/Acme/Catalog" },
        { "src": "vendor/hyva-themes/magento2-mirasvit-gdpr/src" }
    ]
}
```

The key names are `extensions` → objects with `src` (path relative to the Magento root, pointing at the directory that contains `view/`). The file is written by `bin/magento hyva:config:generate` and regenerated automatically by most commands that modify `app/etc/config.php` or `env.php` (`setup:upgrade`, `module:enable`/`disable`, `app:config:import`), so do not edit it by hand — a module adds itself by observing `hyva_config_generate_before`:

`app/code/Acme/Catalog/etc/frontend/events.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Event/etc/events.xsd">
    <event name="hyva_config_generate_before">
        <observer name="acme_catalog_register_hyva_config" instance="Acme\Catalog\Observer\RegisterModuleForHyvaConfig"/>
    </event>
</config>
```

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Observer;

use Magento\Framework\Component\ComponentRegistrar;
use Magento\Framework\Event\Observer;
use Magento\Framework\Event\ObserverInterface;

class RegisterModuleForHyvaConfig implements ObserverInterface
{
    public function __construct(private readonly ComponentRegistrar $componentRegistrar)
    {
    }

    public function execute(Observer $event): void
    {
        $config = $event->getData('config');
        $extensions = $config->hasData('extensions') ? $config->getData('extensions') : [];
        $path = $this->componentRegistrar->getPath(ComponentRegistrar::MODULE, 'Acme_Catalog');
        $extensions[] = ['src' => substr($path, strlen(BP) + 1)];
        $config->setData('extensions', $extensions);
    }
}
```

(Identical to the observer `Hyva_Theme` uses for itself; entries with the same `src` are merged.) Compat modules registered in the `CompatModuleRegistry` skip this step. To drop a module from the file: for registry-registered ones add its name to the `exclusions` array of `Hyva\CompatModuleFallback\Observer\HyvaThemeHyvaConfigGenerateBefore` in `di.xml` (compat-module-fallback ≥1.1.3); for observer-registered ones disable that observer in your `events.xml` (`<observer name="…" disabled="true"/>`); some modules use both.

What the build does with each `src` — via `@hyva-themes/hyva-modules` in the theme (`mergeTailwindConfig` + `postcssImportHyvaModules` on Tailwind 3; `npx hyva-sources` → `generated/hyva-source.css` on Tailwind 4) — depends on the module's `view/frontend/tailwind/`:

| Module ships | Tailwind 3 theme (1.2–1.3) | Tailwind 4 theme (1.4+) |
|---|---|---|
| `module.css` (recommended; `@source "../templates"; @source "../layout"; @import "./components/widget.css";`) | not read — provide the legacy files too if you support 1.3 | scanned/imported as written; `tailwind.config.js`/`tailwind-source.css` next to it are ignored |
| `tailwind.config.js` (legacy: `module.exports = { purge: { content: ['../templates/**/*.phtml', '../layout/*.xml'] }, theme: { extend: {…} } }`) | `purge.content` paths and `theme` merged into the theme config | only a generic `@source` for all `.phtml`/`.xml` in the module; no config merge |
| `tailwind-source.css` (legacy: `@import` lines) | imports added to the theme CSS | imports added, but every path must be explicit (`./…` or `../…`) |
| nothing | the `src` is in the list but contributes nothing — add `module.css` | same |

Nothing here removes the need to rebuild: after installing or changing a module, `npm run build` in the theme (and `bin/magento hyva:config:generate` first if `hyva-themes.json` is stale). Exclude a module's CSS from one theme with `hyva.config.json` `tailwind.exclude` (1.4+).

## Making a module Hyvä-compatible without a separate package

Same work, different packaging: keep the Luma templates and JS where they are, add `hyva_*` layout files that swap in Alpine templates (`<referenceBlock name="acme.widget" template="Acme_Catalog::hyva/widget.phtml"/>` in `hyva_catalog_product_view.xml`), register the module with `hyva_config_generate_before`, ship `view/frontend/tailwind/module.css`, and reference `$viewModels`/`$hyvaCsp` only in templates that are loaded through `hyva_*` handles (those variables do not exist on Luma, and `$hyvaCsp` needs theme module ≥ 1.3.11 — guard it with `isset()`). Test both store views.

## Porting a template: Luma → Hyvä

The migration page's process, one template at a time (copy every failing template into the compat module first and short-circuit the others with `<?php return; ?>` until you reach them):

1. Open the page on a Luma reference store view and on the Hyvä store view; note the console errors; find the template with `bin/magento dev:template-hints:enable`.
2. Copy the template to the same path under the compat module's `view/frontend/templates/` (automatic override) or add a `hyva_*` layout file pointing at a new template.
3. Move the JavaScript inline: `<script>function initAcmeWidget() { return { … } }</script>` (register it with `Alpine.data` inside an `alpine:init` listener when the same component appears more than once), then `x-data="initAcmeWidget()"` on the root element. Code that needs section data becomes a `private-content-loaded` subscriber; code that needs `window.hyva` in `<head>` waits for `DOMContentLoaded`; the rest runs inline after its definition. End each inline script with `<?php if (isset($hyvaCsp)) { $hyvaCsp->registerInlineScript(); } ?>` if the CSP theme must be supported (theme module ≥ 1.3.11 provides `$hyvaCsp`; the guard keeps older installs, CSP theme included, running).
4. Replace the stack: `$.ajax` → `fetch()` with `hyva.getFormKey()`; `data-post`/`data-post-action` links → `hyva.postForm({ action, data })`; `<script type="text/x-magento-template">` + `mage/template` → `<template x-for="item in items" :key="item.id">`; `$(el).data('x')` → `el.dataset.x` (parse JSON yourself; `dataset` is live, not cached); `mage/translate` `$t()` → `__()` in PHP; `Magento_Ui/js/modal/modal` → Hyvä's modal (`$viewModels->require(Modal::class)`; `x-htmldialog` native `<dialog>` plugin since 1.4.0, the modal itself rebuilt on it in 1.5.1/1.4.8); `priceBox` → `hyva.formatPrice()` and the `update-prices-<id>` events; `mage/validation` → HTML5 constraint validation plus Hyvä's `x-data="hyva.formValidation($el)"` with `data-validate='{"required": true}'` rules (1.1.14+); underscore helpers → native (`Array.isArray`, `Object.keys`, `JSON.stringify` equality); customer-data `customerData.get('cart')()` → `@private-content-loaded.window`.
5. Restyle with Tailwind utilities; keep the extension's semantic class names if its own JS or third-party CSS targets them; add the module to `hyva-themes.json` and rebuild.
6. Check both cart types and both theme variants if the extension touches the cart/checkout; run `phpcs --standard=Magento2` on the compat module (Q1).

## The other "fallback": serving pages with Luma

`hyva-themes/magento2-theme-fallback` (`Hyva_ThemeFallback`; the older `hyva-themes/magento2-luma-checkout` = `Hyva_LumaCheckout` now depends on it and only supplies the checkout defaults) is unrelated to the compat-module fallback: a before-plugin on every frontend controller compares the request's `route/controller/action` and SEO path against the configured list (`hyva_theme_fallback/general/list_part_of_url`, defaults `checkout/index`, `paypal/express/review`, `paypal/express/saveShippingMethod`) and, on a match, switches the whole request to the configured theme (`hyva_theme_fallback/general/theme_full_path`, default `frontend/Magento/luma`; enable with `hyva_theme_fallback/general/enable`). On such a page Hyvä is simply not active: RequireJS and Luma CSS load, Alpine and `styles.css` do not, and every `magento:frontend-luma` rule applies — including a Luma-side customer-data flow (Hyvä keeps the `section_data_ids` cookie in sync for exactly this case). Use it to run the core Luma checkout (or a Luma-only third-party checkout) on an otherwise Hyvä store, or to migrate a large site route by route; when the fallback theme is itself Hyvä-based, add `page_cache/block/esi` to the list so ESI blocks render. Hyvä Checkout is the alternative: `hyva-themes/magento2-hyva-checkout`, route `hyva_checkout`, its own component and CSS system (documented separately, CSP-ready).

## Debugging

- Page prints the extension's markup but nothing works: no compat module in play — `grep -rn "<original module>" app/etc/hyva-themes.json`, check the tracker, or start porting.
- Compat template ignored: the registry entry is in `etc/frontend/di.xml` (not `etc/di.xml`), the compat template path mirrors the original module's path exactly, and the theme has no override under the original module's directory shadowing it; `bin/magento cache:clean layout block_html full_page` after changes.
- Module classes missing from `styles.css`: `src` absent from `hyva-themes.json` (run `hyva:config:generate`), `module.css` missing (1.4) or `purge.content` missing (1.3), or the theme was not rebuilt.
- Hyvä block missing on a page: the base-layout reset removed the core block the extension referenced — re-add it in `hyva_default.xml`; `bin/magento hyva:base-layout-resets:generate` regenerates the reset files.
- Checkout renders Luma: the theme fallback is on for `checkout/index` (by design) — Luma rules there.

## Sources

- https://docs.hyva.io/hyva-themes/compatibility-modules/index.html — what a compatibility module is, the Module Tracker link, making existing modules compatible via `hyva-themes.json`
- https://docs.hyva.io/hyva-themes/compatibility-modules/getting-started.html — tracker at `https://gitlab.hyva.io/hyva-public/module-tracker/-/boards`, Luma reference store view, contribution flow, path-repository setup, "Making Existing Modules Hyvä-Compatible" (`hyva_*` layout for Hyvä-specific `.phtml`/JS)
- https://docs.hyva.io/hyva-themes/compatibility-modules/development-guidelines.html — porting process (`require is not defined`, copy template, inline and convert JS, `<?php return; ?>` trick), naming (`Hyva_SmileElasticSuite`, `hyva-themes/magento2-smile-elasticsuite`, `my-org/magento-hyva-integration`), folder structure, template docblocks
- https://docs.hyva.io/hyva-themes/compatibility-modules/technical-deep-dive.html — `CompatModuleRegistry` `compatModules` argument, automatic template override and theme-override path, price renderer exception, `module.css` vs legacy `tailwind.config.js`/`tailwind-source.css` per Tailwind version, automatic `hyva-themes.json` registration, `exclusions`/observer disabling, PHP vs GraphQL cart handles and `ifconfig` flags
- https://docs.hyva.io/hyva-themes/compatibility-modules/core-magento-compat-modules.html — core layout removed by the reset, re-adding blocks in `hyva_default.xml`
- https://docs.hyva.io/hyva-themes/compatibility-modules/from-luma-to-hyva/migrating-js-and-templates.html — inline scripts + `Alpine.data`, when to run (`private-content-loaded`, `DOMContentLoaded`, inline), `x-magento-template` → `x-for`, jQuery `data()` → `dataset`, underscore/jQuery equivalents
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/registering-a-module-for-tailwind-compilation.html — `app/etc/hyva-themes.json` shape (`extensions`/`src`), `bin/magento hyva:config:generate`, automatic regeneration, `hyva_config_generate_before` observer code, compat modules registered automatically
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/using-hyva-modules/index.html — `mergeTailwindConfig`, `postcssImportHyvaModules`, `npx hyva-sources`, `hyva.config.json` include/exclude
- https://docs.hyva.io/hyva-themes/writing-code/layout-and-templates/the-hyva_-layout-handles.html — `hyva_` twin handles loaded after the originals, Luma/Hyvä side by side, `CurrentTheme::isHyva()`
- https://docs.hyva.io/hyva-themes/advanced-topics/generated-base-layout-resets.html — base layout resets since 1.3.21, `var/hyva-layout-resets/`, `hyva:base-layout-resets:generate`, `HyvaThemes` `$hyvaBaseThemes` detection replacing the `Hyva/` prefix check
- https://docs.hyva.io/hyva-themes/upgrading/upgrading-to-1-4-0.html — reset theme replaced by `magento2-base-layout-reset`, `Hyva\Theme\Service\HyvaThemes` for theme detection
- https://docs.hyva.io/hyva-themes/building-your-theme/luma-theme-fallback.html — `magento2-theme-fallback`: config paths, checkout defaults, plugin on frontend controllers, `Hyva_LumaCheckout` history, `page_cache/block/esi` note
- https://docs.hyva.io/hyva-themes/writing-code/csp/csp-compatibility.html — `$hyvaCsp` exists only in Hyvä templates; reference it only under `hyva_*` handles in dual-theme modules
- https://docs.hyva.io/hyva-themes/writing-code/form-validation/javascript-form-validation.html — `x-data="hyva.formValidation($el)"`, `data-validate` JSON rules, `@submit`
- https://github.com/hyva-themes/magento2-compat-module-fallback — README (`CompatModuleRegistry` array shape, fallback order, `hyva-themes.json` hook), `src/etc/frontend/di.xml` (plugin on `Fallback\Rule\ModularSwitch`), tag 1.1.4
- https://github.com/hyva-themes/magento2-theme-module — `src/Observer/RegisterModuleForHyvaConfig.php`, `src/Model/HyvaModulesConfig.php` (`hyva-themes.json`, `hyva_config_generate_before`, same-`src` merge), `src/Console/Command/HyvaConfigGenerate.php`, `src/Plugin/HyvaModulesConfig/UpdateOnModuleStatusChange.php` (regenerate on `config.php`/`env.php` writes), `src/Observer/AddLayoutHandles*.php` (`hyva_` prefix), `src/Service/CurrentTheme.php`, `src/Service/HyvaThemes.php`; tags 1.3.22 and 1.5.2
- https://github.com/hyva-themes/magento2-base-layout-reset — README and `src/etc/di.xml` `modulesToReset` (`Magento` vendor plus listed bundled extensions), `hyvaBaseThemes`
- https://github.com/hyva-themes/magento2-theme-fallback and https://github.com/hyva-themes/magento2-luma-checkout — READMEs (config paths, defaults, `hyva_checkout` route note, migration of `hyva_luma_checkout/*` settings)
- https://github.com/hyva-themes/magento2-default-theme — `Magento_Checkout/layout/checkout_index_index.xml` ("No Checkout module installed" placeholder), `Magento_Checkout/templates/php-cart/`, tag 1.5.2
