# Module scaffold

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Example vendor is `Acme`; module `Acme_Catalog` lives at `app/code/Acme/Catalog`. Rules cited by ID are in `magento:conventions`.

## Minimal module (three files)

A module is registered by `registration.php`, declared by `etc/module.xml`, and (for Composer-installed modules) described by `composer.json`. Nothing else is required.

`app/code/Acme/Catalog/registration.php`:

```php
<?php
declare(strict_types=1);

use Magento\Framework\Component\ComponentRegistrar;

ComponentRegistrar::register(ComponentRegistrar::MODULE, 'Acme_Catalog', __DIR__);
```

`app/code/Acme/Catalog/etc/module.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Module/etc/module.xsd">
    <module name="Acme_Catalog">
        <sequence>
            <module name="Magento_Catalog"/>
            <module name="Magento_Sales"/>
        </sequence>
    </module>
</config>
```

- `name` is `<Vendor>_<Module>` and must match the PSR-4 namespace `Acme\Catalog` and the directory `app/code/Acme/Catalog`.
- `<sequence>` lists modules that must load *before* this one. It governs the merge order of configuration (`di.xml`, `events.xml`, layout) and the order of setup classes. List every module whose classes, events, layout handles or config you rely on (A8). No `setup_version` attribute: it is still accepted by `module.xsd` but no longer needed since declarative schema and patches (2.3+).
- Adding a module to `<sequence>` does **not** install it. Composer `require` does that (next section).

`app/code/Acme/Catalog/composer.json` (optional for `app/code`, required for a Composer package):

```json
{
    "name": "acme/module-catalog",
    "description": "Acme catalog customisations",
    "type": "magento2-module",
    "version": "1.0.0",
    "license": "MIT",
    "require": {
        "php": "~8.1.0||~8.2.0||~8.3.0||~8.4.0||~8.5.0",
        "magento/framework": "*",
        "magento/module-catalog": "*",
        "magento/module-sales": "*"
    },
    "autoload": {
        "files": ["registration.php"],
        "psr-4": {"Acme\\Catalog\\": ""}
    }
}
```

- `type` must be `magento2-module`; `autoload.files` must include `registration.php` so Composer's autoloader registers the module; `psr-4` maps the namespace to the package root.
- Modules under `app/code` are autoloaded by the project's root `composer.json` (its PSR-0 fallback maps `""` to `app/code/` and `generated/code/`) and registered by `app/etc/NonComposerComponentRegistration.php`, so their own `composer.json` is informative only. Keep it anyway: it documents dependencies (A8) and is what you publish if the module moves to `vendor/`.
- PHP support by release (Adobe system requirements): 2.4.4–2.4.5 → 8.1; 2.4.6 → 8.1–8.2; 2.4.7 → 8.2–8.3; 2.4.8 → 8.3–8.4; 2.4.9 → `magento/framework` requires `~8.3.0||~8.4.0||~8.5.0` and Adobe lists 8.5. Tighten the module's constraint to the releases you test on.

## Directory conventions

Every directory is optional; create it when you need it. Names are PSR-4 segments under `Acme\Catalog\`.

| Directory | Holds |
|---|---|
| `Api/` | Service contracts: `*Interface` (operations) and `Api/Data/*Interface` (DTOs) other modules may depend on (A4) |
| `Model/` | Models, resource models (`Model/ResourceModel/`), collections, repository implementations, config readers |
| `Plugin/` | Interceptor classes (`before*/around*/after*` methods), one class per subject |
| `Observer/` | Classes implementing `Magento\Framework\Event\ObserverInterface` |
| `Controller/` | `Controller/<Route>/<Action>.php` (frontend), `Controller/Adminhtml/<Route>/<Action>.php` (admin) |
| `Block/` | Block classes; prefer ViewModels for new presentation logic (L2) |
| `ViewModel/` | Classes implementing `Magento\Framework\View\Element\Block\ArgumentInterface`, injected into blocks through layout `<argument name="view_model" xsi:type="object">` |
| `Console/Command/` | `bin/magento` commands (see `cron-and-cli.md`) |
| `Cron/` | Cron job classes (see `cron-and-cli.md`) |
| `Setup/Patch/Data/`, `Setup/Patch/Schema/` | Data and schema patches (A6; see `magento:data`) |
| `etc/` | Global config: `module.xml`, `di.xml`, `events.xml`, `acl.xml`, `db_schema.xml`, `crontab.xml`, `webapi.xml`, `config.xml` |
| `etc/frontend/`, `etc/adminhtml/`, `etc/webapi_rest/`, `etc/webapi_soap/`, `etc/graphql/`, `etc/crontab/` | Area-scoped `di.xml`, `events.xml`, `routes.xml`; `etc/adminhtml/menu.xml` and `system.xml` |
| `view/frontend/`, `view/adminhtml/`, `view/base/` | `layout/`, `templates/`, `web/`, `ui_component/`, `requirejs-config.js` per area |
| `i18n/` | `en_US.csv` and other locale CSVs (Q5) |
| `Test/Unit/`, `Test/Integration/` | PHPUnit tests mirroring the source tree (Q3) |

`Helper/` exists in core but is a legacy grab-bag; put logic in a service class under `Model/` or a ViewModel instead.

## Frontend controller

Route: `etc/frontend/routes.xml` declares a front name; the URL `/<frontName>/<controller>/<action>` maps to `Controller/<Controller>/<Action>.php`. Missing segments default to `index`.

`app/code/Acme/Catalog/etc/frontend/routes.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:App/etc/routes.xsd">
    <router id="standard">
        <route id="acme_catalog" frontName="acme">
            <module name="Acme_Catalog"/>
        </route>
    </router>
