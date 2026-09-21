---
name: frontend-luma
description: Magento 2 Luma/blank-based storefront work — theme structure, layout XML, .phtml templates with escaping, ViewModels, RequireJS/Knockout/UI components, LESS and static content deploy. Use for frontend changes on Magento Open Source 2.4 themes that inherit from Magento/luma or Magento/blank (not Hyvä).
---

# Magento 2 Luma storefront

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).*

*Not for Hyvä* — if the theme's parent chain reaches `Hyva/default` or `hyva-themes/*` is installed, use `magekwik-magento:frontend-hyva`. Check `.claude/rules/magento.md`/`CLAUDE.md` facts from `/magekwik-magento:init`, or `app/design/frontend/*/*/theme.xml`.

Rules: see `magekwik-magento:conventions` L1–L5, S3, P3. This skill cites them by ID and does not restate them.

## When to use

- Adding, moving, removing or restyling something on a storefront page of a theme whose `theme.xml` `<parent>` chain ends in `Magento/luma` or `Magento/blank`.
- Overriding a core `.phtml` template, or giving a template data through a ViewModel.
- Storefront JavaScript: RequireJS modules, jQuery UI widgets, Knockout/UI components, mixins on core widgets, customer-data sections.
- Theme LESS (`_extend.less`, `_theme.less`, module `_module.less`), grunt, static content deploy and "my change does not show up" problems.
- Creating a new theme under `app/design/frontend/<Vendor>/<theme>`.

## When not to

- The theme is Hyvä (Alpine.js/Tailwind, no RequireJS) → `magekwik-magento:frontend-hyva`.
- Backend behaviour the frontend calls (plugins, observers, `di.xml`, controllers, ACL) → `magekwik-magento:module`.
- Data the ViewModel needs from the database (repositories, collections, EAV attributes) → `magekwik-magento:data`.
- REST/GraphQL endpoints a JS component calls → `magekwik-magento:api`.
- Admin UI grids and forms (`ui_component` XML) — not covered here.

## Decision guide

| Need | Use | Reference |
|---|---|---|
| Add, move or remove something on a page | Layout XML in the theme: `<Vendor>_<Module>/layout/<handle>.xml` (or module `view/frontend/layout/`) with `referenceContainer`/`referenceBlock`/`move` (L1) | `layout-xml.md` |
| Change the markup a core block prints | Template override in the theme: `<Vendor>_<Module>/templates/<same path>.phtml` — only when layout XML cannot do it (L1) | `templates-and-escaping.md` |
| Data or presentation logic for a template | ViewModel implementing `ArgumentInterface`, passed via `<argument name="view_model" xsi:type="object">` (L2) | `templates-and-escaping.md` |
| Find which template/block renders something | `bin/magento dev:template-hints:enable && bin/magento cache:clean config full_page` (developer mode) | `templates-and-escaping.md` |
| Behaviour on the page | RequireJS module in `web/js/`, initialised with `x-magento-init` or `data-mage-init` (L3) | `requirejs-knockout.md` |
| Change what a core widget/component does | Mixin declared in `requirejs-config.js` `config.mixins` (L3) | `requirejs-knockout.md` |
| Styling | Theme `web/css/source/_extend.less`; variables in `_theme.less`; module styles in `<Vendor>_<Module>/web/css/source/_module.less` (L4) | `less.md` |
| Per-customer content on a cacheable page | Customer-data section (`etc/frontend/sections.xml` + `SectionSourceInterface`) rendered with Knockout — never `cacheable="false"` (P3) | `requirejs-knockout.md` |
| Styles or JS do not update | Developer mode: delete the theme's `pub/static/frontend/<Vendor>/<theme>/<locale>` and `var/view_preprocessed`, or `grunt exec:<theme> && grunt less:<theme>`; production: `setup:static-content:deploy` (L5) | `less.md` |

Two quick tests: *"Can I do it by referencing an existing block or container?"* → layout XML, no template. *"Does the template need anything beyond `$block` data?"* → ViewModel, not a custom Block class and not a helper.

## Rules that bite

