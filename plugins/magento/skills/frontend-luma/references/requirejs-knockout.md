# RequireJS, jQuery widgets, Knockout/UI components and customer-data

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magekwik-magento:conventions` (L3 and P3 apply throughout).

Luma's JavaScript is AMD modules loaded by RequireJS (`requirejs/require.js`, `baseUrl` = the theme's `pub/static/frontend/<Vendor>/<theme>/<locale>/`), jQuery + jQuery UI widgets for behaviour, Knockout for reactive components (`Magento_Ui`), and `Magento_Customer/js/customer-data` for anything that differs per visitor on a cached page. No script tags with global code: every piece of behaviour is a module and is started declaratively (L3).

## Where modules live and how they are named

| File | Module id |
|---|---|
| `app/code/Acme/Catalog/view/frontend/web/js/notice.js` | `Acme_Catalog/js/notice` |
| `app/design/frontend/Acme/default/Acme_Catalog/web/js/notice.js` | `Acme_Catalog/js/notice` (overrides the module file for this theme) |
| `app/design/frontend/Acme/default/web/js/theme-thing.js` | `js/theme-thing` |
| `lib/web/mage/sticky.js` | `mage/sticky` |
| `app/code/Acme/Catalog/view/frontend/web/template/notice.html` | Knockout template `Acme_Catalog/notice` |

Module ids never carry `.js`. Static resolution goes theme → parent themes → module `view/frontend/web` → `view/base/web` → `lib/web`, so a theme can override any core file by mirroring its path.

## `requirejs-config.js`

Every module (`view/frontend/requirejs-config.js`, `view/base/requirejs-config.js`), theme (`<theme_dir>/requirejs-config.js`) and theme-module directory (`<theme_dir>/<Vendor>_<Module>/requirejs-config.js`) may declare one. Each is wrapped in `(function(){ … require.config(config); })();` and concatenated in the order modules (by `<sequence>`) → `Magento/blank` → `Magento/luma` → your theme into `pub/static/frontend/<Vendor>/<theme>/<locale>/requirejs-config.js`, so the variable **must** be named `config`:

```js
var config = {
    map: {
        '*': {
            acmeNotice: 'Acme_Catalog/js/notice',                       // alias usable in x-magento-init
            'Magento_Checkout/js/view/minicart': 'Acme_Catalog/js/view/minicart' // replace a core module everywhere
        },
        'Acme_Catalog/js/other': { helper: 'Acme_Catalog/js/helper-v2' }   // alias only inside that module
    },
    paths: {
        'acme/vendor-lib': 'Acme_Catalog/js/lib/vendor-lib.min'            // any file/URL, HTML templates too
    },
    shim: {
        'acme/vendor-lib': { deps: ['jquery'], exports: 'VendorLib' }       // non-AMD script: what it needs, what it defines
    },
    deps: ['Acme_Catalog/js/always'],                                       // loaded on every page — keep it empty unless you mean it
    config: {
        mixins: {
            'Magento_Checkout/js/view/shipping': { 'Acme_Catalog/js/view/shipping-mixin': true },
            'mage/collapsible': { 'Acme_Catalog/js/collapsible-mixin': true }
        },
        text: { headers: { 'X-Requested-With': 'XMLHttpRequest' } }        // text! plugin request headers
    }
};
```

- `map` `'*'` replaces a module id for every requester — the way to swap a core component for yours. A `map` entry keyed by a module id applies only when that module requires the alias. To *extend* a core module instead of replacing it, use a mixin.
- `paths` is for files, not ids: use it for third-party libraries and for pointing an id at a `.min` build.
- `shim` is only for scripts that do not call `define()`; `deps` lists what to load first, `exports` the global they create.
- `deps` at the top level loads modules on every page — `Magento_Theme` uses it for `mage/common`, `mage/dataPost`, `mage/bootstrap`. Do not put page-specific components there.
- Developer mode rewrites the merged `requirejs-config.js` on every request; default and production write it only when the file is missing, so after editing any `requirejs-config.js` delete `pub/static/frontend/<Vendor>/<theme>/<locale>/requirejs-config.js` (developer/default) or redeploy static content (production), then `bin/magento cache:clean full_page`.

Core aliases you will meet: `jquery`, `jquery/ui` (loads all of jQuery UI — prefer `jquery-ui-modules/widget`, `jquery-ui-modules/dialog`, …), `ko`/`knockout`, `underscore`, `uiComponent` (`Magento_Ui/js/lib/core/collection`), `uiElement`, `uiRegistry`, `uiLayout`, `mage/translate`, `mage/template`, `mage/url`, `mage/storage`, `mage/cookies`, `Magento_Customer/js/customer-data`, `Magento_Ui/js/modal/modal`, `Magento_Ui/js/modal/alert`, `Magento_Ui/js/modal/confirm`, `domReady!`, `text!`.

## Writing a module

A plain component receives the config from `x-magento-init`/`data-mage-init` and the element:

```js
define(['jquery', 'mage/translate'], function ($) {
    'use strict';

    return function (config, element) {
        var $el = $(element),
            delay = config.delay || 3000;

        $el.on('click', '.action.close', function () {
            $el.slideUp(delay);
        });
        $el.attr('title', $.mage.__('Close'));
    };
});
```

A jQuery UI widget, initialised the same way but by widget name:

```js
define(['jquery', 'jquery-ui-modules/widget'], function ($) {
    'use strict';

    $.widget('acme.notice', {
        options: { delay: 3000 },

        _create: function () {
            this._on(this.element, { 'click .action.close': '_close' });
        },

        _close: function () {
            this.element.slideUp(this.options.delay);
        }
    });

    return $.acme.notice;
});
```

Because the module returns the widget constructor, `"Acme_Catalog/js/notice": {...}` in `x-magento-init` calls it with `(config, element)`, which jQuery UI turns into `new` + `_createWidget(config, element)` — the same as `$(element).notice(config)`; the widget is also callable by name once its module has loaded. Core widgets live under `$.mage.*` (`mage/menu`, `mage/collapsible`, `mage/sticky`, `mage/tabs`, `mage/loader`, `mage/validation`).

## Declarative initialisation

```html
<div class="acme-notice" data-mage-init='{"Acme_Catalog/js/notice": {"delay": 500}}'>…</div>

