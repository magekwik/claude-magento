# Layout XML — files, handles, instructions and debugging

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magekwik-magento:conventions` (L1 and P3 apply throughout).

Layout XML declares the tree of containers and blocks for a page. The framework merges every layout file that matches the page's handles, builds the structure, instantiates the blocks and renders them. Change pages here first; override a template only when the markup itself must change (L1).

## Three file types

| Type | Root element / XSD | Module location | Theme location | Purpose |
|---|---|---|---|---|
| Page layout | `<layout>` — `urn:magento:framework:View/Layout/etc/page_layout.xsd` | `view/frontend/page_layout/` | `<Vendor>_<Module>/page_layout/` | Wireframe of `<body>`: containers only (`empty`, `1column`, `2columns-left`, `2columns-right`, `3columns`, registered in `Magento_Theme/view/frontend/layouts.xml`) |
| Page configuration | `<page>` — `urn:magento:framework:View/Layout/etc/page_configuration.xsd` | `view/frontend/layout/` | `<Vendor>_<Module>/layout/` | What you write 99% of the time: `<head>`, `<body>` with blocks and containers, `<update>` |
| Generic layout | `<layout>` — `urn:magento:framework:View/Layout/etc/layout_generic.xsd` | `view/frontend/layout/` | `<Vendor>_<Module>/layout/` | Body-only structure for AJAX responses and non-page results |

Every page configuration file starts:

```xml
<?xml version="1.0"?>
<page xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:View/Layout/etc/page_configuration.xsd">
    <head>…</head>
    <body>…</body>
