---
name: frontend-hyva
description: Hyvä theme development for Magento 2 — Tailwind CSS, Alpine.js components, ViewModels, private content, and compatibility modules for third-party extensions. Use for frontend work on Magento Open Source 2.4 stores whose theme inherits from Hyva/default (never RequireJS/Knockout/jQuery).
---

# Magento 2 Hyvä storefront

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release); Hyvä Theme 1.2–1.5 — Alpine.js 3 throughout, Tailwind CSS 3 on 1.2–1.3 and Tailwind CSS 4 on 1.4–1.5 (Hyvä itself requires Magento 2.4.4-p9 / 2.4.5-p8 / 2.4.6-p7 / 2.4.7-p1 or later and PHP 8.1–8.4; 1.4.6+ carries PHP 8.5 fixes).*

Rules: see `magento:conventions` H1–H5, S3, P3. This skill cites them by ID and does not restate them.

**Confirm the store is Hyvä before anything else:** the theme's `theme.xml` `<parent>` chain reaches `Hyva/default` (or `Hyva/default-csp`), and `composer.lock` lists `hyva-themes/magento2-theme-module` (the version there is the Hyvä version). `.claude/rules/magento.md` from `/magento:init` records this too. Which Tailwind you have: `web/tailwind/tailwind.config.js` + `postcss.config.js` = Tailwind 3 (1.2–1.3); `web/tailwind/hyva.config.json` + `@import "tailwindcss"` in `tailwind-source.css` = Tailwind 4 (1.4+).

## When to use

- Adding, moving, removing or restyling something on a storefront page of a theme whose parent is `Hyva/default`.
- Overriding a Hyvä template, giving a template data through a ViewModel, rendering icons.
- Storefront behaviour: Alpine.js components, `window.hyva` helpers, `fetch()` against Magento, customer section data (private content), Hyvä events.
- Tailwind: `content`/`@source` paths, `theme.extend`, rebuilding `styles.css`, "my class does nothing" problems.
- Making a third-party (Luma-built) extension work on Hyvä: finding or writing a compatibility module.

## When not to

- The theme's parent chain ends in `Magento/luma`/`Magento/blank`, or the page is served by the Luma theme fallback (checkout on many Hyvä stores) → `magento:frontend-luma`.
- Backend behaviour the frontend calls (plugins, observers, `di.xml`, controllers, ACL) → `magento:module`.
- Data the ViewModel needs (repositories, collections, EAV attributes) → `magento:data`; REST/GraphQL endpoints the page calls → `magento:api`.
- Hyvä Checkout internals (its own component system and docs) and admin UI components — not covered here.

## Decision guide

| Need | Use | Reference |
|---|---|---|
| Add, move or remove something on a page | Layout XML in the theme, `<Vendor>_<Module>/layout/<handle>.xml` with `referenceContainer`/`referenceBlock`/`move` — same mechanics as Luma (L1); Hyvä-only layout in a module goes in `hyva_<handle>.xml` | `hyva-compat.md` |
| Change markup | Template in the child theme mirroring the parent path (`Magento_Theme/templates/html/header.phtml`), never a copy of the whole parent theme (H5) | `tailwind-alpine.md` |
| Behaviour on the page | Alpine `x-data` component inline in the template, or a `<script>` in the same `.phtml` defining `function initX() { return {…} }` / `Alpine.data()`; page-wide scripts as `Hyva_Theme::page/js/…` blocks in `before.body.end` (H1) | `tailwind-alpine.md` |
| Data for a template | ViewModel implementing `ArgumentInterface`: `$viewModels->require(Acme\Catalog\ViewModel\X::class)` in the template, or a layout `view_model` argument (H4) | `tailwind-alpine.md` |
| Styling | Tailwind utility classes in the template, then rebuild `web/css/styles.css`; theme colours/fonts in `tailwind.config.js` `theme.extend` (1.2–1.3) or `@theme` in `tailwind-source.css` (1.4+) (H3) | `tailwind-alpine.md` |
| Per-customer data on a cacheable page | `private-content-loaded` window event (`$event.detail.data.<section>`) + `hyva.getBrowserStorage()`; reload with `reload-customer-section-data` — never `cacheable="false"` (H4, P3) | `tailwind-alpine.md` |
| Third-party module UI | Find the `Hyva_<Vendor><Module>` compatibility module first; write one if none exists (H2) | `hyva-compat.md` |
| Icons | `$viewModels->require(HeroiconsOutline::class)->xHtml('w-5 h-5', 20, 20)` (or `HeroiconsSolid`); own SVGs in the theme's `Hyva_Theme/web/svg/` via `SvgIcons::renderHtml('name')` | `tailwind-alpine.md` |
| Class does nothing / style missing | The file is outside Tailwind's `content`/`@source` paths, or the class is built dynamically, or `styles.css` was not rebuilt/redeployed (H3) | `tailwind-alpine.md` |