<script type="text/x-magento-init">
{
    ".acme-notice": { "Acme_Catalog/js/notice": {"delay": 500}, "collapsible": {"active": true} },
    "*": { "Magento_Ui/js/core/app": { "components": { "acme-notice": { "component": "Acme_Catalog/js/view/notice" } } } }
}
</script>
```

`mage/apply/main` (run by `mage/bootstrap` on DOM ready) collects every `data-mage-init` attribute and `x-magento-init` script, `JSON.parse`s them in one pass (invalid JSON in any block throws — `SyntaxError` in the console — and aborts the pass, so every declarative component on the page stays uninitialised), and for each `{selector: {moduleId: config}}` pair `require`s the module and calls it with `(config, element)` — or, if the module returned an object with a key equal to the module id, that function; or, if `$(element)[moduleId]` exists, the jQuery widget. `"*"` initialises with `element === false`. A failed `require` (typo in the id, file missing from `pub/static`) logs `Script error for "Acme_Catalog/js/notice"` and the rest still runs. Markup added later must be re-scanned with `$(container).trigger('contentUpdated')`. Imperative `require(['Acme_Catalog/js/notice'], function (notice) { … })` in a `<script>` is allowed for one-off page code but is inline JavaScript for CSP purposes — see `templates-and-escaping.md`.

## Mixins

A mixin wraps a module's export without copying the file (A2 for JavaScript). Declared in `requirejs-config.js` `config.mixins` keyed by the *target* id (no `.js`, no `map` alias), the mixin module receives the original export and must return the replacement:

```js
// Acme_Catalog/js/view/shipping-mixin.js — a UI component
define([], function () {
    'use strict';

    return function (Shipping) {
        return Shipping.extend({
            defaults: { template: 'Acme_Catalog/checkout/shipping' },

            validateShippingInformation: function () {
                return this._super() && window.acmeNoticeAccepted === true;
            }
        });
    };
});