</config>
```

`app/code/Acme/Catalog/Controller/Badge/Index.php` (GET, renders a page — `/acme/badge/index`):

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Controller\Badge;

use Magento\Framework\App\Action\HttpGetActionInterface;
use Magento\Framework\Controller\ResultInterface;
use Magento\Framework\View\Result\PageFactory;

class Index implements HttpGetActionInterface
{
    public function __construct(
        private readonly PageFactory $pageFactory
    ) {
    }

    public function execute(): ResultInterface
    {
        return $this->pageFactory->create();
    }
}
```

`app/code/Acme/Catalog/Controller/Badge/Save.php` (POST, mutates state — S2):

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Controller\Badge;

use Magento\Framework\App\Action\HttpPostActionInterface;
use Magento\Framework\App\RequestInterface;
use Magento\Framework\Controller\Result\RedirectFactory;
use Magento\Framework\Controller\ResultInterface;
use Magento\Framework\Message\ManagerInterface;

class Save implements HttpPostActionInterface
{
    public function __construct(
        private readonly RequestInterface $request,
        private readonly RedirectFactory $redirectFactory,
        private readonly ManagerInterface $messageManager
    ) {
    }

    public function execute(): ResultInterface
    {
        $sku = (string) $this->request->getParam('sku', '');
        // ... call a service class; never put business logic in the controller
        $this->messageManager->addSuccessMessage(__('Badge saved for %1.', $sku));
        return $this->redirectFactory->create()->setPath('acme/badge/index');
    }
}
```

- Implement the `Http<Method>ActionInterface` for the verb the action accepts (`Get`, `Post`, `Put`, `Delete`, …); the router rejects other verbs. Do not extend `Magento\Framework\App\Action\Action` in new code — inject `RequestInterface` and result factories instead (A9).
- Form-key (CSRF) validation runs on POST automatically; implement `CsrfAwareActionInterface` only for a custom check (S2).
- Cast every request parameter before use (S6).

## Admin controller with ACL and menu

Admin controllers extend `Magento\Backend\App\Action` (which supplies `_isAllowed()` checking `static::ADMIN_RESOURCE` and the admin session/URL handling) and implement the verb interface. Declaring `ADMIN_RESOURCE` is mandatory (S1); the default inherited value is `Magento_Backend::admin`, which every admin user has.

`app/code/Acme/Catalog/etc/adminhtml/routes.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:App/etc/routes.xsd">
    <router id="admin">
        <route id="acme_catalog" frontName="acme_catalog">
            <module name="Acme_Catalog"/>
        </route>
    </router>
</config>
```

`app/code/Acme/Catalog/etc/acl.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Acl/etc/acl.xsd">
    <acl>
        <resources>
            <resource id="Magento_Backend::admin">
                <resource id="Magento_Catalog::catalog">
                    <resource id="Acme_Catalog::badges" title="Product Badges" translate="title" sortOrder="50">
                        <resource id="Acme_Catalog::badges_save" title="Save Badges" translate="title" sortOrder="10"/>
                    </resource>
                </resource>
            </resource>
        </resources>
    </acl>
</config>
```

- Resource IDs are `Vendor_Module::name`. Nest under an existing core resource (`Magento_Catalog::catalog`, `Magento_Sales::sales`, `Magento_Backend::content`, `Magento_Backend::stores`) so the permission appears in the right place in *System > Permissions > User Roles*.
- Config sections in `system.xml` and REST routes in `webapi.xml` reference the same IDs (Q6, S1).

`app/code/Acme/Catalog/etc/adminhtml/menu.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:module:Magento_Backend:etc/menu.xsd">
    <menu>
        <add id="Acme_Catalog::badges" title="Product Badges" translate="title" module="Acme_Catalog"
             parent="Magento_Catalog::inventory" sortOrder="50" action="acme_catalog/badge/index"
             resource="Acme_Catalog::badges"/>
    </menu>