Two quick tests: *"Would this be a `define([...])`, `x-magento-init` or Knockout template on Luma?"* → it is an Alpine component in the `.phtml` here. *"Does the extension ship `view/frontend/web/js` or `requirejs-config.js`?"* → it needs a compatibility module before any of its pages will work.

## Rules that bite

1. **H1** — `require`, `define`, `$`, `jQuery` and `ko` are undefined on a Hyvä page and Luma `web/js` / `web/template` files are never loaded, so `x-magento-init`, `data-mage-init`, `data-bind` and RequireJS modules silently do nothing (or throw `require is not defined`). Behaviour lives in the template: `x-data` on the element or a `<script>` in the same `.phtml`. On `Hyva/default-csp` inline Alpine expressions are not evaluated (Alpine CSP build) and every inline `<script>` must be followed *immediately* by `<?php $hyvaCsp->registerInlineScript() ?>`.
2. **H3** — Tailwind emits only classes it finds as complete, unbroken strings in scanned files. 1.2–1.3: `tailwind.config.js` `content` (paths resolve from `web/tailwind`, where you run npm) ships `'../../**/*.phtml'` and `'../../*/layout/*.xml'`; uncomment/add `'../../../../../../../vendor/hyva-themes/magento2-default-theme/**/*.phtml'` for the parent theme and `'../../../../../../../app/code/**/*.phtml'` (or a narrower glob) for module templates. 1.4+: `@source "../../**/*.phtml"` in `tailwind-source.css` covers the theme; parent theme and modules come from `web/tailwind/hyva.config.json` `tailwind.include` (`[{ "src": "vendor/hyva-themes/magento2-default-theme" }]`) and `app/etc/hyva-themes.json`. `columns-<?= $n ?>` is never generated: list the possible classes in a PHP comment or drive a CSS variable.
3. **H3 / L5** — Rebuild after every template change: `cd app/design/frontend/Acme/default/web/tailwind && npm ci --ignore-scripts && npm run build` (`npm run build-prod` is the same script on 1.2–1.3 and again from 1.4.7; 1.4.0–1.4.6 have only `build`; `npm run watch` while developing; Node ≥16 for 1.3, ≥20 for 1.4+). Output is `web/css/styles.css`. Developer and default modes publish it on first request as a symlink into `pub/static/frontend/Acme/default/<locale>/css/` (a copy only when a preprocessor such as CSS minification rewrote it), so a rebuild is normally live at once — if not, delete that file and `var/view_preprocessed`; production serves only what `bin/magento setup:static-content:deploy --no-less --no-js-bundle --no-html-minify --theme Acme/default en_US` wrote. Build on CI or staging, not on the production box.
4. **S3** — `x-data`, `x-show`, `@click` and `:class` values are JavaScript inside an HTML attribute: a server value goes through `$escaper->escapeJs()` as a JS string literal *and* the whole attribute through `escapeHtmlAttr()`. Simpler and what Hyvä's own templates do: put the data in a `<script>` (`function initAcmeBanner() { return { threshold: '<?= $escaper->escapeJs($threshold) ?>' } }`) and write `x-data="initAcmeBanner()"`. Text nodes `escapeHtml()`, attributes `escapeHtmlAttr()`, `href` `escapeUrl()`; `$block->escapeHtml()` is deprecated; icon `…Html()` methods return safe HTML.
5. **H4 / L2** — Every Hyvä template gets `$block`, `$escaper`, `$viewModels` (`Hyva\Theme\Model\ViewModelRegistry`) and `$hyvaCsp`. `$viewModels->require(\Acme\Catalog\ViewModel\ShippingNotice::class)` returns any `ArgumentInterface` implementation without layout XML; the layout `<argument name="view_model" xsi:type="object">` form still works. Pass `$block` as the second argument only in templates rendered inside a `ttl="…"` ESI block. Hyvä's own: `CurrentProduct`, `CurrentCategory`, `ProductPrice`, `StoreConfig`, `Store`, `Customer`, `Modal`, `HeroiconsOutline`/`HeroiconsSolid`, `SvgIcons`, `BlockJsDependencies`.
6. **H4 / P3** — No `cacheable="false"`. All customer sections are fetched together from `customer/section/load` and dispatched once as `private-content-loaded` with `event.detail.data.cart`, `.customer`, `.messages`, …; subscribe with `@private-content-loaded.window="cart = $event.detail.data.cart"` or `window.addEventListener('private-content-loaded', …)`. Nothing reloads by itself: after your own POST/`fetch()` that changes the cart, `window.dispatchEvent(new CustomEvent('reload-customer-section-data'))`. Data is kept in `hyva.getBrowserStorage()` (`localStorage`, falls back to `sessionStorage`) under `mage-cache-storage` for the cookie lifetime (default 3600 s); `removeItem('mage-cache-storage')` invalidates without reloading. Your own section is `etc/frontend/sections.xml` + `SectionSourceInterface`, exactly as on Luma.
7. **H1** — `window.hyva` (from `Hyva_Theme::page/js/hyva.phtml` in `<head>`) replaces `mage/*`: `hyva.getFormKey()` (reads or creates the `form_key` cookie — every POST body needs it), `hyva.getCookie(name)` / `setCookie(name, value, days, skipSetDomain)` / `setSessionCookie`, `hyva.getBrowserStorage()`, `hyva.formatPrice(value, showSign, options)` (Intl, current currency), `hyva.postForm({action, data})` (adds `form_key` and `uenc`), `hyva.getUenc()`, `hyva.str('%1', x)`, `hyva.replaceDomElement(selector, html)` (runs scripts in the new HTML), `hyva.trapFocus(el)` / `releaseFocus(el)`, `hyva.alpineInitialized(fn)`. Globals `BASE_URL` and `CURRENT_STORE_CODE` come from `page/js/variables.phtml`. There is no `mage/url` or `mage/translate`: print `$escaper->escapeUrl($block->getUrl('route/x/y'))` and `__()` from PHP.
8. **H2** — A Luma-built extension's templates do render on a Hyvä store view, but its JS throws `require is not defined` and its LESS/CSS is absent. Before writing anything, look for `Hyva_<Vendor><Module>` in `app/code` and `vendor` (composer `hyva-themes/magento2-<vendor>-<module>` or `<vendor>/magento2-hyva-<module>`) and in the Hyvä compatibility module tracker. A compat module registered in `Hyva\CompatModuleFallback\Model\CompatModuleRegistry` (`etc/frontend/di.xml`) overrides `Orig_Module::x.phtml` just by shipping `view/frontend/templates/x.phtml`; a theme override of that template still lives under the *original* module directory (`Orig_Module/templates/x.phtml`).
9. **H2** — On a Hyvä store view every layout handle gets a `hyva_`-prefixed twin loaded *after* it (`hyva_default`, `hyva_catalog_product_view`) and Luma store views never load them: Hyvä-only blocks in a module go in `hyva_default.xml` etc., and a compat module re-adds there what `hyva-themes/magento2-base-layout-reset` stripped from the core layout. In PHP use `Hyva\Theme\Service\CurrentTheme::isHyva()` (1.4+ also `Hyva\Theme\Service\HyvaThemes`), never a string match on `Hyva/` — child themes have other names.
10. **H5** — Override by mirroring the parent path in the child theme (`Magento_Theme/templates/html/header.phtml`, `Magento_Catalog/templates/product/view/addtocart.phtml`, Hyvä's own under `Hyva_Theme/templates/…`); find the file with `bin/magento dev:template-hints:enable` (`dev/debug/template_hints_storefront`). Copy the parent's `web/` directory once when creating the theme (that is the Tailwind toolchain), never its template tree. Containers keep the Luma names (`after.body.start`, `header.container`, `page.top`, `top.container`, `columns.top`, `page.messages`, `content`, `sidebar.main`, `footer`, `before.body.end`) but the blocks inside are Hyvä's (`header-content`, `cart-drawer`, `topmenu_generic`, `footer-content`).
11. **H1 / H2** — The theme ships no checkout: `checkout_index_index` renders "No Checkout module installed" until Hyvä Checkout (`hyva-themes/magento2-hyva-checkout`, route `hyva_checkout`, its own component system), the Luma fallback (`hyva-themes/magento2-theme-fallback` + `magento2-luma-checkout`: routes such as `checkout/index` are rendered by `frontend/Magento/luma` with RequireJS — `magento:frontend-luma` rules apply on those pages), or a third-party checkout is installed. Never edit `Magento_Checkout/web/js` for a Hyvä store; the cart page is server-rendered PHP (`Magento_Checkout/templates/php-cart`).
12. **L1** — `x-show` toggles `display` and keeps the DOM (add `x-cloak`; Hyvä ships `[x-cloak] { display: none !important }`), `<template x-if>`/`<template x-for>` add and remove nodes. Layout `htmlClass` may hold Tailwind classes only on 2.4.7+ (`elements.xsd` allows `/ : . [ ] & @ ( )` there; 2.4.6 allows `:`; 2.4.4–2.4.5 letters, digits, `-`, `_`) — otherwise give the container a plain class and `@apply` in `web/tailwind/theme/page-layout.css`. After layout or template edits: `bin/magento cache:clean layout block_html full_page`.

## Minimal correct example

A dismissible "free shipping" banner at the top of every page of `Acme/default`, hidden for the rest of the browser session once closed, with the threshold from the same ViewModel as `magento:frontend-luma`'s example.

`app/design/frontend/Acme/default/Magento_Theme/layout/default.xml`:

```xml
<?xml version="1.0"?>
<page xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:View/Layout/etc/page_configuration.xsd">
    <body>
        <referenceContainer name="page.top">
            <block name="acme.shipping.banner" template="Magento_Theme::acme/shipping-banner.phtml" before="-">
                <arguments>
                    <argument name="view_model" xsi:type="object">Acme\Catalog\ViewModel\ShippingNotice</argument>
                </arguments>
            </block>
        </referenceContainer>
    </body>
</page>
```

`app/code/Acme/Catalog/ViewModel/ShippingNotice.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\ViewModel;

use Magento\Framework\View\Element\Block\ArgumentInterface;

class ShippingNotice implements ArgumentInterface
{
    public function getThreshold(): string
    {
        return '$50';
    }
}
```

`app/design/frontend/Acme/default/Magento_Theme/templates/acme/shipping-banner.phtml`:

```php
<?php
declare(strict_types=1);

use Acme\Catalog\ViewModel\ShippingNotice;
use Hyva\Theme\Model\ViewModelRegistry;
use Hyva\Theme\ViewModel\HeroiconsOutline;
use Magento\Framework\Escaper;
use Magento\Framework\View\Element\Template;

/** @var Template $block */
/** @var Escaper $escaper */
/** @var ViewModelRegistry $viewModels */

/** @var ShippingNotice $viewModel */
$viewModel = $block->getData('view_model');
/** @var HeroiconsOutline $heroicons */
$heroicons = $viewModels->require(HeroiconsOutline::class);
?>
<div x-data="{ open: sessionStorage.getItem('acme-banner') !== 'closed' }"
     x-show="open"
     x-cloak
     role="status"
     class="bg-primary text-white px-4 py-2 flex justify-between items-center">
    <span><?= $escaper->escapeHtml(__('Free shipping on orders over %1', $viewModel->getThreshold())) ?></span>
    <button type="button"
            class="ml-4 p-1"
            aria-label="<?= $escaper->escapeHtmlAttr(__('Dismiss')) ?>"
            @click="open = false; sessionStorage.setItem('acme-banner', 'closed')">
        <?= $heroicons->xHtml('', 20, 20, ['aria-hidden' => 'true']) ?>
    </button>
</div>
```

Rebuild the stylesheet (the template is under the theme, so the shipped `content` / `@source` globs already cover it): `cd app/design/frontend/Acme/default/web/tailwind && npm ci --ignore-scripts && npm run build` (`npm run build-prod` on 1.2–1.3), then `bin/magento cache:clean layout block_html full_page`.

Why this shape: `page.top` is the container Hyvä's `Magento_Theme/page_layout/override/base/1column.xml` places right after `header.container`, so the banner sits under the header on every page (`header.container` with `before="-"` would put it above the skip link — keep that first); `default.xml` in the theme's `Magento_Theme` directory merges into every page after the parent theme's file (rule 10). The block has no `class`, so it is a plain `Template`; the threshold comes from the `view_model` argument (rule 5), and the icon from `HeroiconsOutline` through the registry that every Hyvä template already has. The state is one Alpine component on the element (rule 1): `x-data` reads `sessionStorage`, `x-show` keeps the element in the DOM, `x-cloak` stops it flashing before Alpine boots (rule 12), and the click handler writes the flag back — no `<script>`, so nothing to register for CSP; on `Hyva/default-csp` move the object into `Alpine.data('acmeBanner', …)` in a `<script>` followed by `$hyvaCsp->registerInlineScript()`. The translated `Phrase` is escaped as text and as an attribute value (rule 4); `xHtml()` returns safe SVG. `bg-primary`, `text-white`, `flex`, `justify-between` exist in the theme palette (Hyvä's `backgroundColor.primary` on 1.3, `--color-primary` on 1.5) and Tailwind sees them because the template is under the theme's globs (rule 2), but only after the rebuild (rule 3). Nothing is `cacheable="false"` and nothing differs per customer, so no private content is needed (rule 6).