// Acme_Catalog/js/collapsible-mixin.js — a jQuery widget (mage/collapsible returns $.mage.collapsible)
define(['jquery'], function ($) {
    'use strict';

    return function (collapsibleWidget) {
        $.widget('mage.collapsible', collapsibleWidget, {
            _create: function () {
                this._super();
                this.element.addClass('acme-collapsible');
            }
        });

        return $.mage.collapsible;
    };
});
```

Plain functions and objects are wrapped with `mage/utils/wrapper` (`wrapper.wrap(target, function (original, ...args) {…})`, `wrapper.wrapSuper`). Check what the target actually exports before choosing the pattern: most core widgets return their constructor (`return $.mage.collapsible;`), but `mage/menu` returns `{ menu: $.mage.menu, navigation: $.mage.navigation }`, so a menu mixin receives that object — extend `target.menu`/`target.navigation` with `$.widget('mage.menu', target.menu, {…})` and return the object with both keys replaced, or jQuery UI throws on the plain object. Mixins only apply to modules that return something; several modules can mix into the same target (applied in config-merge order), and a later `requirejs-config.js` can switch one off with `false`. The mixin plugin resolves targets through the *unbundled* module id, so `map` aliases are not valid keys.

## Knockout / UI components

Frontend UI components are Knockout view models managed by `Magento_Ui`: layout (or a block's `jsLayout` argument) describes a tree of `components`, `Magento_Ui/js/core/app` instantiates them, and templates bind to them with the `scope` binding.

```xml
<block name="acme.notice" template="Acme_Catalog::notice.phtml">
    <arguments>
        <argument name="jsLayout" xsi:type="array">
            <item name="components" xsi:type="array">
                <item name="acme-notice" xsi:type="array">
                    <item name="component" xsi:type="string">Acme_Catalog/js/view/notice</item>
                    <item name="config" xsi:type="array">
                        <item name="template" xsi:type="string">Acme_Catalog/notice</item>
                        <item name="threshold" xsi:type="string">50</item>
                    </item>
                </item>
            </item>
        </argument>
    </arguments>
</block>
```

```php
<div class="acme-notice" data-bind="scope: 'acme-notice'">
    <!-- ko template: getTemplate() --><!-- /ko -->
</div>
<script type="text/x-magento-init">
{ "*": { "Magento_Ui/js/core/app": <?= /* @noEscape */ $block->getJsLayout() ?> } }
</script>
```

```js
// Acme_Catalog/js/view/notice.js
define(['uiComponent', 'ko', 'Magento_Customer/js/customer-data'], function (Component, ko, customerData) {
    'use strict';

    return Component.extend({
        defaults: { template: 'Acme_Catalog/notice', threshold: 0 },

        initialize: function () {
            this._super();
            this.cart = customerData.get('cart');       // ko observable, updates when the section reloads
            this.remaining = ko.computed(function () {
                return Math.max(0, this.threshold - (this.cart().subtotalAmount || 0));
            }, this);
            return this;
        }
    });
});
```

```html
<!-- Acme_Catalog/view/frontend/web/template/notice.html -->
<div class="acme-notice__body" if="remaining() > 0">
    <span translate="'Add more to get free shipping'"></span>
    <span data-bind="text: remaining"></span>
</div>
```

- `defaults` are merged with the `config` from the layout; `initialize` must call `this._super()` and return `this`.
- Template ids resolve as `<Module>/template/<path>.html` through the same static fallback (`Acme_Catalog/notice` → theme `Acme_Catalog/web/template/notice.html`, else the module's `view/frontend/web/template/notice.html`), loaded with the `text!` plugin and cached in the browser like any static file — in developer mode a genuinely new path materialises on its first request, edits to an existing one show through the symlink, and only a new file that *overrides* an already-materialised path (say a theme copy of a module template) needs that path deleted from the theme's `pub/static` (and `var/view_preprocessed`) once.
- Custom bindings from `Magento_Ui/js/lib/knockout/bindings/`: `scope`, `i18n` (`data-bind="i18n: 'Text'"` or `translate="'Text'"`), `afterRender`, `mageInit`, `bindHtml`, `fadeVisible`, `outerClick`, `keyboard`, `tooltip`, `range`, `datepicker`, `collapsible`, `optgroup`, `staticChecked`, `autoselect`; the async `template` binding is Knockout's own, extended by the engine in `Magento_Ui/js/lib/knockout/template/` (`engine.js`, `loader.js`). Knockout's `if`, `text`, `css`, `attr`, `click`, `visible` can be written as attributes (`if="…"`, `text="…"`) inside `.html` templates thanks to `Magento_Ui`'s renderer; `$t('Text')` is available inside a scope.
- Get a component instance from anywhere with `uiRegistry.get('acme-notice')` (async: `uiRegistry.get('acme-notice', function (c) {…})`).

## Customer-data sections (P3)

Full-page cache serves the same HTML to everyone; anything that depends on the visitor is loaded separately as a **section** and rendered client-side. Three pieces:

`app/code/Acme/Catalog/CustomerData/Notice.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\CustomerData;