</page>
```

`<page layout="2columns-left">` selects the page layout (the `layout` attribute on the root); `<update handle="other_handle"/>` merges another handle's instructions in first. The `xsi:noNamespaceSchemaLocation` URN is resolved by IDEs (`bin/magento dev:urn-catalog:generate .idea/misc.xml`) and by static tests; in developer mode the *merged* result is validated against `layout_merged.xsd`, which includes the same element definitions (other modes skip schema validation).

## Handles — which files apply to a page

- The handle is the file name without `.xml`; the file's root attributes (`layout`, `label`, `design_abstraction`) become handle attributes.
- `default` is added to every full page. The page's own handle is its lowercased full action name `route_controller_action`: `cms_index_index` (home), `cms_page_view`, `catalog_category_view`, `catalog_product_view`, `catalogsearch_result_index`, `checkout_cart_index`, `checkout_index_index`, `customer_account_login`, `customer_account_index`, `sales_order_history`.
- Entity handles come on top, from `Page::addPageLayoutHandles()`:
  - Products: `catalog_product_view_type_<simple|configurable|bundle|grouped|virtual|downloadable>`, `catalog_product_view_attribute_set_<id>`, `catalog_product_view_id_<id>`, `catalog_product_view_sku_<rawurlencoded sku>`.
  - Categories: `catalog_category_view_type_<default|layered|default_without_children|layered_without_children>` (anchor → `layered`), `catalog_category_view_displaymode_<products|page|products_and_page>`, `catalog_category_view_id_<id>`.
  - CMS pages: `cms_page_view` plus `cms_page_view_id_<identifier>` with `/` replaced by `_` (`cms_page_view_id_home` for the default home page).
- Shared handles are pulled in with `<update handle="…"/>`: `customer_account` (every My Account page), `default_head_blocks` (from `default`), `checkout_cart_item_renderers` (from `checkout_cart_index`). `<update>` recurses; a cycle is logged in developer mode and stopped.
- `layout="…"` on `<page>` may appear in any handle; the last one processed wins.

## Merge order

`Magento\Framework\View\Model\Layout\Merge` collects, for the current theme, in this order: every module's `view/base/layout/*.xml` and `view/frontend/layout/*.xml` (sorted by module `<sequence>`, A8), then for each theme from the root ancestor to the current one (`Magento/blank` → `Magento/luma` → `Acme/default`) that theme's `<Vendor>_<Module>/layout/*.xml`. Later files add to earlier ones, so a `referenceBlock` in your theme changes what a module declared. Two directories *replace* instead of extend:

- `<theme>/<Vendor>_<Module>/layout/override/base/<handle>.xml` replaces the module's own `<handle>.xml`.
- `<theme>/<Vendor>_<Module>/layout/override/theme/Magento/luma/<handle>.xml` replaces Luma's version of that file (the path names an ancestor theme; naming a non-ancestor throws).

Override only when an extending file cannot express the change; overrides freeze a copy of core XML that stops receiving upstream fixes. The merged XML is cached in the `layout` cache type, keyed by handles, theme and store.

## Containers vs blocks

- A **container** (`<container>`) is structure: it renders its children in order and, only if it has `htmlTag`, wraps them in `<htmlTag id="htmlId" class="htmlClass">`. A container with no children (or whose children render nothing) prints nothing. `label` is the name shown in the admin widget-placement UI.
- A **block** (`<block>`) is a PHP object (`class`, default `Magento\Framework\View\Element\Template`) rendering a `template`. Blocks can have child blocks and containers; `getChildHtml('alias')` renders one by its alias (`as`, or the name when `as` is absent), `getChildHtml()` renders all.
- Names must be unique per page and match `[a-zA-Z0-9][a-zA-Z\d\-_\.]*`; a `<block>` without `name` gets a generated one (`<parent>_schedule_block…`) you cannot reference. Prefix yours (`acme.shipping.notice`).

## Instruction reference (page_configuration.xsd / elements.xsd)

| Element | Attributes | Notes |
|---|---|---|
| `<block>` | `name`, `class`, `template`, `as`, `before`, `after`, `ifconfig`, `aclResource` (`acl` deprecated), `group`, `cacheable` (default `true`), `ttl` (int seconds), `output` | Children: `<arguments>` (max one), `<action>`, `<block>`, `<container>`, `<referenceBlock>`, `<uiComponent>` |
| `<container>` | `name`, `label`, `as`, `before`, `after`, `htmlTag`, `htmlClass`, `htmlId`, `output` | `htmlTag` is an enumeration: `div`, `main`, `nav`, `header`, `footer`, `section`, `article`, `aside`, `p`, `ul`, `ol`, `dl`, `dd`, `table`, `tfoot`, `fieldset`, `h1`–`h6` — no `span` |
| `<referenceBlock>` | `name` (required), `template`, `class`, `group`, `display` (default `true`), `remove` | Same children as `<block>` plus `<referenceContainer>` |
| `<referenceContainer>` | `name` (required), `htmlTag`, `htmlClass`, `htmlId`, `label`, `display`, `remove` | Children: `<block>`, `<container>`, `<referenceBlock>`, `<referenceContainer>`, `<uiComponent>` — **no** `<arguments>`, no `before`/`after` |
| `<move>` | `element`, `destination` (required), `as`, `before`, `after` | Direct child of `<body>` (page configuration) or of `<layout>` |
| `<update>` | `handle` | Direct child of `<page>` |
| `<action>` | `method`, `ifconfig` | Calls a public block method with `<argument>` children; documented as deprecated — prefer `<arguments>` |
| `<remove>` | `src` | Only inside `<head>`; removes a previously added asset |
| `<attribute>` | `name`, `value` | Inside `<html>`, `<head>` or `<body>`: `<attribute name="class" value="checkout-index-index"/>` |

`before`/`after` take a sibling name or `-` (`before="-"` = first, `after="-"` = last). They only reorder siblings; if the named sibling has a different parent the instruction is ignored (developer mode logs "Broken reference … their parents are different" at info level in `var/log/debug.log`).

### `remove` and `display`

```xml
<referenceBlock name="report.bugs" remove="true"/>     <!-- block and its children are gone -->
<referenceContainer name="sidebar.additional" remove="true"/>
<referenceBlock name="catalog.compare.sidebar" display="false"/>   <!-- not rendered, object still exists -->
```

- `remove="true"` schedules the element for removal after all files are merged; a later file (a child theme, a module loaded after yours) can put it back with `remove="false"`. Removing a container removes everything inside it.
- `display="false"` skips rendering of the element and its children but keeps the block object, so `$block->getChildBlock()` callers and layout arguments still work. It is ignored when `remove="true"` is also set.
- `<referenceBlock name="x">` for a name that no file declares is logged as "Broken reference: missing declaration of the element 'x'" (critical) and dropped; a `<block>` placed inside a `<referenceContainer>` that does not exist is dropped silently in production and logged at info level in developer mode.

### `move`

```xml
<move element="breadcrumbs" destination="columns.top" before="page.main.title"/>
<move element="catalog.compare.sidebar" destination="sidebar.additional" as="compare" after="-"/>
```

Moves keep the element's alias unless `as` is given; the element may be a block or a container. Use `<move>` instead of declaring the block again under a new parent: a second `<block name="x">` is not an error at runtime, but the later declaration replaces the earlier one — its arguments are reset and the children scheduled under it so far are dropped.

### `ifconfig`

```xml
<block name="acme.notice" template="Acme_Catalog::notice.phtml" ifconfig="acme_catalog/notice/enabled"/>
```

Read with `ScopeConfigInterface::isSetFlag()` at store scope when the structure is built; a falsy value removes the block and its children. Allowed on `<block>`, `<uiComponent>` and `<action>` only — the XSD has no `ifconfig` on `<container>`, `<referenceBlock>` or `<referenceContainer>`, and because the merged layout is schema-validated only when `ValidationState::isValidationRequired()` is true (developer mode), an unknown attribute throws a `ValidationException` there and is silently ignored — neither validated nor logged — in default and production mode. For anything more complex than a yes/no flag, decide in the ViewModel and return early in the template.

### `<arguments>` and `xsi:type`

```xml
<block name="acme.notice" template="Acme_Catalog::notice.phtml">
    <arguments>
        <argument name="view_model" xsi:type="object">Acme\Catalog\ViewModel\Notice</argument>
        <argument name="title" xsi:type="string" translate="true">Free shipping</argument>
        <argument name="threshold" xsi:type="number">50</argument>
        <argument name="show_icon" xsi:type="boolean">true</argument>
        <argument name="help_url" xsi:type="url" path="cms/page/view"><param name="page_id">shipping</param></argument>
        <argument name="css_classes" xsi:type="array">
            <item name="base" xsi:type="string">acme-notice</item>
            <item name="tone" xsi:type="string">acme-notice--info</item>
        </argument>
        <argument name="logo" xsi:type="helper" helper="Magento\Sales\Model\Order\Invoice\GetLogoFile::execute"/>
        <argument name="optional" xsi:type="null"/>
    </arguments>
</block>
```

Each argument becomes block data: `$block->getData('title')` or the magic `$block->getTitle()`. Types the layout interpreter accepts: `string` (with `translate="true"` the value is wrapped in `__()`), `boolean`, `number`, `null`, `array` (items are typed the same way and nest), `object` (a class name — the object manager instantiates it and it **must** implement `Magento\Framework\View\Element\Block\ArgumentInterface`; `shared="false"` gives a fresh instance instead of the singleton), `url` (`path` plus `<param>` children, resolved with `UrlInterface::getUrl()`), `helper` (`Class::method`, called with `<param>` values), `options` (an `OptionSourceInterface` model). `const` appears in the XSD but the frontend interpreter has no handler for it — use a `string`. Arguments declared on a `referenceBlock` merge into the existing ones (same name replaces; `array` items merge by key).

Argument names must be unique per block and each `<arguments>` must contain at least one `<argument>`.

## `<head>`

```xml
<head>
    <title>Free shipping</title>
    <meta name="description" content="…"/>
    <css src="Acme_Catalog::css/notice.css"/>
    <css src="css/print.css" media="print"/>
    <link src="https://fonts.example/x.css" src_type="url" rel="stylesheet"/>
    <script src="Acme_Catalog::js/legacy.js" defer="defer"/>
    <font src="fonts/acme/acme-400.woff2"/>
    <remove src="css/print.css"/>
    <attribute name="lang" value="en"/>
</head>
```

`css`, `link` and `font` share `linkType`: `src` (required), `src_type` (`url` or `controller` for remote assets; otherwise the value is a `Vendor_Module::path` or a theme `web/` path resolved through the fallback), `defer`, `ie_condition`, `charset`, `hreflang`, `media`, `rel`, `rev`, `sizes`, `target`, `type`, `order`, `integrity`, `crossorigin`, `as` (`font`/`script`/`style`). `script` has its own `scriptType`: `src`, `src_type`, `defer`, `async`, `ie_condition`, `charset`, `type`, `integrity`, `crossorigin` — no `order`, `media`, `rel` or `as`. `<remove src>` must repeat the exact `src` string that added the asset. `<title>` sets the page title; `<meta name="…" content="…"/>` sets metadata (`metaType` allows `content`, `charset`, `http-equiv`, `name`, `scheme` — there is no `property` attribute). Open Graph tags are written as `<meta name="og:type" content="product"/>`; the page renderer emits `property="og:type"` for any name starting with `og:`. The `default_head_blocks.xml` files of `Magento_Theme` (`requirejs/require.js`), `Magento/blank` (`styles-m.css`, `styles-l.css`, `print.css`) and `Magento/luma` (the fonts) are where the standard assets come from.

## `<body>`

```xml
<body>
    <attribute name="class" value="acme-landing"/>
    <referenceContainer name="content">…</referenceContainer>
    <move …/>
</body>
```

`<attribute name="class">` appends to the body classes (`catalog-product-view` etc. are added by the framework from the handle). Children allowed: `<attribute>`, `<block>`, `<referenceBlock>`, `<referenceContainer>`, `<container>`, `<move>`, `<uiComponent>`.

## Blocks, caching and FPC

- `cacheable="false"` on **any** `<block>` present in the final structure makes `Layout::isCacheable()` return false: the page is served with no-cache headers and is never stored in full-page cache. Core uses it on the checkout, cart and customer-account handles, which are private anyway. Never add it to a block on a cacheable page (P3); use a customer-data section for per-customer bits (see `requirejs-knockout.md`).
- `ttl="3600"` on a block sets `$block->getTtl()`; with Varnish as the FPC backend the block is rendered as an ESI include with its own lifetime (`catalog.topnav` uses it). With the built-in FPC `ttl` changes nothing about caching.
- Block HTML caching (`block_html` cache type) only happens for blocks that set `cache_lifetime` data; layout arguments are part of the cache key only through `getCacheKeyInfo()`.

## Containers you will reference

From `Magento_Theme/view/base/page_layout/empty.xml`, `view/frontend/page_layout/1column.xml`…`3columns.xml` and `view/frontend/layout/default.xml`, top to bottom of the page:

| Name | Where it renders |
|---|---|
| `after.body.start` | First thing inside `<body>` (scripts, cookie notice) |
| `page.wrapper` | `<div class="page-wrapper">` around everything |
| `header.container` | `<header class="page-header">` |
| `header.panel` | The thin top bar: language switcher, `top.links` |
| `header-wrapper` | `<div class="header content">`: `logo`, `minicart`, `top.search` |
| `page.top` | Between header and main content: `navigation.sections` (menu), `top.container`, `breadcrumbs` |
| `top.container` | Inside `page.top`, after the menu |
| `main.content` | `<main id="maincontent" class="page-main">` |
| `columns.top` | Above the columns: `page.main.title`, `page.messages` |
| `columns` | `<div class="columns">`: `main`, `div.sidebar.main`, `div.sidebar.additional` |
| `content.top`, `content`, `content.aside`, `content.bottom` | Inside `main` — the page's own blocks go in `content` |
| `sidebar.main`, `sidebar.additional` | Left/right columns (2-/3-column layouts) |
| `page.bottom.container` → `page.bottom` | Below the columns, above the footer |
| `footer-container` → `footer` | `<footer class="page-footer">` → `<div class="footer content">` |
| `before.body.end` | Last thing before `</body>` |

Handles that set the page layout: `catalog_product_view` and `checkout_cart_index` (`layout="1column"`), `catalog_category_view` and `customer_account` (`2columns-left`), `checkout_index_index` (`layout="checkout"`, a page layout `Magento_Checkout` declares itself). The framework adds body classes from the handle and layout: `catalog-product-view page-layout-1column`.

## Debugging

- **Template hints**: `bin/magento dev:template-hints:enable` (sets `dev/debug/template_hints_storefront`) then `bin/magento cache:clean config full_page`; each block is outlined with its template path and, with `dev/debug/template_hints_blocks`, the block class. `dev/debug/template_hints_storefront_show_with_parameter` + `?templatehints=magento` limits it to URLs carrying the parameter. Hints only render when `dev/restrict/allow_ips` allows the client (empty = everyone), and the whole *Advanced › Developer* config section is hidden in production mode — use `bin/magento config:set` there. Disable with `dev:template-hints:disable`.
- **Which files declared a block**: search `grep -rn 'name="page.main.title"' vendor/magento app/design app/code --include=*.xml`; the element's final shape is the merge of every hit in the order above.
- **The merged XML**: `$block->getLayout()->getUpdate()->asString()` (temporarily, in a template) dumps the merged instructions for the current handles; `getUpdate()->getHandles()` lists the handles themselves.
- **Nothing renders**: check the container name exists on that handle (a 1-column page has no `sidebar.main`), that the block is not `remove`d by a later file, that `ifconfig` is true for the current store, and — for a missing ViewModel class or template — `var/log/system.log` (production swallows block-generation exceptions and renders an empty block; developer mode throws them).
- **Caches**: `bin/magento cache:clean layout block_html full_page` after any layout change; `config` as well when `ifconfig` values changed. The `layout` type caches both the collection of every layout file for the theme and each handle set's merged result, so a new file and an edited one alike stay invisible until it is cleaned.

## Sources

- https://developer.adobe.com/commerce/frontend-core/guide/layouts/ — Layouts overview (three file types, module → theme processing order, extend vs override)
- https://developer.adobe.com/commerce/frontend-core/guide/layouts/types — Layout file types (locations, root elements, "page layouts feature only containers", standard page layouts and `layouts.xml`, `layout` attribute)
- https://developer.adobe.com/commerce/frontend-core/guide/layouts/xml-instructions — Layout instructions (`block`, `container`, `referenceBlock`/`referenceContainer` with `remove`/`display`, `move`, `update`, `action` deprecated, argument `xsi:type` list, `shared="false"`, `translate`, `before`/`after` with `-`, `ifconfig`, `cacheable`)
- https://developer.adobe.com/commerce/frontend-core/guide/layouts/xml-manage — Common layout customization tasks (`layout` attribute, `<css>`/`<script>`/`<link>` with `src_type="url"`, `<remove src>`, `<meta>`, body `<attribute>`, view models as object arguments, template priority, selectable layouts)
- https://developer.adobe.com/commerce/frontend-core/guide/layouts/extend — Extend a layout (`<theme_dir>/<Namespace>_<Module>/layout/<layout>.xml`, handle ID = file name)
- https://developer.adobe.com/commerce/frontend-core/guide/layouts/override — Override a layout (`layout/override/base/` and `layout/override/theme/<Parent_Vendor>/<parent_theme>/`, when not to override)
- https://developer.adobe.com/commerce/frontend-core/guide/layouts/product-layouts — Product layouts (`catalog_product_view_type_*`, `_id_`, `_sku_` handles)
- https://developer.adobe.com/commerce/frontend-core/guide/themes/debug — Template path hints (admin path, `dev:template-hints:enable|disable`, `?templatehints=magento`, `cache:clean config full_page`)
- https://developer.adobe.com/commerce/php/development/cache/page/private-content — Private content (why `cacheable="false"` is wrong for per-customer blocks)
