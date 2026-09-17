# Templates, ViewModels and escaping

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (L1, L2, S3 and Q5 apply throughout).

A `.phtml` template is the markup half of a block: `Magento\Framework\View\Element\Template::_toHtml()` resolves the `template` name through the theme fallback, hands the file to the PHP template engine, and the engine `include`s it with `$block`, `$escaper` and a few helpers in scope. Everything the template shows comes from `$block` (layout arguments, child blocks) or from a ViewModel; the template itself decides only *how* to print it.

## Where templates live and how they are found

The `template` attribute (or `setTemplate()`) is `Vendor_Module::path/inside/templates.phtml`. For `Magento_Catalog::product/view/addtocart.phtml` on the `Acme/default` theme the resolver tries, in order:

1. `app/design/frontend/Acme/default/Magento_Catalog/templates/product/view/addtocart.phtml`
2. the same path in each parent theme (`Magento/luma`, then `Magento/blank`)
3. `<Magento_Catalog module dir>/view/frontend/templates/product/view/addtocart.phtml`
4. `<Magento_Catalog module dir>/view/base/templates/product/view/addtocart.phtml`

So an **override** is a copy of the core file at step 1 with the same path — nothing else to register. Keep the copy as close to the original as possible and diff it against core after every upgrade (H5 says the same for Hyvä). The resolution result is not stored in any cache type; only rendered HTML is (`block_html` for blocks with a `cache_lifetime`, and `full_page`), so after adding an override run `bin/magento cache:clean block_html full_page`.

Without the `Vendor_Module::` prefix the path is resolved relative to the block class's module; for the default `Template` class that module is empty and the file is looked up in the theme-root `templates/` directory. Always write the prefix.

A template that cannot be found (or is outside the allowed directories) throws `ValidatorException: Invalid template file: 'x' in module: 'y' block's name: 'z'` in developer mode and, in production, logs the same message to `var/log/system.log` and renders an empty string.

## What is in scope

| Variable | What it is |
|---|---|
| `$block` | The block object (`Magento\Framework\View\Element\Template` unless the layout gave a `class`) |
| `$escaper` | `Magento\Framework\Escaper` — the only escaping API to use |
| `$secureRenderer` | `Magento\Framework\View\Helper\SecureHtmlRenderer` — renders `<script>`/`<style>`/event handlers with CSP nonces |
| `$localeFormatter` | `Magento\Framework\Locale\LocaleFormatter` — locale-aware number formatting |
| `$csp` | `Magento\Csp\Api\InlineUtilInterface` when `Magento_Csp` is enabled (it is by default) |
| `$this` | The template *engine*, which proxies method calls to the block — deprecated, flagged by `Magento2.Templates.ThisInTemplate` (L2) |

Start every template with docblocks so IDEs and reviewers know the types:

```php
<?php
/** @var \Magento\Framework\View\Element\Template $block */
/** @var \Magento\Framework\Escaper $escaper */
/** @var \Acme\Catalog\ViewModel\ShippingNotice $viewModel */
$viewModel = $block->getData('view_model');
?>
```

`$block->getData('view_model')` and the magic `$block->getViewModel()` are the same thing (`DataObject::__call` turns `getViewModel` into `getData('view_model')`); the explicit form survives a rename and is what the coding standard's examples use.

## `$block` API you actually use