use Magento\Customer\CustomerData\SectionSourceInterface;
use Magento\Customer\Model\Session;

class Notice implements SectionSourceInterface
{
    public function __construct(private readonly Session $session)
    {
    }

    public function getSectionData(): array
    {
        return ['isLoggedIn' => $this->session->isLoggedIn(), 'greeting' => $this->session->getCustomer()->getName()];
    }
}
```

`app/code/Acme/Catalog/etc/frontend/di.xml` registers it under a section name (lowercase, hyphens):

```xml
<type name="Magento\Customer\CustomerData\SectionPoolInterface">
    <arguments>
        <argument name="sectionSourceMap" xsi:type="array">
            <item name="acme-notice" xsi:type="string">Acme\Catalog\CustomerData\Notice</item>
        </argument>
    </arguments>
</type>
```

`app/code/Acme/Catalog/etc/frontend/sections.xml` says which POST actions make it stale:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magekwik-magento:module:Magento_Customer:etc/sections.xsd">
    <action name="acme/notice/dismiss">
        <section name="acme-notice"/>
    </action>
</config>
```

How it behaves (from `Magento_Customer/js/customer-data.js` and `section-config.js`):

- Sections are fetched in one `GET customer/section/load?sections=a,b` and kept in `localStorage` (`mage-cache-storage`); `customerData.get('acme-notice')` returns a Knockout observable of the last known data, so templates render immediately from storage and update when a reload lands. `customerData.reload(['acme-notice'], true)` forces a fetch; `customerData.invalidate(['acme-notice'])` marks it stale.
- After any jQuery AJAX request with method POST/PUT/DELETE, and on native `<form method="post">` submits, the URL is matched against `sections.xml` action names (`route/controller/action`, lowercase, `*` wildcards allowed) and the listed sections are invalidated and reloaded. `<section name="*"/>` invalidates all; an `<action>` with **no** `<section>` child also invalidates all — that is the rule that turns a harmless custom POST into a full section reload.
- Sections listed as expirable (core: `cart`, via the `expirableSectionNames` argument of `Magento\Customer\Block\CustomerData`) are re-fetched after `customer/online_customers/section_data_lifetime` minutes (default 60). The `section_data_ids` cookie carries a version per section, and the server regenerates the `private_content_version` cookie on every POST request, which is how a change made in one tab is noticed by another.
- Guests get sections too; return minimal data for them. Never put a section's data into the HTML server-side: the HTML is the cached, shared part.

## Translation in JavaScript

`$.mage.__('Text')` (after requiring `mage/translate`), `$t('Text')` inside Knockout templates, and the `i18n` binding all look the phrase up in `js-translation.json`, generated per theme/locale at static deploy (and on first request in developer/default mode) by scanning `.js` and `.html` files for those call patterns. Two consequences: a phrase used only in a `.phtml` inline script is never collected, and the dictionary only contains phrases whose translation differs from the source — so with `en_US` and no CSV entry it is empty, which is normal. `dev/js/translate_strategy` is `dictionary` by default (`embedded` inlines translations into the JS files at deploy time; `none` disables both).

## Templates in JavaScript

`mage/template` is Underscore's `_.template` with a selector convenience: `mageTemplate('#acme-tpl', {name: 'x'})` or `mageTemplate('<li><%- data.name %></li>')({data: item})`. Use `<%- %>` (escaped) for data, `<%= %>` only for HTML you built yourself. `Magento_Ui/js/lib/knockout/template/*` is the Knockout side and needs no direct use.

## Static deploy, bundling, minification