## Routing table

| For | Read |
|---|---|
| Theme `web/tailwind` layout on 1.2–1.3 (`tailwind.config.js`, `postcss.config.js`, `tailwind-source.css`) and 1.4+ (`tailwind-source.css` with `@source`/`@theme`, `hyva.config.json`, `generated/`), `content` globs and `@source`, `theme.extend` colours/fonts, `@apply`, purge pitfalls, build/watch commands, deploying `styles.css`, dark mode; Alpine directives Hyvä uses (`x-data`, `x-show`, `x-cloak`, `x-ref`, `x-init`, `@click.outside`, `$dispatch`, `Alpine.store`, `<template x-if>`/`x-for`); `<script>` placement and `Hyva_Theme::page/js/…` blocks; `window.hyva` helpers; Hyvä events; private content and `sections.xml`; ViewModels and icons | `references/tailwind-alpine.md` |
| Why Luma module frontends fail, compatibility module naming and the tracker, module structure, the `CompatModuleRegistry` automatic template override, `hyva_*` layout handles, registering a module's templates and CSS for the Tailwind build (`hyva-themes.json`, `hyva_config_generate_before`, `view/frontend/tailwind/module.css`), overriding an extension's templates, the Luma theme fallback and `magento2-compat-module-fallback` and what each does (and does not) cover | `references/hyva-compat.md` |
