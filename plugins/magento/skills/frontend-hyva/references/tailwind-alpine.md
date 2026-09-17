# Tailwind CSS, Alpine.js, `window.hyva`, private content and ViewModels

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release); Hyvä Theme 1.2–1.5.* Rules cited by ID are in `magento:conventions` (H1, H3, H4, S3, P3 apply throughout).

Hyvä replaces Luma's RequireJS/jQuery/Knockout/LESS stack with a `styles.css` compiled by Tailwind from the classes found in your templates, Alpine.js 3 for behaviour, a small `window.hyva` helper object, and native `fetch()`. Every piece of JavaScript lives in the `.phtml` that uses it. Hyvä 1.2–1.3 build with Tailwind 3 (`tailwind.config.js`), 1.4–1.5 with Tailwind 4 (CSS-first, `@source`/`@theme` in `tailwind-source.css`); the sections below say which applies.

## The theme's `web/tailwind` directory

A child theme gets a full copy of the parent's `web/` directory once (`cp -r vendor/hyva-themes/magento2-default-theme/web/* app/design/frontend/Acme/default/web/`) and builds its own `web/css/styles.css`; templates and layout are *not* copied (H5).

| File | Hyvä 1.2–1.3 (Tailwind 3) | Hyvä 1.4–1.5 (Tailwind 4) |
|---|---|---|
| `package.json` | `tailwindcss ^3`, `@tailwindcss/forms`, `@tailwindcss/typography`, `postcss-import`, `@hyva-themes/hyva-modules ^1.0`; Node ≥16 | `tailwindcss ^4`, `@tailwindcss/cli`, `@hyva-themes/hyva-modules ^1.4`; `"type": "module"`; Node ≥20 |
| Scripts | `build` (= `NODE_ENV=production npx tailwindcss --postcss -i tailwind-source.css -o ../css/styles.css --minify`), `build-prod` (same + "Done!"), `watch`, `browser-sync` | `build` (= `npm run generate && npx tailwindcss -i tailwind-source.css -o ../css/styles.css --minify`), `generate` (= `npx hyva-sources && npx hyva-tokens`), `watch`, `start`, `browser-sync`; `build-prod` alias again from 1.4.7 |
| `tailwind.config.js` | `hyvaModules.mergeTailwindConfig({ theme: { extend: {…} }, plugins: [...], content: [...] })` | none (a legacy config could be loaded with `@config`, the theme does not) |
| `postcss.config.js` | `postcssImportHyvaModules`, `postcss-import`, `tailwindcss/nesting`, `tailwindcss`, `postcss-preset-env` | none |
| `tailwind-source.css` | `@import "tailwindcss/base"; @import "tailwindcss/components"; @import url(components/*.css)…; @import "tailwindcss/utilities"; @import "theme.css";` | `@import "@hyva-themes/hyva-modules/css"; @import "tailwindcss" source(none); @source "../../**/*.phtml"; @source "../../**/*.xml"; @import "./base"; "./components"; "./theme"; "./utilities"; @import "./generated/hyva-source.css"; "./generated/hyva-tokens.css"; @theme { … }` |
| `hyva.config.json` | — | `tailwind.include`/`exclude` (`[{ "src": "vendor/hyva-themes/magento2-default-theme" }]`) and `tokens.values` (`color.primary`, …) read by `npx hyva-sources` / `npx hyva-tokens` |
| Styles | `components/*.css` (`button.css`, `forms.css`, `theming.css` with `[x-cloak]`, `modal.css`, …), `theme.css` | `base/`, `components/`, `theme/` (`page-layout.css`…), `utilities/`, `generated/` (written by `generate`, do not edit) |
| Output | `web/css/styles.css` (committed in Hyvä's own repo; build it on CI or commit it) | same |

Build from that directory (Tailwind 3 resolves `content` paths from the working directory, so run there or use `npm --prefix app/design/frontend/Acme/default/web/tailwind run build`):

```sh
cd app/design/frontend/Acme/default/web/tailwind
npm ci --ignore-scripts      # exact versions from package-lock.json, no lifecycle scripts
npm run build                # minified production styles.css  (1.2–1.3: npm run build-prod is the same)
npm run watch                # rebuild on every template change while developing
```

What Magento then does with `web/css/styles.css` (L5): developer and default modes publish it on first request through `static.php` as a symlink into `pub/static/frontend/Acme/default/<locale>/css/` (a copy under `var/view_preprocessed` only when a preprocessor — CSS minification outside developer mode — rewrote it), so a rebuild is normally live at once; if it is not, delete the published file and `var/view_preprocessed`. Production serves only what `bin/magento setup:static-content:deploy --area frontend --theme Acme/default --no-less --no-js-bundle --no-html-minify en_US` wrote (Hyvä needs neither LESS, JS bundling nor HTML minification, and the docs recommend leaving Magento's minification/bundling settings off). Build on CI or staging, never on the production host.

## Content paths — what Tailwind scans (H3)

Tailwind reads scanned files as plain text and emits a utility only for a class name it finds as a complete, unbroken string; nothing is evaluated. Consequences:

- **Tailwind 3** (`tailwind.config.js`), as shipped:

  ```js
  content: [
    '../../**/*.phtml',                       // this theme's templates
    '../../*/layout/*.xml',                   // layout XML (htmlClass attributes)
    '../../*/page_layout/override/base/*.xml',
    // parent theme in vendor (uncomment in a child theme)
    //'../../../../../../../vendor/hyva-themes/magento2-default-theme/**/*.phtml',
    //'../../../../../../../vendor/hyva-themes/magento2-default-theme/*/layout/*.xml',
    // app/code modules whose templates use Tailwind classes
    //'../../../../../../../app/code/**/*.phtml',
  ]
  ```

  Seven `../` from `web/tailwind` reach the Magento root. A child theme *must* enable the parent-theme lines, otherwise every parent template's classes are missing from `styles.css`. Module templates are either added here by hand (narrow it: `'../../../../../../../app/code/Acme/**/view/frontend/templates/**/*.phtml'`) or, better, registered in `app/etc/hyva-themes.json` so `mergeTailwindConfig` adds them for every theme (see `hyva-compat.md`). `safelist: [...]` exists for classes that cannot be scanned; prefer fixing the paths.
- **Tailwind 4** (`tailwind-source.css`): `@import "tailwindcss" source(none);` disables automatic detection, then `@source "../../**/*.phtml"; @source "../../**/*.xml";` (relative to the CSS file) scan the theme. The parent theme and modules are *not* globbed by hand: `npx hyva-sources` (run by `build`/`watch`) writes `generated/hyva-source.css` with `@source`/`@import` lines for every path in `app/etc/hyva-themes.json` plus `hyva.config.json` `tailwind.include`, minus `tailwind.exclude`. Two 1.4 pitfalls from the docs: `@source` honours `.gitignore`, so an allow-list `.gitignore` (`*` then `!app/`) hides `vendor/hyva-themes/...` from the scan — use a deny-list; and `@import` of local files needs an explicit `./` or `../` prefix.
- **Dynamic class names** never work in either version: `columns-<?= $n ?>`, `'bg-' . $color . '-500'`, `:class="'text-' + size"`. Either list every possible class in a PHP comment next to the markup (`<?php // columns-1 columns-2 columns-3 xl:columns-3 ?>`), or map values to full class names in PHP, or (1.4+) drive a CSS variable: `class="columns-(--cols)" style="--cols: <?= (int) $n ?>"`.
- Layout `htmlClass` values are scanned (`'../../*/layout/*.xml'`), but the XSD only allows Tailwind's `/ : . [ ] & @ ( )` from Magento 2.4.7 (`:` from 2.4.6); on older releases use a plain class and `@apply` in `web/tailwind/theme/page-layout.css`.

## Extending the theme: colours, fonts, components

**Tailwind 3** — `theme.extend` merges with the defaults, keys directly under `theme` replace the whole scale. Hyvä's config defines the names its templates use (`primary`, `secondary`, `background`, `container` with `lighter`/`DEFAULT`/`darker`, separately for `colors`, `textColor`, `backgroundColor`, `borderColor`), so `bg-primary`, `text-secondary-darker`, `bg-container-lighter`, `border-container` are what you restyle:

```js
const colors = require('tailwindcss/colors');
module.exports = hyvaModules.mergeTailwindConfig({
  theme: {
    extend: {
      fontFamily: { sans: ['Inter', 'Segoe UI', 'Helvetica Neue', 'Arial', 'sans-serif'] },
      colors: { primary: { lighter: colors.emerald['300'], DEFAULT: colors.emerald['700'], darker: colors.emerald['900'] } },
      backgroundColor: { primary: { lighter: colors.emerald['600'], DEFAULT: colors.emerald['700'], darker: colors.emerald['800'] } },
      borderColor: { primary: { DEFAULT: colors.emerald['700'] } },
    },
  },
  plugins: [require('@tailwindcss/forms'), require('@tailwindcss/typography')],
  content: [ /* as above */ ],
});
```

**Tailwind 4** — tokens are CSS variables in a top-level `@theme { }` block in `tailwind-source.css` (`--color-primary: oklch(46% 0.2 265)` → `bg-primary`, `text-primary`, `border-primary`; `--font-sans`, `--breakpoint-md`, `--spacing`); Hyvä's own `@theme` maps `--color-ink`, `--color-fg`, `--color-bg`, `--color-surface` onto Tailwind's palette, and `hyva.config.json` `tokens.values.color.{primary,secondary,on-primary,on-secondary}` are turned into `generated/hyva-tokens.css` by `npx hyva-tokens`. Default palette values are available as variables (`var(--color-slate-950)`). v3 utilities that v4 dropped (`flex-shrink-0`, `bg-opacity-50`, `overflow-ellipsis`) are re-added by `@import "@hyva-themes/hyva-modules/css"` for third-party modules only — write `shrink-0`, `bg-black/50`, `text-ellipsis` in new code.

**Custom CSS and `@apply`** — utilities in the template first; when the same class list repeats across many templates, or an element has no template (`htmlClass`, CMS content, third-party markup), add a rule in `web/tailwind/theme/*.css` (1.4) or `components/*.css` / `theme.css` (1.3) built with `@apply`. That is how Hyvä styles buttons, forms, `.card`, page layout; it is not a way to keep templates "clean" — every `@apply` class is one more thing Tailwind cannot tree-shake or see in the markup. Nested rules (`&:hover`) work in both versions (`tailwindcss/nesting` in 1.3, native in 1.4).

**Dark mode** — the `dark:` variant follows `prefers-color-scheme` by default in both versions. For a toggle: Tailwind 3 `darkMode: 'selector'` (`'class'` before 3.4.1) in `tailwind.config.js`; Tailwind 4 `@custom-variant dark (&:where(.dark, .dark *));` in `tailwind-source.css`. Then add/remove `dark` on `<html>` from an Alpine component (`document.documentElement.classList.toggle('dark', on)`) and persist the choice in `hyva.getBrowserStorage()`. Hyvä's default theme ships no dark palette; every `dark:` class you add must appear in a scanned file like any other.

## Alpine.js in Hyvä templates (H1)

Alpine 3 is loaded as `Hyva_Theme::js/alpine3.min.js` (module script, `defer`) from the `script-alpine-js` block in `before.body.end`, so components initialise after the DOM is parsed. The directives Hyvä templates use:

| Directive | Meaning |
|---|---|
| `x-data="{ open: false, toggle() { this.open = !this.open } }"` | Component scope on this element and its children; state, methods, getters; `this` is the object. `x-data="initBanner()"` calls a function defined in a `<script>` in the same template (Hyvä's own pattern), `x-data="acmeBanner"` uses `Alpine.data('acmeBanner', () => ({…}))` registered inside a `document.addEventListener('alpine:init', …)` listener (the `Alpine` global does not exist before the deferred script runs). |
| `x-init="load()"` | Runs when the component initialises (`$nextTick` inside it for after-render). |
| `x-show="open"` | Toggles `display: none` — the DOM stays. Add `x-cloak` to elements that start hidden; Hyvä ships `[x-cloak] { display: none !important }` (`components/theming.css` in 1.3, `base/index.css` in 1.4). `x-transition` for animation. |
| `<template x-if="items.length">…</template>` / `<template x-for="item in items" :key="item.id">…</template>` | Add/remove nodes; one root element inside the `<template>`. |
| `x-ref="input"` / `$refs.input` | Element handles instead of `querySelector`. |
| `@click="…"`, `@click.prevent`, `@click.outside="open = false"` (`.away` is the Alpine 2 name and still accepted), `@keydown.escape.window`, `@submit.prevent` | Event listeners; `.window` listens on `window` (`@private-content-loaded.window`, `@toggle-cart.window`). |
| `:class="{ 'hidden': !open }"`, `:aria-expanded="open"`, `x-text="label"`, `x-html="html"` | Bindings; `x-html` only for server-escaped HTML. |
| `$dispatch('toggle-cart')` / `window.dispatchEvent(new CustomEvent('name', { detail }))` | Components talk through window events, never through shared globals. |
| `Alpine.store('cart', { items: [] })` / `$store.cart.items` | Cross-component state; register in the same `alpine:init` listener. |
| `x-defer="intersect"`, `x-intersect`, `x-ignore`, `x-snap-slider`, `x-htmldialog` | Hyvä-bundled plugins: defer initialisation until visible/idle/interaction, viewport observation, skip a subtree, CSS-driven sliders, native `<dialog>` (1.4+ modal). |

Server values inside Alpine expressions are JavaScript inside an attribute (S3): `x-data="{ threshold: '<?= $escaper->escapeJs($threshold) ?>' }"` is the minimum; the whole attribute value should also be `escapeHtmlAttr()`-safe. Cleaner:

```php
<script>
    function initAcmeNotice() {
        return {
            threshold: '<?= $escaper->escapeJs($viewModel->getThreshold()) ?>',
            open: sessionStorage.getItem('acme-notice') !== 'closed',
            close() { this.open = false; sessionStorage.setItem('acme-notice', 'closed'); }
        }
    }
</script>
<?php $hyvaCsp->registerInlineScript() ?>
<div x-data="initAcmeNotice()" x-show="open" x-cloak>…</div>
```

`$hyvaCsp->registerInlineScript()` must follow the `</script>` with nothing in between (it hashes the preceding script; call it after *each* inline script). It is harmless on the non-CSP theme and required on `Hyva/default-csp`, whose Alpine CSP build evaluates no inline expressions at all: there, `x-data` may only name a registered component, `:class="hiddenClass"` refers to a method, and `hyva.createBooleanObject('open')` supplies the toggle boilerplate. `x-data` objects and `<script>` blocks are rendered per block: a template printed in a loop (product list items) should move its script into a block rendered once, via `hyva_js_block_dependencies` in layout XML or `$viewModels->require(BlockJsDependencies::class)->setBlockNameDependency($block, 'name')` (1.3.6+). Script placement in general: inline in the `.phtml` that uses it; theme-wide scripts as blocks in `before.body.end` (`Hyva_Theme::page/js/…` templates are where Hyvä keeps its own: `hyva.phtml`, `variables.phtml` in `head.additional`; `alpinejs.phtml`, `cookies.phtml`, `private-content.phtml`, `modal.phtml` in `before.body.end`); code that needs Alpine ready goes in `hyva.alpineInitialized(() => …)` or an `alpine:initialized` listener; nothing goes in `requirejs-config.js`, `web/js/*.js` modules or `x-magento-init`.

## `window.hyva` helpers

Defined in `Hyva_Theme::page/js/hyva.phtml` (block `head.hyva-scripts`, in `<head>`), so available to every inline script and Alpine expression:

| Helper | Use |
|---|---|
| `hyva.getFormKey()` | Value of the `form_key` cookie (created if missing) — required in every POST body: `new URLSearchParams({ form_key: hyva.getFormKey(), qty })`. |
| `hyva.getCookie(name)`, `hyva.setCookie(name, value, days, skipSetDomain)`, `hyva.setSessionCookie(name, value, skipSetDomain)` | Cookie access that respects the store's cookie config (`COOKIE_CONFIG` from `variables.phtml`). |
| `hyva.getBrowserStorage()` | `localStorage`, falling back to `sessionStorage`; `false` (with a console warning) when neither is usable — always check the return value. |
| `hyva.formatPrice(value, showSign, options)` | `Intl.NumberFormat` in the store locale and current currency; `options` are Intl options plus `groupSeparator`/`decimalSeparator`. |
| `hyva.postForm({ action, data, skipUenc })` | Builds and submits a hidden POST form with `form_key` and `uenc` added — the replacement for Luma `data-post` links (add to cart, wishlist, compare). |
| `hyva.getUenc()` | `window.location.href` base64-encoded the way `Magento\Framework\Url\Encoder` expects for `uenc` redirect params. |
| `hyva.str('%1 of %2', a, b)` / `hyva.strf` | Positional placeholder replacement (`%1`-based / `%0`-based). |
| `hyva.replaceDomElement(selector, html)`, `hyva.activateScripts(node)` | Swap in fetched HTML and execute the `<script>` tags it contains (plain `innerHTML` does not run them). |
| `hyva.trapFocus(el)` / `hyva.releaseFocus(el)` | Keyboard focus containment for modals and drawers. |
| `hyva.alpineInitialized(fn)` | Run once Alpine has started (used by `private-content.phtml` itself). |
| `hyva.createBooleanObject(name, initial, extra)`, `hyva.safeParseNumber(v)` | CSP-friendly toggle objects; numeric coercion for inputs. |
| `window.dispatchMessages([{ type: 'success', text }], 2000)` | Show a Magento-style message (types `success`, `notice`, `warning`, `error`); duration optional. |

Globals from `Hyva_Theme::page/js/variables.phtml`: `BASE_URL`, `CURRENT_STORE_CODE`, `COOKIE_CONFIG`. There is no `mage/url`, `mage/translate` or `mage/template`: build URLs server-side (`'<?= $escaper->escapeJs($block->getUrl('acme/notice/dismiss')) ?>'` or `BASE_URL + 'acme/notice/dismiss'`), translate with `__()` in PHP, and render markup with `<template>` elements or `hyva.replaceDomElement`.

`fetch()` against Magento controllers (docs pattern): JSON — `fetch(url + '?form_key=' + hyva.getFormKey(), { method: 'post', body: JSON.stringify(data), headers: { 'Content-Type': 'application/json' } })`; form — `fetch(url, { method: 'post', body: new URLSearchParams({ form_key: hyva.getFormKey(), sku }), headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' } })`. Add `'X-Requested-With': 'XMLHttpRequest'` when the response must keep the customer session personalised (the page-cache depersonalise plugin skips XHR requests). The controller side is `magento:module` (S2: `HttpPostActionInterface`).

## Hyvä events

Dispatched and listened to on `window`; the docs list is not exhaustive.

| Event | Direction | Notes |
|---|---|---|
| `private-content-loaded` | Hyvä → you | `event.detail.data` = all customer sections (`cart`, `customer`, `messages`, `wishlist`, …). Fired after every page load once section data is available and after every reload. |
| `reload-customer-section-data` | you → Hyvä | Re-runs section loading; dispatch after a `fetch()` that changed the cart/customer. No automatic reload exists. |
| `toggle-cart` | you → Hyvä | Opens the cart drawer; `{ detail: { isOpen: false } }` closes it (1.3.0+). |
| `toggle-authentication` | you → Hyvä | Login slider or redirect to checkout; `{ detail: { url } }` sets the redirect. |
| `toggle-mobile-menu`, `clear-messages` | you → Hyvä | Mobile nav overlay; remove splash messages (1.1.2+). |
| `configurable-selection-changed`, `listing-configurable-selection-changed` | Hyvä → you | `{ productId, optionId, value, productIndex, selectedValues, candidates }` on PDP / listing swatch changes. |
| `update-product-final-price`, `update-prices-<productId>`, `update-qty-<productId>`, `update-gallery` | both | PDP price, quantity and gallery plumbing (see the PDP pricing page before touching prices). |
| `alpine:init`, `alpine:initialized` | Alpine → you | Register `Alpine.data`/`Alpine.store` in the first, run post-start code in the second. |

## Private content — customer section data (H4, P3)

Mechanics, from `Hyva_Theme::page/js/private-content.phtml` (block `script-private-content`, `before.body.end`):

1. After Alpine initialises (and on every `reload-customer-section-data`), `loadSectionData()` compares the `private_content_version` cookie with the copy in `hyva.getBrowserStorage()` and checks the `mage-cache-sessid` cookie, the `last_visited_store` cookie against `CURRENT_STORE_CODE`, and the `mage-cache-timeout` expiry (cookie lifetime from `web/cookie/cookie_lifetime`, default 3600 s).
2. If anything is stale it `fetch()`es `customer/section/load/?sections=` (all sections, `X-Requested-With: XMLHttpRequest`), merges the result into `mage-cache-storage`, and dispatches `private-content-loaded`; otherwise it dispatches the stored data. A page with no cookie yet dispatches the server-rendered `#default-section-data` JSON (block `default-section-data`).
3. Magento sets a fresh `private_content_version` cookie on every POST response (`Magento\Framework\App\PageCache\Version::process`), and clears `mage-cache-sessid` on login/logout — so a normal form POST followed by a page load refetches automatically; a `fetch()` POST gets the new cookie too but nothing re-runs `loadSectionData()` until you dispatch `reload-customer-section-data`. `window.processSectionDataBeforeDispatch` can wrap the payload before dispatch (rarely needed).

Consuming it in a template:

```php
<div x-data="{ count: 0 }"
     @private-content-loaded.window="count = $event.detail.data.cart?.summary_count ?? 0">
    <span x-text="count"></span>
</div>
```

All sections arrive together — there is no per-section subscription — and they are plain objects, not observables: only the next `private-content-loaded` updates your state. Keep the page cacheable (no `cacheable="false"`) and render only the neutral markup server-side; Hyvä's own header does exactly this for the cart counter and customer name.

Adding a section (Magento-side, same as Luma; Hyvä reads whatever `customer/section/load` returns):

```xml
<!-- app/code/Acme/Catalog/etc/frontend/di.xml -->
<type name="Magento\Customer\CustomerData\SectionPoolInterface">
    <arguments>
        <argument name="sectionSourceMap" xsi:type="array">
            <item name="acme-loyalty" xsi:type="string">Acme\Catalog\CustomerData\Loyalty</item>
        </argument>
    </arguments>
</type>
```

`Acme\Catalog\CustomerData\Loyalty implements Magento\Customer\CustomerData\SectionSourceInterface` returns an array from `getSectionData()`; `etc/frontend/sections.xml` (`<action name="acme/loyalty/redeem"><section name="acme-loyalty"/></action>`) still matters for Luma store views and the Luma-fallback checkout, but on Hyvä you trigger the reload yourself after the POST. Invalidate without reloading: `hyva.getBrowserStorage().removeItem('mage-cache-storage')`; force a full refetch: `hyva.setCookie('mage-cache-sessid', '', -1, true)` then dispatch `reload-customer-section-data`.

## ViewModels and icons (H4)

Every Hyvä template receives `$viewModels` (`Hyva\Theme\Model\ViewModelRegistry`) next to `$block` and `$escaper`; `$viewModels->require(Some\ViewModel::class)` returns the shared instance of any class implementing `Magento\Framework\View\Element\Block\ArgumentInterface` — no layout XML argument needed (the layout `view_model` argument still works and is what a module shared with Luma should use). Pass `$block` as the second argument only for cache-tagged ViewModels (`IdentityInterface`) used inside `ttl="…"` ESI blocks — Hyvä's menu templates are the only core case. Frequently used: `Hyva\Theme\ViewModel\CurrentProduct`, `CurrentCategory`, `ProductPrice`, `ProductPage`, `ProductListItem`, `StoreConfig`, `Store`, `Customer`, `Modal`, `Navigation`, `HyvaCsp`, `BlockJsDependencies`, `SvgIcons`, `HeroiconsOutline`, `HeroiconsSolid`, `LucideIcons`.

Icons render inline SVG (cached, with an accessible `<title>` unless `aria-hidden`/`role` is set, 1.3.0+):

```php
$heroicons = $viewModels->require(\Hyva\Theme\ViewModel\HeroiconsOutline::class);
echo $heroicons->shoppingCartHtml('w-6 h-6', 24, 24, ['aria-hidden' => 'true']);   // camelCased file name + Html
$icons = $viewModels->require(\Hyva\Theme\ViewModel\SvgIcons::class);
echo $icons->renderHtml('acme/logo-mark', 'h-8', null, null);                        // Hyva_Theme/web/svg/acme/logo-mark.svg in the theme
```

Signature everywhere: `(string $classnames = '', ?int $width = 24, ?int $height = 24, array $attributes = [])`; the `…Html` suffix marks the output as safe for the XSS sniff. Icon sets are `SvgIcons` instances configured with `iconPathPrefix` in `di.xml` (`Hyva_Theme::svg/heroicons/outline`), so a theme overrides an icon by mirroring `Hyva_Theme/web/svg/heroicons/outline/x.svg`, and a module can declare its own set with a virtual type. Heroicons v2 and Lucide are separate packages/ViewModels; CMS content uses `{{icon "heroicons/outline/x" classes="w-4 h-4"}}`.

## Debugging

- Class has no effect: search `web/css/styles.css` for it. Absent → not scanned (path outside `content`/`@source`, dynamic name, `.gitignore` on 1.4) or not rebuilt; present → specificity or an `@apply` component rule overriding it.
- `Alpine Expression Error` in the console: a PHP value broke the JS (escape with `escapeJs`), or the component uses a CSP-only/JS-only syntax for the theme variant in use.
- `require is not defined` / `$ is not defined`: Luma JS reached the page — a third-party template or a copied Luma snippet; find the block with `bin/magento dev:template-hints:enable` and replace it or add a compat module (`hyva-compat.md`).
- Section data never updates after your `fetch()`: you did not dispatch `reload-customer-section-data`, or the request was not a POST (no new `private_content_version` cookie) — call `hyva.getBrowserStorage().removeItem('mage-cache-storage')` before dispatching.
- Nothing changed after editing a template or layout: `bin/magento cache:clean layout block_html full_page`; in production also redeploy static content for CSS.

## Sources

- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/index.html — Working with Tailwind CSS (Tailwind 3 on 1.2–1.3, Tailwind 4 on 1.4+; sub-page index)
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/supported-versions.html — Tailwind versions per Hyvä release
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/generating-css.html — `npm ci --ignore-scripts`, `build`, `watch`, `start`, `--prefix`, Node versions per release, `build-prod`/`build-dev` history
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/hyva-theme-css-files.html — 1.4 `web/tailwind` layout (`base`, `components`, `generated`, `utilities`, `theme`)
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/tailwind-purging-settings.html — `content` example, manual vs `hyva-themes.json` module paths, `@source` lines in `tailwind-source.css`
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/using-hyva-modules/index.html — `mergeTailwindConfig`, `postcssImportHyvaModules` (order), `npx hyva-sources`, `hyva.config.json` include/exclude, `hyva-tokens`, fallback utilities
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/using-hyva-modules/fallback.html — v3 utilities re-added for compatibility and their v4 equivalents
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/dynamic-tailwind-classes.html — why dynamic classes are missing; PHP-comment and CSS-variable workarounds
- https://docs.hyva.io/hyva-themes/working-with-tailwindcss/troubleshooting.html — `@import` relative paths, `@screen` removed in v4, `.gitignore` vs `@source`
- https://docs.hyva.io/hyva-themes/building-your-theme/index.html — child theme: copy `web/`, `hyva.config.json` parent include, the 1.3 `content` block with parent-theme and `app/code` globs, `npm run build`
- https://docs.hyva.io/hyva-themes/building-your-theme/styling-layout-containers.html — `htmlClass` Tailwind classes, the `htmlClassType` XSD pattern, `theme/page-layout.css` with `@apply`
- https://docs.hyva.io/hyva-themes/building-your-theme/deploying-hyva-to-production.html — build on CI, `npm ci --ignore-scripts`, `setup:static-content:deploy --no-less --no-js-bundle --no-html-minify`, `build-prod` history
- https://docs.hyva.io/hyva-themes/working-with-alpinejs/index.html — Alpine 3 on 1.2+ (Alpine 2 on 1.0–1.1); https://docs.hyva.io/hyva-themes/working-with-alpinejs/alpine-plugins/index.html — `x-intersect`, `x-ignore`, `x-defer`, `x-snap-slider`, `x-htmldialog`
- https://docs.hyva.io/hyva-themes/writing-code/the-window-hyva-object.html — every `hyva.*` helper and signature
- https://docs.hyva.io/hyva-themes/writing-code/hyva-javascript-events.html — `private-content-loaded`, `reload-customer-section-data`, `toggle-cart`, `toggle-authentication`, `toggle-mobile-menu`, `clear-messages`, PDP events
- https://docs.hyva.io/hyva-themes/writing-code/working-with-sectiondata.html — section data lifecycle, storage keys, cookies, forced reload, "no per-section subscription"
- https://docs.hyva.io/hyva-themes/writing-code/working-with-view-models/index.html — `$viewModels->require()`, `$block` second argument for ESI blocks, `IdentityInterface` cache tags
- https://docs.hyva.io/hyva-themes/writing-code/working-with-view-models/svgicons.html — `SvgIcons::renderHtml`, `…Html()` naming, signature, a11y `<title>` (1.3.0+)
- https://docs.hyva.io/hyva-themes/view-utilities/hyva-svg-icon-modules/heroicons.html — Heroicons v1 bundled, Heroicons v2 package, `{{icon}}` CMS directive
- https://docs.hyva.io/hyva-themes/writing-code/csp/index.html and https://docs.hyva.io/hyva-themes/writing-code/csp/csp-compatibility.html — Alpine CSP build, `$hyvaCsp->registerInlineScript()` placement, `$hyvaCsp` availability
- https://docs.hyva.io/hyva-themes/writing-code/rendering-javascript-once.html — `hyva_js_block_dependencies`, `BlockJsDependencies::setBlockNameDependency` (1.3.6+), `block_html` caveat
- https://docs.hyva.io/hyva-themes/writing-code/using-fetch.html — `fetch()` GET/POST patterns with `hyva.getFormKey()`; https://docs.hyva.io/hyva-themes/writing-code/window-dispatchmessages.html — `dispatchMessages()`
- https://github.com/hyva-themes/magento2-theme-module — `src/view/frontend/templates/page/js/hyva.phtml` (helper definitions), `private-content.phtml` (storage keys, cookies, `customer/section/load`, event dispatch), `variables.phtml` (`BASE_URL`, `CURRENT_STORE_CODE`), `layout/default_hyva.xml` (`head.additional` / `before.body.end` blocks), `ViewModel/*` (registry, icons), `view/base/web/js/alpine3.min.js` (Alpine 3.14 in 1.5.2; `.away` still handled); tags 1.3.22 and 1.5.2
- https://github.com/hyva-themes/magento2-default-theme — `web/tailwind/` at tags 1.2.0, 1.3.22, 1.4.0–1.4.10, 1.5.2 (`package.json` scripts, `tailwind.config.js` content and theme names, `tailwind-source.css`, `hyva.config.json`, `[x-cloak]` rule), `Magento_Theme/page_layout/override/base/1column.xml`
- https://v3.tailwindcss.com/docs/content-configuration — `content` paths relative to the working directory, complete-string rule, `safelist`; https://v3.tailwindcss.com/docs/theme — `theme.extend` vs replace; https://v3.tailwindcss.com/docs/dark-mode — `darkMode: 'selector'`
- https://tailwindcss.com/docs/detecting-classes-in-source-files — plain-text scanning, `@source`, `source(none)`, `.gitignore`, `@source inline()`; https://tailwindcss.com/docs/theme — `@theme` namespaces; https://tailwindcss.com/docs/dark-mode — `@custom-variant dark`; https://tailwindcss.com/docs/functions-and-directives — `@apply`, `@config`, `@variant`
- https://alpinejs.dev/directives/data, https://alpinejs.dev/directives/show, https://alpinejs.dev/directives/cloak, https://alpinejs.dev/directives/on, https://alpinejs.dev/directives/if, https://alpinejs.dev/directives/for, https://alpinejs.dev/directives/ref, https://alpinejs.dev/directives/init, https://alpinejs.dev/globals/alpine-data, https://alpinejs.dev/globals/alpine-store, https://alpinejs.dev/magics/dispatch — Alpine 3 directive semantics (`.outside`, `.window`, `x-cloak` CSS, `<template>` roots)
- Magento source (local `vendor/`, 2.4.9): `Magento\Framework\App\PageCache\Version::process` (new `private_content_version` cookie on every POST), `Magento\Customer\CustomerData\SectionPool` `sectionSourceMap`, `Magento_Customer/etc/frontend/sections.xml`, `app/etc/di.xml` `developerMaterialization` (symlink strategy in developer mode), `Magento\Developer` `dev:template-hints:enable`; `lib/internal/Magento/Framework/View/Layout/etc/elements.xsd` `htmlClassType` at tags 2.4.4, 2.4.6, 2.4.7 on github.com/magento/magento2
