# Theme structure, LESS, grunt and static content deploy

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magekwik-magento:conventions` (L4 and L5 apply throughout).

Luma styling is LESS compiled per theme and locale into two CSS files. Nothing is committed under `pub/static` or `var/view_preprocessed` (L5): those directories are build output, regenerated on demand in developer/default mode and by `setup:static-content:deploy` in production.

## Theme skeleton

```
app/design/frontend/Acme/default/
├── registration.php          ComponentRegistrar::register(ComponentRegistrar::THEME, 'frontend/Acme/default', __DIR__);
├── theme.xml                 <title>Acme Default</title> <parent>Magento/luma</parent> <media><preview_image>media/preview.jpg</preview_image></media>
├── composer.json             optional; type "magento2-theme", require magento/theme-frontend-luma
├── etc/view.xml              catalog image sizes, JS bundling <exclude>/bundle_size, other vars
├── i18n/en_US.csv            theme-level translations
├── media/preview.jpg
├── web/
│   ├── css/source/_theme.less    variable overrides (replaces Luma's file — copy what you keep)
│   ├── css/source/_extend.less   extra rules, included by @magento_import
│   ├── images/logo.svg           picked up automatically by the header logo block
│   ├── js/                       theme-level RequireJS modules (id `js/<name>`)
│   └── fonts/
├── requirejs-config.js       theme-level RequireJS config (see requirejs-knockout.md)
└── Magento_Catalog/          per-module overrides: layout/, templates/, web/css/source/_module.less, web/js, web/template
```

`theme.xml` allows exactly `title`, optional `parent` and optional `media/preview_image`; the parent chain (`Acme/default` → `Magento/luma` → `Magento/blank`) is what every fallback (templates, layout, static files, LESS) walks. The theme is registered in the database by `bin/magento setup:upgrade` (a recurring setup step of `Magento_Theme`) and, outside production mode, by any admin page load; then assign it under *Content › Design › Configuration*. Blank is the base theme (all mixins, structure, `styles-m.less`/`styles-l.less`); Luma is a child of blank that overrides variables and per-module `_module.less` files — inherit from Luma to get the demo look, from blank for a design of your own.

## The LESS pipeline

The root sources in `Magento/blank/web/css/` are what `default_head_blocks.xml` links:

| File | Compiles to | Contents |
|---|---|---|
| `styles-m.less` | `styles-m.css` (all devices, mobile first) | `source/_reset.less`, `_styles.less` (lib + theme + components), `//@magento_import 'source/_module.less'`, `//@magento_import 'source/_widgets.less'`, `source/_theme.less`, `//@magento_import 'source/_extend.less'`, `source/lib/_responsive.less` with `@media-target: 'mobile'` |
| `styles-l.less` | `styles-l.css` (`media="screen and (min-width: 768px)"`) | The same imports with `@media-target: 'desktop'` and `@media-common: false` |
| `print.less`, `email.less`, `email-inline.less` | print / transactional email CSS | |

`//@magento_import 'source/_module.less';` is a Magento pre-processing instruction (note the comment syntax, so plain LESS tools ignore it). It expands to one `@import 'Vendor_Module::source/_module.less';` for every module that has `view/frontend/web/css/source/_module.less`, each resolved through the theme fallback — so `app/design/frontend/Acme/default/Magento_Catalog/web/css/source/_module.less` *replaces* `Magento_Catalog`'s file for this theme. The same instruction with `source/_extend.less` collects every module's `_extend.less` **and** the theme-level `web/css/source/_extend.less` (theme files override `lib/web` files of the same path, last theme in the chain wins). `//@magento_import (reference) '…';` imports mixins without emitting rules. With the `static_content_only_enabled_modules` `env.php` flag set, disabled modules are skipped.

Server-side steps for `css/styles-m.css`: no CSS file exists → the resolver looks for `css/styles-m.less` → the pre-processor chain (`magento_import`, then `import` which rewrites `Vendor_Module::` notation) copies every resolved file into `var/view_preprocessed/pub/static/frontend/Acme/default/en_US/css/…` → `wikimedia/less.php` (`Less_Parser`) compiles it (source maps and no compression in developer mode) → the CSS is published to `pub/static/frontend/Acme/default/en_US/css/styles-m.css`. A LESS error aborts publication: the browser gets a 404 for the CSS whose body, in developer mode, is the less.php message and trace; production logs it (critical) and serves the standard 404. Nothing was written, so fixing the file and reloading recompiles.

## Three places for your styles (L4)

1. `web/css/source/_extend.less` — rules added on top of Luma. Included by `@magento_import` into **both** root files, so structure it with the responsive mixins (below) or the same rule ships twice.
2. `web/css/source/_theme.less` — variable overrides only (`@primary__color: #123456;`). A plain `@import 'source/_theme.less'` resolves through the fallback, so your file *replaces* Luma's `_theme.less`; copy the declarations you still want from `vendor/magento/theme-frontend-luma/web/css/source/_theme.less` first.
3. `<Vendor>_<Module>/web/css/source/_module.less` in the theme — replaces that module's stylesheet (Luma does this for `Magento_Catalog`, `Magento_Checkout`, …); `_extend.less` in the same directory adds to it instead. For a module you own, put styles in the module's `view/frontend/web/css/source/_module.less` so they ship with it.

The same-path rule cuts both ways: if a parent theme already has `web/css/source/_extend.less`, yours replaces it — copy its content in.

## Responsive structure

`lib/web/css/source/lib/_responsive.less` defines `.media-width(@extremum, @break)` and calls it for every breakpoint; what you write are *guards* on that mixin, collected into the right media query in the right file:

```less
//  web/css/source/_extend.less
& when (@media-common = true) {                                   // common styles: styles-m.css only (styles-l.less sets @media-common: false)
    .acme-shipping-notice {
        .lib-css(background, @primary__color);
        .lib-css(color, @color-white);
        .lib-font-size(13);
        .lib-line-height(18);
        font-weight: @font-weight__semibold;
        padding: @indent__xs @indent__s;
        text-align: center;
    }
}

.media-width(@extremum, @break) when (@extremum = 'max') and (@break = @screen__m) {   // styles-m.css, max-width: 767px
    .acme-shipping-notice { .lib-font-size(12); }
}

.media-width(@extremum, @break) when (@extremum = 'min') and (@break = @screen__m) {   // styles-l.css, min-width: 768px
    .acme-shipping-notice { padding: @indent__s @indent__base; }
}
```

Breakpoints: `@screen__xxs: 320px`, `@screen__xs: 480px`, `@screen__s: 640px`, `@screen__m: 768px`, `@screen__l: 1024px`, `@screen__xl: 1440px`. `'max'` guards up to `@screen__m` land in `styles-m.css` (as `max-width: @break - 1`), `'min'` for `@screen__s` also in `styles-m.css`; `'min'` guards for `@screen__m` and above and the `'max', @screen__l` guard land in `styles-l.css` (with `print`). Rules outside any guard are emitted wherever the file is imported — in both CSS files.

## UI library

`lib/web/css/source/lib/` is imported by `_styles.less`; every mixin starts with `.lib-`, variables live in `lib/variables/*.less` and follow `@<component>__<property>` (`@button__color`, `@link__hover__color`, `@form-element-input__border`). Frequently used:

| Mixin | Use |
|---|---|
| `.lib-css(@property, @value, @prefix: 0)` | Emit `property: value` only when `@value` is not `false`/`''` — the idiom for optional theme variables; `@prefix: 1` adds `-webkit-`/`-moz-`/`-ms-` |
| `.lib-font-size(13)`, `.lib-line-height(18)` | px input → `rem` output (`@font-size-unit-ratio`) |
| `.lib-button()`, `.lib-button-primary()`, `.lib-button-as-link()`, `.lib-link-as-button()`, `.lib-button-reset()` | Buttons from the `@button__*` variables |
| `.lib-link()`, `.lib-heading(h2)`, `.lib-typography()` | Text styles |
| `.lib-icon-font(@content, @size, @color, …)`, `.lib-icon-font-symbol(@content)` | Luma-Icons glyphs (`@icon-cart`, `@icon-search`, …) |
| `.lib-message(info|error|success|warning|notice)` | Message boxes |
| `.lib-clearfix()`, `.lib-visually-hidden()`, `.lib-list-reset-styles()`, `.lib-text-hide()` | Utilities |
| `.lib-vendor-prefix-display(flex)`, `.lib-vendor-prefix-flex-grow(1)` | Prefixed flexbox |
| `.lib-layout-column()`, `.lib-column-width()` | Grid helpers |

Variables you will reach for: `@color-white`, `@color-black`, `@color-gray*`, `@primary__color` (and `__dark`/`__light`), `@theme__color__primary`, `@link__color`, `@text__color`, `@font-family__base`, `@font-size__base` (14px), `@font-size__s`/`__l`, `@font-weight__regular|semibold|bold`, `@line-height__base`, `@indent__base` (20px) with `__xs` 5, `__s` 10, `__m` 25, `__l` 30, `__xl` 40, `@layout__max-width` (1280px), `@button__*`, `@form-element-input__*`. Read the docs shipped with the library (`lib/web/css/docs/source/README.md`) before inventing a variable.

## Compilation mode and grunt

`dev/front_end_development_workflow/type` (*Stores › Configuration › Advanced › Developer › Frontend development workflow*, developer mode only — the section is hidden in production) is `server_side_compilation` by default and the only option in production; `client_side_compilation` serves the `.less` files and compiles them in the browser with less.js, so edits show on reload without deleting anything but pages load slowly and `@magento_import` still needs the server pre-processing step. Most teams keep server-side compilation and use grunt:

```bash
cp package.json.sample package.json && cp Gruntfile.js.sample Gruntfile.js && cp grunt-config.json.sample grunt-config.json
npm install
```

`grunt-config.json` points `themes` at `dev/tools/grunt/configs/local-themes.js`; create it with your theme (keep `blank`/`luma` if you compile them too):

```js
module.exports = {
    acme: { area: 'frontend', name: 'Acme/default', locale: 'en_US', files: ['css/styles-m', 'css/styles-l'], dsl: 'less' }
};
```

| Task | What it does |
|---|---|
| `grunt clean:acme` | Deletes `pub/static/frontend/Acme/default/en_US/`, the matching `var/view_preprocessed/less` and `/source` trees, `var/cache` and `pub/static/deployed_version.txt` |
| `grunt exec:acme` | `clean:acme`, then `php bin/magento dev:source-theme:deploy css/styles-m css/styles-l --type=less --locale=en_US --area=frontend --theme=Acme/default`, which publishes the resolved LESS sources (symlinks) under `pub/static/…/en_US/css/` |
| `grunt less:acme` | Compiles `pub/static/…/css/styles-m.less` and `styles-l.less` to CSS with node `less` (source maps on) |
| `grunt watch:acme` (or `grunt watch`) | Recompiles on every change under that theme's `pub/static` sources; the `reload` target drives LiveReload |
| `grunt refresh` | `clean` + `exec:all` + `less` for every configured theme |
| `grunt exec` again | After switching compilation mode, changing a root file, adding a *new* `@import`/`@magento_import` target or file, moving files, or `setup:upgrade` |

Grunt compiles with less.js while the storefront compiles with less.php; the output is meant to match, but a syntax that one accepts and the other rejects shows up as a working `grunt less` and a 404 for the CSS on the server — always load the page once through Magento's own pipeline before shipping.

## Static content and what to delete

- **Developer / default mode**: a request for a missing file under `pub/static` is rewritten by `pub/static/.htaccess` (or the nginx `location /static/` block) to `static.php`, which finds the source through the fallback and materialises it: symlink for source files (JS, images, fonts, `.html` templates), copy for anything produced in `var/view_preprocessed` (compiled CSS). Existing files are never touched again, so after a LESS edit delete `pub/static/frontend/Acme/default/en_US/css/` and `var/view_preprocessed/pub/static/frontend/Acme/default/en_US/css/` (or the whole theme directories) and reload; JS edits show through the symlink (hard-refresh for the browser cache). Minification and merging are ignored in developer mode.
- **Production**: `static.php` answers 404 (unless `static_content_on_demand_in_production` is set in `env.php`). Deploy: `bin/magento setup:static-content:deploy --theme Acme/default --area frontend en_US de_DE` (`-l`/`--language` also accepted; `--jobs 4` parallelises; `--strategy standard|quick|compact`, default `quick`; `--no-parent` skips parent themes; `--no-javascript`, `--no-css`, `--no-less`, `--no-images`, `--no-fonts`, `--no-html`, `--no-misc`, `--no-html-minify`; `--content-version` and `--refresh-content-version-only` for multi-node roll-outs; `--symlink-locale` shares unchanged locales). Without `-f` the command refuses to run in developer/default mode ("Manual static content deployment is not required…"). The docs' sequence is to empty `pub/static` (keep `.htaccess`) and `var/view_preprocessed` first so stale files do not survive.
- `dev/static/sign` (default 1) puts `version<timestamp>` from `pub/static/deployed_version.txt` into every static URL; deploy rewrites the file, developer/default modes create it when missing, and production without it throws `Unable to retrieve deployment version of static files from the file system`. The web server strips the segment (`RewriteRule ^version.+?/(.+)$ $1`), so changing the version is how browser caches are busted — never by renaming files.
- `dev/css/minify_files`, `dev/js/minify_files`, `dev/css/merge_css_files`, `dev/js/merge_files`, `dev/js/enable_js_bundling`, `dev/template/minify_html` are production-time switches applied by static deploy or on first request; change them with `bin/magento config:set` and redeploy. `dev/css/use_css_critical_path` inlines the theme's `web/css/critical.css` and defers the rest.
- Never commit `pub/static/*` (except `.htaccess`), `var/view_preprocessed`, `pub/static/deployed_version.txt`, `generated/` (L5); `.gitignore` in the project skeleton already lists them.

## `etc/view.xml`

Theme-level configuration read by modules: `<images module="Magento_Catalog"><image id="category_page_grid" type="small_image"><width>240</width><height>300</height></image>…</images>` sizes product images per placement (`id` values are what `$block->getImage($product, 'category_page_grid')` / `Magento\Catalog\Block\Product\ImageFactory::create()` look up), `<vars module="Magento_Catalog">` carries module-specific values (gallery options), and `<exclude><item type="file">Lib::jquery/jquery.min.js</item></exclude>` plus `<var name="bundle_size">1MB</var>` control JS bundling. `Magento\Framework\Config\View::read()` merges every ancestor's `view.xml` under yours with `array_replace_recursive`, so a theme without the file inherits Luma's and a theme with one only needs the entries it changes — do not copy the whole parent file.

## Sources

- https://developer.adobe.com/commerce/frontend-core/guide/themes/create-storefront — Create a storefront theme (directory, `theme.xml`, `registration.php`, optional `composer.json`, `etc/view.xml`, `web/images/logo.svg`, apply in admin, clear `pub/static` and `var/view_preprocessed` or deploy)
- https://developer.adobe.com/commerce/frontend-core/guide/css/preprocess — CSS and LESS preprocessing (server-side default and only option in production, client-side in the browser, `//@magento_import` expansion, `var/view_preprocessed/less`, publication to `pub/static/frontend/<Vendor>/<theme>/<locale>`, root files and `_module.less`/`_widgets.less`/`_extend.less`)
- https://developer.adobe.com/commerce/frontend-core/guide/css/quickstart/customize-styles — Customize theme styles (`_extend.less` precedence over `_theme.less`, child `_theme.less` replaces the parent's so copy its variables, child `_extend.less` overrides a parent's, module `_extend.less` vs `_module.less`)
- https://developer.adobe.com/commerce/frontend-core/guide/css/ui-library — UI library (`lib/web/css/source/lib/`, `.lib-` mixins, `.media-width()` with `@media-common`, variable naming, embedded docs)
- https://developer.adobe.com/commerce/frontend-core/guide/tools/grunt — Grunt (developer/default mode, copy the three `.sample` files, `npm install`, `local-themes.js` keys, `grunt exec:<theme>` republishes symlinks, `grunt watch:<theme>`)
- https://developer.adobe.com/commerce/frontend-core/guide/css/debug — Compile LESS with grunt (`grunt less`, `grunt exec` after mode/root/import changes and `setup:upgrade`, `grunt watch` with LiveReload, `grunt clean`, source maps, server-side compilation is the default)
- https://developer.adobe.com/commerce/frontend-core/guide/themes/js-bundling — JavaScript bundling (production only, `etc/view.xml` `<exclude>` and `bundle_size`, `dev/js/*` config paths, redeploy)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/static-view/static-view-file-deployment — Deploy static view files (on-demand generation in default/developer mode, `-f`, `--theme`, `--area`, `--language`, `--jobs`, strategies with `quick` as default, `--no-*` switches, `--content-version`, `--symlink-locale`, `--no-parent`, output path, `deployed_version.txt`, empty `pub/static` first)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/setup/application-modes — Application modes (developer mode writes static files to `pub/static` on demand; production serves only deployed files and shows no errors)