</config>
```

`<add>` attributes: `id`, `title`, `module`, `resource` are required; `parent` places it under an existing menu item; `action` is `<frontName>/<controller>/<action>`; `sortOrder`, `translate`, `dependsOnModule`, `dependsOnConfig` are optional.

`app/code/Acme/Catalog/Controller/Adminhtml/Badge/Index.php` (`/admin/acme_catalog/badge/index`):

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Controller\Adminhtml\Badge;

use Magento\Backend\App\Action;
use Magento\Backend\App\Action\Context;
use Magento\Framework\App\Action\HttpGetActionInterface;
use Magento\Framework\Controller\ResultInterface;
use Magento\Framework\View\Result\PageFactory;

class Index extends Action implements HttpGetActionInterface
{
    public const ADMIN_RESOURCE = 'Acme_Catalog::badges';

    public function __construct(
        Context $context,
        private readonly PageFactory $pageFactory
    ) {
        parent::__construct($context);
    }

    public function execute(): ResultInterface
    {
        $page = $this->pageFactory->create();
        $page->setActiveMenu('Acme_Catalog::badges');
        $page->getConfig()->getTitle()->prepend(__('Product Badges'));
        return $page;
    }
}
```

A `Save` action follows the same pattern with `HttpPostActionInterface`, `ADMIN_RESOURCE = 'Acme_Catalog::badges_save'`, and `$this->resultRedirectFactory->create()->setPath('*/*/index')` (the redirect factory comes from `Context`). Admin POSTs are form-key checked by `Magento\Backend\App\Request\BackendValidator` (the adminhtml `CsrfRequestValidator`) before the action runs; there is nothing extra to add.

The page needs a layout handle `view/adminhtml/layout/acme_catalog_badge_index.xml` (route id + controller + action) — see `magento:frontend-luma` for layout XML.

## ViewModel

Presentation logic for a template goes in a ViewModel, not a Block subclass (L2):

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\ViewModel;

use Magento\Framework\View\Element\Block\ArgumentInterface;

class Badge implements ArgumentInterface
{
    public function labelFor(float $price): string
    {
        return $price > 100 ? 'premium' : 'standard';
    }
}
```

Wire it in layout XML: `<block name="..." template="Acme_Catalog::badge.phtml"><arguments><argument name="view_model" xsi:type="object">Acme\Catalog\ViewModel\Badge</argument></arguments></block>`; the template reads `$block->getData('view_model')`. ViewModels are ordinary injectable classes: constructor-inject repositories and config readers.

## Enabling and verifying

```bash
bin/magento module:enable Acme_Catalog
bin/magento setup:upgrade          # registers the module in app/etc/config.php and runs patches
bin/magento module:status Acme_Catalog
bin/magento cache:clean            # after any etc/*.xml change in developer/default mode
```

- `setup:upgrade` is required once per new module; it writes `'Acme_Catalog' => 1` to `app/etc/config.php`. Commit that file.
- Production mode additionally needs `bin/magento setup:di:compile` and `setup:static-content:deploy` (or `deploy:mode:set production`, which runs both).
- If the module does not show in `module:status`, check `registration.php` is reachable (for `app/code` it is picked up automatically; for `vendor/` run `composer dump-autoload`) and that the name in `module.xml` matches.

## Checklist before you finish

- `declare(strict_types=1);` on every PHP file; typed properties/params/returns (Q2).
- Every core module referenced in code, `events.xml` or layout is in `<sequence>` (A8).
- No `ObjectManager` anywhere (A1); no `new` for injectable classes (A9).
- Admin controllers: `ADMIN_RESOURCE` + `acl.xml` + `menu.xml` all name the same resource (S1).
- `vendor/bin/phpcs --standard=Magento2 app/code/Acme/Catalog` is clean (Q1).

## Sources

- https://experienceleague.adobe.com/en/docs/commerce-learn/tutorials/backend-development/create-module — Create a module (folder, `module.xml`, `registration.php`, `setup:upgrade`)
- https://developer.adobe.com/commerce/php/development/build/component-registration — Register a component (`ComponentRegistrar::register` for module, theme, language, library)
- https://developer.adobe.com/commerce/php/development/build/component-load-order — Component load order (`module.xml` `<sequence>` and its relation to `composer.json` `require`)
- https://developer.adobe.com/commerce/php/development/build/composer-integration — Composer integration (`type: magento2-module`, `autoload.files`, `psr-4`)
- https://developer.adobe.com/commerce/php/development/build/component-file-structure — Component file structure (directory names and meanings)
- https://developer.adobe.com/commerce/php/development/build/component-management — Enable or disable a component (`module:enable`, `setup:upgrade`, `cache:clean`, `module:status`)
- https://developer.adobe.com/commerce/php/development/components/routing — Routing (`routes.xsd`, `standard`/`admin` routers, `Http*ActionInterface`, example controller)
- https://developer.adobe.com/commerce/php/tutorials/backend/create-access-control-list-rule — Create Access Control List rules (`acl.xsd`, resource IDs, `ADMIN_RESOURCE`, `menu.xsd`)
- https://developer.adobe.com/commerce/php/tutorials/admin/create-admin-page — Create an Admin page (admin `routes.xml`, `menu.xml`, controller extending `Magento\Backend\App\Action` with `HttpGetActionInterface`)
- https://developer.adobe.com/commerce/php/development/components/view-models — View models (`ArgumentInterface`, layout `view_model` argument)
- https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/system-requirements — System requirements (PHP versions per release)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/set-mode — Set the operation mode (`deploy:mode:set production` runs compile and static deploy)