1. **L1** — Handle = file name. `default.xml` merges into every page; a page's own handle is its lowercased full action name (`catalog_product_view`, `catalog_category_view`, `cms_index_index`, `checkout_index_index`, `checkout_cart_index`, `customer_account_index`); entity handles are added on top (`catalog_product_view_type_configurable`, `catalog_product_view_id_42`, `catalog_product_view_sku_ABC`, `catalog_category_view_id_7`, `cms_page_view_id_about-us`). `<update handle="customer_account"/>` pulls another handle in. Merge order: module files, then each theme from `Magento/blank` down to yours, so your theme file wins.
2. **L1** — Target the real container names from `Magento_Theme/view/frontend/layout/default.xml` and the page layouts: `after.body.start`, `header.container`, `header.panel`, `header-wrapper`, `page.top`, `top.container`, `columns.top`, `page.messages`, `content.top`, `content`, `content.bottom`, `sidebar.main`, `sidebar.additional`, `page.bottom`, `footer`, `before.body.end`. A `referenceContainer` to a name that does not exist drops your block silently (developer mode logs "Broken reference … doesn't exist" at info level).
3. **L1** — Reposition with `<move element="x" destination="y" before|after="z"/>`; `before="-"`/`after="-"` mean first/last among siblings, and ordering against an element with a different parent is ignored. Remove with `<referenceBlock name="x" remove="true"/>` (children go too; a later file's `remove="false"` cancels it); `display="false"` hides the output but keeps the block object for `getChildHtml()` callers. `<remove>` as an element only works inside `<head>` for assets.
4. **L1** — `ifconfig="section/group/field"` is allowed on `<block>`, `<uiComponent>` and `<action>` only; it is evaluated with `isSetFlag()` at store scope and a false value removes the block and its children. It is not valid on `<container>` or `<referenceBlock>`, and the merged layout is schema-validated only in developer mode, so an attribute the XSD does not allow throws there and is silently ignored (not validated, not logged) in default and production mode.
5. **L2** — `<argument name="view_model" xsi:type="object">` is instantiated by the object manager and must implement `Magento\Framework\View\Element\Block\ArgumentInterface`, otherwise block generation throws `Instance of … ArgumentInterface is expected` (developer mode) or logs it and renders nothing (production). The instance is a shared singleton unless the argument has `shared="false"`: constructor-inject services, keep no per-request state in properties. Read it with `$block->getData('view_model')` — the magic `$block->getViewModel()` is the same `DataObject::__call` lookup and works too, but the explicit form is what the docblock and the coding standard's examples use; leave `class` off the `<block>` so it stays `Magento\Framework\View\Element\Template`.
6. **S3** — `$escaper->escapeHtml()` for text nodes, `escapeHtmlAttr()` inside attribute values, `escapeUrl()` for `href`/`src`, `escapeJs()` inside JS string literals, `escapeCss()` inside `style`. `__()` returns a `Phrase` that still needs escaping. `$block->escapeHtml()` and friends are deprecated since framework 103.0.0 (2.4.0) — use the `$escaper` the template engine injects. `/* @noEscape */` is only for values that are already HTML (methods with `Html` in the name — `getChildHtml()`, `toHtml()` — count as safe for the sniff).
7. **L2** — Templates use `$block` and `$escaper` only: no `$this`, no `$this->helper()`, no `ObjectManager`. Links come from `$block->getUrl('route/controller/action', ['_secure' => true])`, assets from `$block->getViewFileUrl('Acme_Catalog::images/x.svg')`, children from `$block->getChildHtml('alias')`. Always write the template attribute as `Vendor_Module::path/file.phtml`; without the prefix the path is resolved against the block class's module, which for the default `Template` class is the theme-root `templates/` directory.
8. **L3** — `<script type="text/x-magento-init">` holds one JSON object: `{"<css selector>|*": {"<RequireJS module id>": {config}}}`. It is parsed with `JSON.parse` in one pass over the page, so a trailing comma or an unescaped quote in any block aborts the pass and leaves every declarative component on the page uninitialised. The module id must resolve to a file (`Acme_Catalog/js/notice` → `view/frontend/web/js/notice.js` or the theme's `Acme_Catalog/web/js/notice.js`) and return `function (config, element)`, a jQuery widget (`$.widget('acme.notice', {...}); return $.acme.notice;`) or an object keyed by the module id. HTML injected by AJAX is initialised again with `$(el).trigger('contentUpdated')`.
9. **L3** — `requirejs-config.js` (module `view/frontend/`, theme root, or theme `<Vendor>_<Module>/`) declares `var config = { map: {'*': {...}}, paths, shim, deps, config: { mixins, text } }`; every file is wrapped in `require.config(config)` and merged module → parent theme → theme. Mixin keys are module ids without `.js`; a mixin is `return function (target) { … return target; }` and only applies to modules that return a function or object. Developer mode regenerates the merged `requirejs-config.js` on every request; default and production modes write it only when it is missing, so delete it or redeploy after editing.
10. **L4** — Theme `web/css/source/_extend.less` adds rules; `_theme.less` is for variable overrides and *replaces* Luma's `_theme.less` outright, so copy the declarations you keep. Wrap common rules in `& when (@media-common = true) { … }` and breakpoint rules in `.media-width(@extremum, @break) when (@extremum = 'min') and (@break = @screen__m) { … }`; rules left outside both are compiled into `styles-m.css` *and* `styles-l.css`. Use the lib mixins and variables (`.lib-css()`, `.lib-font-size()`, `.lib-button()`, `@indent__s`, `@screen__m`, `@primary__color`); no inline styles.
11. **L5** — Developer and default modes materialise static files on first request: JS, images and `.html` templates are symlinked into `pub/static`, compiled CSS is copied, and an existing file is never regenerated. So a LESS edit does not show until `pub/static/frontend/<Vendor>/<theme>/<locale>/css` and `var/view_preprocessed` are deleted — or you run `grunt exec:<theme>` then `grunt less:<theme>` (`grunt watch` afterwards). Production mode never generates on demand (unless `static_content_on_demand_in_production` is set in `env.php`): run `bin/magento setup:static-content:deploy --theme Acme/default en_US` (add `-f` only in developer/default mode) and never commit `pub/static`, `var/view_preprocessed` or `generated/`. Minification is ignored in developer mode whatever the config says.
12. **P3** — One `<block cacheable="false">` anywhere in the merged layout makes `Layout::isCacheable()` false and the whole page uncacheable. Per-customer fragments go through customer-data sections (`etc/frontend/sections.xml`, `SectionSourceInterface`, `customerData.get('cart')` in Knockout); `ttl="3600"` on a block only creates an ESI hole when Varnish is the FPC backend. After changing layout XML or templates: `bin/magento cache:clean layout block_html full_page`.

## Minimal correct example

A "free shipping" notice at the top of every page of `Acme/default`, with the threshold coming from a ViewModel.

`app/design/frontend/Acme/default/Magento_Theme/layout/default.xml`:

```xml
<?xml version="1.0"?>
<page xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:View/Layout/etc/page_configuration.xsd">
    <body>
        <referenceContainer name="page.top">
            <block name="acme.shipping.notice" template="Magento_Theme::acme/shipping-notice.phtml" before="-">
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

`app/design/frontend/Acme/default/Magento_Theme/templates/acme/shipping-notice.phtml`:

```php
<?php
/** @var \Magento\Framework\View\Element\Template $block */
/** @var \Magento\Framework\Escaper $escaper */
/** @var \Acme\Catalog\ViewModel\ShippingNotice $viewModel */
$viewModel = $block->getData('view_model');
?>
<div class="acme-shipping-notice">
    <?= $escaper->escapeHtml(__('Free shipping on orders over %1', $viewModel->getThreshold())) ?>
</div>
```

Why this shape: `default.xml` in the theme's `Magento_Theme` directory is merged into every storefront page after the module and parent-theme files (rule 1); `page.top` is the container Luma renders right after the header, and it already holds `navigation.sections` (the menu) and `breadcrumbs` — `before="-"` is what puts the notice first, above the menu (rules 2–3). The block has no `class`, so it is a plain `Template`, and everything the template needs comes from the ViewModel argument (rule 5) — the threshold can later be read from `ScopeConfigInterface` (conventions A10) without touching the template. The template only uses `$block` and `$escaper`, and escapes the translated `Phrase` (rules 6–7). Nothing is `cacheable="false"`, so full-page cache keeps working (rule 12); the notice is the same for every visitor, so no customer-data section is needed. Style it in `app/design/frontend/Acme/default/web/css/source/_extend.less` (rule 10), then in developer mode delete `pub/static/frontend/Acme/default/en_US/css` and `var/view_preprocessed` and run `bin/magento cache:clean layout block_html full_page`.

## Routing table

| For | Read |
|---|---|
| Layout file types and locations, handles and how they are resolved, containers vs blocks, every `referenceBlock`/`referenceContainer`/`block`/`container`/`move` attribute, argument `xsi:type`s, `ifconfig`, `<head>` and `<body>`, `cacheable`/`ttl`, container names, override directories, merge order, template hints and layout debugging | `references/layout-xml.md` |
| Template fallback and override paths, `$block` API, ViewModels, the `Escaper` methods and when each applies, `__()`, `getChildHtml`, `getUrl`, `getViewFileUrl`, docblocks, `data-mage-init` vs `x-magento-init`, `_toHtml`, CSP and inline scripts, PHPCS template sniffs | `references/templates-and-escaping.md` |
| `requirejs-config.js` keys, `define()` modules, `x-magento-init` shape, jQuery UI widgets, mixins, Knockout/UI components and `.html` templates, custom bindings, customer-data sections and invalidation, `mage/translate` and `js-translation.json`, `mage/template`, bundling and minification, debugging RequireJS errors | `references/requirejs-knockout.md` |
| Theme structure, `styles-m.less`/`styles-l.less`, `_theme.less`/`_extend.less`/`_module.less`, `@magento_import`, UI library mixins and variables, `.media-width()`, grunt setup and tasks, server- vs client-side compilation, static content deploy and materialisation, what to delete when styles do not update | `references/less.md` |