- Every module id must exist under `pub/static/frontend/<Vendor>/<theme>/<locale>/` at request time: developer and default modes create the symlink on the first 404 (`static.php`), production only serves what `setup:static-content:deploy` wrote. A new module file in production therefore needs a redeploy; in developer mode it just needs the theme's `pub/static` copy of `requirejs-config.js` refreshed if you added config.
- Minification (`dev/js/minify_files`, `dev/css/minify_files`) is applied only outside developer mode; minified files are named `*.min.js` and `requirejs-min-resolver.js` maps ids to them, so never hard-code `.min` in ids. Exclusions live in `dev/js/minify_exclude`.
- Built-in bundling (`dev/js/enable_js_bundling`) works in production mode only: static deploy writes `js/bundle/bundle*.js` (size from the theme's `etc/view.xml` `bundle_size`, files excluded through its `<exclude>` list) and the RequireJS config block loads every bundle on every page; `dev/js/merge_files` must be 0 for it. It cuts request count at the price of a large blocking download — measure before enabling, and prefer an r.js/Magepack build if you go further.
- `dev/static/sign` (default on) prefixes static URLs with `version<timestamp>` from `pub/static/deployed_version.txt`; deploy regenerates it, developer/default modes generate one if missing, production without the file fails with `Unable to retrieve deployment version of static files from the file system`.

## Debugging

- `Script error for "x"` / `Uncaught Error: Mismatched anonymous define()` in the console: wrong module id, file not deployed, or a non-AMD script loaded without `shim`. Check the network tab for the 404 and the merged `requirejs-config.js` for the `map`/`paths` in effect.
- A mixin that does not apply: the key is not the exact target id (aliases from `map` do not count), the target returns nothing, or the merged config is stale (see above).
- A component that initialises twice (duplicate handlers, double modals): `contentUpdated` fired on a container that still holds already-initialised markup, or the same selector matched by two `x-magento-init` blocks.
- Customer-data never updates: the POST URL does not match an `<action>` in `sections.xml`, or the request was not made through jQuery (`fetch()` bypasses `ajaxComplete`) — call `customerData.reload([...], true)` yourself.
- `require.s.contexts._.config` in the console shows the live RequireJS configuration; `requirejs.undef('id')` forces a module to reload after a failed fetch.

## Sources

- https://developer.adobe.com/commerce/frontend-core/javascript/init — Initialize JavaScript (`data-mage-init`, `x-magento-init` JSON shape with selector and `*`, what a component may return, `contentUpdated`, imperative `require` is inline JavaScript)
- https://developer.adobe.com/commerce/frontend-core/javascript/requirejs — RequireJS configuration (`var config`, `map` with `*` and per-module keys, `paths`, `deps`, `shim` with `exports`, `config.mixins`, `config.text` headers)
- https://developer.adobe.com/commerce/frontend-core/javascript/mixins — JavaScript mixins (declaration in `requirejs-config.js`, UI component / jQuery widget / function / object patterns, `mage/utils/wrapper`, no `.js` in keys, disabling with `false`)
- https://developer.adobe.com/commerce/frontend-core/javascript/custom — Custom JavaScript (module locations in modules and themes, ids without `.js`, `define()`, `$.widget('<ns>.<name>', …); return $.<ns>.<name>;`, `map` to replace a component)
- https://developer.adobe.com/commerce/frontend-core/ui-components/concepts/configuration-flow — UI component configuration flow (`x-magento-init` with `Magento_Ui/js/core/app`, `component` property, `config` merged over `defaults`, `.html` templates rendered by Knockout)
- https://developer.adobe.com/commerce/frontend-core/ui-components/concepts/knockout-bindings — Custom Knockout bindings (`scope`, `i18n`/`translate`, `template`, `mageInit`, `afterRender`, … in `Magento_Ui/js/lib/knockout/bindings/`)
- https://developer.adobe.com/commerce/php/development/cache/page/private-content — Private content (`SectionSourceInterface`, `sectionSourceMap`, `sections.xml`, "no section listed invalidates all", `customerData.get()`, `customer/section/load`, why not `cacheable="false"`)
- https://developer.adobe.com/commerce/frontend-core/guide/themes/js-bundling — JavaScript bundling (production only, `dev/js/enable_js_bundling`, `dev/js/minify_files`, `dev/js/merge_files 0`, `bundle_size` and `<exclude>` in `etc/view.xml`, redeploy static content)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/static-view/static-view-file-deployment — Deploy static view files (on-demand generation in default/developer mode, `-f`, `--theme`, `--language`, `pub/static/frontend/<Vendor>/<theme>/<locale>`, `deployed_version.txt`)