- `$block->getData('key')` / `$block->getKey()` / `$block->hasData('key')` — layout `<argument name="key">` values and anything a parent block `setData()`.
- `$block->getChildHtml('alias')` — renders a child declared in layout under this block (`as` alias, or its name). `getChildHtml()` with no argument renders all children; `getChildBlock('alias')` returns the object; `getChildNames()` lists them. A child that layout `remove`d renders `''`, no error.
- `$block->getUrl('checkout/cart/add', ['product' => 42, '_secure' => true])` — builds `https://…/checkout/cart/add/product/42/`. `$block->getBaseUrl()` is the store base URL.
- `$block->getViewFileUrl('Acme_Catalog::images/icon.svg')` — static file URL through the theme fallback (`app/design/frontend/Acme/default/Acme_Catalog/web/images/icon.svg`, then the module's `view/frontend/web/images/icon.svg`); `'images/logo.svg'` without a module prefix looks in the theme's `web/`.
- `$block->getNameInLayout()`, `$block->getRequest()->getParam('id')` (cast it — S6), `$block->getLayout()->getBlock('name')` (read-only lookups; do not `createBlock()` from a template — declare it in layout so it is cacheable and overridable).
- `$block->getJsLayout()` — the `jsLayout` argument as JSON, already safe to print (the XSS sniff knows it).

Avoid `$block->getLayout()->createBlock(...)`, `$this->helper(...)` and any `ObjectManager` call: they hide dependencies and are flagged by `Magento2.Templates.ObjectManager`/`ThisInTemplate`.

## ViewModels (L2)

A ViewModel is any class implementing the empty marker interface `Magento\Framework\View\Element\Block\ArgumentInterface`, built by the object manager with normal constructor injection, and handed to the block through layout:

```xml
<block name="acme.notice" template="Acme_Catalog::notice.phtml">
    <arguments>
        <argument name="view_model" xsi:type="object">Acme\Catalog\ViewModel\Notice</argument>
    </arguments>
</block>
```

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\ViewModel;

use Magento\Framework\App\Config\ScopeConfigInterface;
use Magento\Framework\View\Element\Block\ArgumentInterface;
use Magento\Store\Model\ScopeInterface;

class Notice implements ArgumentInterface
{
    private const XML_PATH_THRESHOLD = 'acme_catalog/notice/threshold';

    public function __construct(private readonly ScopeConfigInterface $scopeConfig)
    {
    }

    public function getThreshold(): string
    {
        return (string) $this->scopeConfig->getValue(self::XML_PATH_THRESHOLD, ScopeInterface::SCOPE_STORE);
    }
}
```

- The layout interpreter checks the instance: any other class throws `UnexpectedValueException: Instance of Magento\Framework\View\Element\Block\ArgumentInterface is expected, got X instead.` — in developer mode the page errors, in production the message goes to `var/log/system.log` and the block renders nothing.
- Instances are **shared** (`ObjectManager::get()`), so the same object serves every block on the page that names it — keep no per-block state in properties; add `shared="false"` on the argument when you really need a fresh instance.
- No `di.xml` entry is needed. Several blocks can receive the same ViewModel; a block can receive several under different argument names.
- Prefer a ViewModel to a custom `Block` class for presentation logic (data lookups, formatting, "is it enabled?"). Write a Block subclass only for things that are about the block itself: `_prepareLayout()` (adding children programmatically), `getCacheKeyInfo()`/`getIdentities()` for block caching, or a class other modules are meant to reference.
- Prefer a ViewModel to a helper: `Magento2.Templates.ThisInTemplate` reports "The use of helpers in templates is discouraged. Use ViewModel instead."

## Escaping (S3)

`$escaper` is `Magento\Framework\Escaper`. Pick the method by *where* the value lands:

| Where the value goes | Method | Notes |
|---|---|---|
| Text between tags | `escapeHtml($data, $allowedTags = null)` | Casts to string (a `Phrase` is fine), `htmlspecialchars` with `ENT_QUOTES`. With `$allowedTags` (e.g. `['b', 'a']`) other tags are stripped, attributes other than `id`, `class`, `href`, `title`, `style` are dropped, `href` is URL-escaped; `script`, `img`, `embed`, `iframe`, `video`, `source`, `object`, `audio` can never be allowed (logged as critical and removed). Arrays are escaped element-wise. |
| Inside a quoted attribute value | `escapeHtmlAttr($string, $escapeSingleQuote = true)` | Encodes everything that could break out of a double- or single-quoted attribute; use for `title`, `alt`, `data-*`, JSON in an attribute. |
| `href`, `src`, `action`, `data-url` | `escapeUrl($string)` | Removes `javascript:`, `data:`, `vbscript:` schemes (including hex-encoded forms) and then HTML-escapes. |
| A single value inside a URL query | `encodeUrlParam($string)` | `rawurlencode`-style; combine with `escapeUrl` on the whole URL. |
| Inside a JavaScript string literal | `escapeJs($string)` | Replaces every character except `[a-z0-9,._]` with `\uXXXX`; safe inside `'…'` or `"…"` in a `<script>` or event handler. Wrap in `escapeHtmlAttr` when the JS sits in an attribute. |
| Inside a `style` attribute or `<style>` | `escapeCss($string)` | Hex-escapes; do not use it to "sanitise" whole stylesheets. |
| Already HTML (rendered child block, WYSIWYG content sanitised elsewhere) | no escaping, mark it `/* @noEscape */` | The sniff treats methods whose name contains `html` (`getChildHtml()`, `toHtml()`, `getBlockHtml()`) and `getJsLayout()` as safe without the annotation. |

Deprecated and to be removed from templates you touch: `$block->escapeHtml()`, `$block->escapeHtmlAttr()`, `$block->escapeUrl()`, `$block->escapeJs()`, `$block->escapeCss()` (deprecated in framework 103.0.0 = 2.4.0 — `Magento2.Legacy.EscapeMethodsOnBlockClass` flags them), and `escapeQuote()`, `escapeJsQuote()`, `escapeXssInUrl()` on either object (deprecated 101.0.0). `/* @escapeNotVerified */` is no longer an accepted annotation.

```php
<a href="<?= $escaper->escapeUrl($block->getUrl('acme/notice/details', ['id' => $viewModel->getId()])) ?>"
   title="<?= $escaper->escapeHtmlAttr($viewModel->getTitle()) ?>"
   data-config="<?= $escaper->escapeHtmlAttr(json_encode($viewModel->getConfig())) ?>">
    <?= $escaper->escapeHtml(__('Details for %1', $viewModel->getName())) ?>
</a>
<?= $escaper->escapeHtml($viewModel->getRichText(), ['b', 'i', 'a']) ?>
<div class="acme-notice__children"><?= $block->getChildHtml('addons') ?></div>
<?php $script = 'window.acmeNotice = { id: "' . $escaper->escapeJs($viewModel->getId()) . '" };'; ?>
<?= /* @noEscape */ $secureRenderer->renderTag('script', [], $script, false) ?>
```

Rules of thumb: escape at output, never in the ViewModel (it does not know where the string will land); `__()` returns a `Phrase` and *still* needs escaping — the translation file is data; cast numbers explicitly (`(int)`) and the sniff lets them through; `count()` is exempt.

## Translation (Q5)

`__('Free shipping on orders over %1', $threshold)` looks the whole string up in the merged `i18n/<locale>.csv` files (module, theme, language pack, DB) and substitutes `%1`, `%2`, …; that is why fragments must not be concatenated — translators reorder placeholders, not sentences. Strings only used in templates still go into your module's `i18n/en_US.csv` (`"Free shipping on orders over %1","Free shipping on orders over %1"`) so `bin/magento i18n:collect-phrases` and translators find them. Layout `<argument … translate="true">` wraps the value in `__()` for you. JavaScript strings translate through `$.mage.__()`/`$t()` and the `js-translation.json` dictionary — see `requirejs-knockout.md`.

## JavaScript from a template

Prefer declarative initialisation of a RequireJS module (L3):

```php
<div class="acme-notice" data-mage-init='{"Acme_Catalog/js/notice": {"delay": 3000}}'>…</div>

<script type="text/x-magento-init">
{
    ".acme-notice": {
        "Acme_Catalog/js/notice": {"delay": <?= (int) $viewModel->getDelay() ?>}
    },
    "*": {
        "Magento_Ui/js/core/app": <?= /* @noEscape */ $block->getJsLayout() ?>
    }
}
</script>
```

- `data-mage-init` targets the element it sits on; `x-magento-init` takes a selector (or `*` for element-less components) and can initialise several components. Both are JSON: build values with `(int)` casts, `$escaper->escapeHtmlAttr(json_encode(...))` inside the attribute form, and `/* @noEscape */ json_encode(...)` inside the script form.
- A raw `<script>` with inline code is what CSP is there to stop. The storefront runs CSP in report-only mode by default, but `checkout_index_index` runs in *restrict* mode with inline scripts disallowed, so inline code there is blocked unless rendered through `$secureRenderer->renderTag('script', [], $js, false)` (adds the nonce) or `$secureRenderer->renderEventListenerAsTag('onclick', $js, '.selector')`. `<script type="text/javascript">` is flagged by `Magento2.Legacy.PhtmlTemplate`; use `<script>` (via the renderer) or the `x-magento-init` type.
- Never reference RequireJS modules with a global `require([...])` inside markup that may be inserted by AJAX without `.trigger('contentUpdated')` afterwards — the declarative forms are re-scanned by that event.

## Custom block classes — when you need one

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Block;

use Acme\Catalog\Api\NoticeRepositoryInterface;
use Magento\Framework\View\Element\Template;
use Magento\Framework\View\Element\Template\Context;

class Notice extends Template
{
    public function __construct(
        Context $context,
        private readonly NoticeRepositoryInterface $noticeRepository,
        array $data = []
    ) {
        parent::__construct($context, $data);
    }

    protected function _prepareLayout()
    {
        $this->pageConfig->getTitle()->set(__('Shipping notice'));
        return parent::_prepareLayout();
    }
}
```

`Context` carries the request, URL builder, escaper, scope config, cache state and event manager; extra dependencies go after it and `array $data = []` stays last so layout arguments still arrive. Override `getCacheKeyInfo()` and implement `IdentityInterface` only when you set `cache_lifetime` and the output depends on entities. If none of this applies, use a ViewModel.

## Finding the template to change

1. Developer mode: `bin/magento dev:template-hints:enable && bin/magento cache:clean config full_page`; every block gets a red outline with the template path (and the class with `dev/debug/template_hints_blocks`). Turn it off with `dev:template-hints:disable`. The *Advanced › Developer* configuration section is hidden in production mode, so the CLI command (or `config:set`) is the way in.
2. Search the block name from the hint in layout XML (`grep -rn 'name="product.info.addtocart"' vendor/magento app --include=*.xml`) to see the `template` attribute and any `referenceBlock` that changed it in a parent theme.
3. Copy the file to `app/design/frontend/Acme/default/<Vendor>_<Module>/templates/<same path>` and edit; clean `block_html full_page`.

## Static checks

`vendor/bin/phpcs --standard=Magento2 app/design/frontend/Acme/default app/code/Acme` (Q1) runs, among others: `Magento2.Security.XssTemplate` (unescaped echo), `Magento2.Templates.ThisInTemplate` (`$this`, helpers), `Magento2.Templates.ObjectManager`, `Magento2.Legacy.EscapeMethodsOnBlockClass` (`$block->escape*`), `Magento2.Legacy.PhtmlTemplate` (`text/javascript`, `$block->_protected` access). `php -l` on every `.phtml` catches syntax before the storefront does.

## Sources

- https://developer.adobe.com/commerce/frontend-core/guide/templates/ — Templates overview (templates as the view layer, "do not change the default templates", HTML templates for Knockout)
- https://developer.adobe.com/commerce/frontend-core/guide/templates/override — Basic template concepts (`<theme_dir>/<Namespace>_<Module>/templates/<path>`, layout arguments via `get{ArgumentName}()`/`has{ArgumentName}()`, `$escaper->escapeHtml(__(...))`, templates must not instantiate objects)
- https://developer.adobe.com/commerce/frontend-core/guide/templates/walkthrough — Template customization (locate with template hints, copy following the convention, developer mode, clearing `pub/static` and `var/view_preprocessed` for `.html` templates)
- https://developer.adobe.com/commerce/frontend-core/guide/themes/debug — Override default files / template path hints (admin path, `dev:template-hints:enable|disable`, `?templatehints=magento`, `cache:clean config full_page`)
- https://developer.adobe.com/commerce/php/development/components/view-models — View models (`ArgumentInterface`, `<argument name="view_model" xsi:type="object">`, `$block->getViewModel()`, `/** @var */` docblock, helpers discouraged)
- https://developer.adobe.com/commerce/php/development/security/cross-site-scripting — Cross-site scripting (which `Escaper` method for which context, `/* @noEscape */`, methods containing `html`, casts and `count()`, `$escaper` available in templates, `Magento2.Security.XssTemplate`)
- https://developer.adobe.com/commerce/frontend-core/javascript/init — Initialize JavaScript (`data-mage-init`, `x-magento-init` shape with selector and `*`, what a component returns, `contentUpdated`, "do not add inline JavaScript")
- https://developer.adobe.com/commerce/frontend-core/guide/layouts/xml-instructions — Layout instructions (`shared="false"` on object arguments, `translate="true"`)
