---
name: module
description: Build and modify Magento 2 modules — scaffolding, di.xml plugins/preferences/virtual types, events and observers, ViewModels, cron jobs, console commands and admin controllers with ACL. Use when adding or changing backend behaviour in Magento Open Source 2.4.
---

# Magento 2 modules

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).*

Rules: see `magekwik-magento:conventions` A1–A10, P6, S1. This skill cites them by ID and does not restate them.

## When to use

- Adding or changing backend behaviour in a new or existing `app/code/<Vendor>/<Module>` module.
- Intercepting a core or third-party public method (plugin) or swapping an implementation (preference).
- Reacting to something that happened (order placed, entity saved, customer registered) with an observer.
- Scheduled work (cron) or developer/ops commands (`bin/magento` console commands).
- Admin actions: controllers, ACL resources, menu entries; frontend controllers and routes.
- Wiring a ViewModel or any other class through `di.xml` (arguments, virtual types, proxies, factories).

## When not to

- Database schema, data patches, models/resource models/collections, repositories, EAV or extension attributes → `magekwik-magento:data`.
- REST or GraphQL endpoints, `webapi.xml`, integration tokens → `magekwik-magento:api`.
- Templates, layout XML, JavaScript, CSS → `magekwik-magento:frontend-luma` or `magekwik-magento:frontend-hyva`.

## Decision guide

| Need | Use | Reference |
|---|---|---|
| Change a public method's input, output or behaviour | Plugin (`before`/`after`; `around` only to skip the original) | `plugins-vs-observers.md` |
| Replace an interface implementation everywhere | `preference` in `di.xml` (last resort) | `di-xml.md` |
| Same class, different constructor args | Virtual type | `di-xml.md` |
| React after something happened (order placed, entity saved) | Observer + `events.xml` (area-scoped) | `plugins-vs-observers.md` |
| Add data to an entity for other modules/APIs | Extension attribute | `magekwik-magento:data` |
| Scheduled work | Cron job + `crontab.xml` group | `cron-and-cli.md` |
| Developer/ops command | `Console/Command` + `di.xml` `commandList` | `cron-and-cli.md` |
| Admin action | Controller with `ADMIN_RESOURCE` + `acl.xml` + `menu.xml` | `scaffold.md` |

Two quick tests: *"Do I need to change what a method receives or returns?"* → plugin. *"Do I only need to know that it happened?"* → observer. Never a preference for either.

## Rules that bite

1. **A1** — No `ObjectManager::getInstance()` and no injected `ObjectManagerInterface`; every dependency (including `Psr\Log\LoggerInterface`) is a typed constructor parameter.
2. **A2** — Plugins cannot target `final` classes/methods, `private`/`protected` methods, `static` methods or `__construct`; an `around` plugin must call `$proceed(...)` or the original method and every later plugin are silently skipped.
3. **A3** — Observers return nothing and change nothing except through side effects; `execute()` is `void`, and if you find yourself wanting the return value you need a plugin.
4. **A8** — Every module you touch classes or events from goes in `etc/module.xml` `<sequence>` and, for Composer-installed modules, `composer.json` `require`.
5. **A9** — `new` only for value objects and exceptions; generated `XxxFactory` for models/DTOs, `\Xxx\Proxy` via `di.xml` (never type-hinted) for heavy dependencies.
6. **P6** — Every cron job is idempotent, bounded (page or limit its work) and in a named group; long jobs get their own group with `use_separate_process`.
7. **S1** — Every admin controller sets `public const ADMIN_RESOURCE = 'Acme_Catalog::something'` and that resource exists in `etc/acl.xml`; menu entries reference the same resource.
8. **A2** — Plugins run by `sortOrder`; each `around` nests every higher-sorted plugin's before/around/after inside its `$proceed` — see `plugins-vs-observers.md` for the exact chain.
9. **A8** — `etc/di.xml` is global; `etc/frontend/`, `etc/adminhtml/`, `etc/webapi_rest/`, `etc/graphql/`, `etc/crontab/` `di.xml` are area-scoped and merge on top of global (in `<sequence>` order), so an area file wins for that area; put plugins/preferences in the narrowest area that needs them.
10. **A3** — `events.xml` observers are singletons by default; declare `shared="false"` on any observer that keeps state between calls; scope the file to `etc/frontend/` or `etc/adminhtml/` when the event only matters there.
11. A plugin class is constructed by the object manager: constructor arguments must be injectable services or `di.xml`-configured values — no runtime values, no `ObjectManager`; keep hot-path plugins cheap (P4).
12. After adding a module: `bin/magento module:enable Acme_Catalog && bin/magento setup:upgrade`. After changing `di.xml`, `events.xml`, `crontab.xml` or `routes.xml` in developer mode: `bin/magento cache:clean config compiled_config` (plugin lists live in `compiled_config`); production mode also needs `setup:di:compile`.

## Minimal correct example

A `before` plugin on `ProductRepositoryInterface::save` that normalises the product name on every save.

`app/code/Acme/Catalog/etc/di.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:ObjectManager/etc/config.xsd">
    <type name="Magento\Catalog\Api\ProductRepositoryInterface">
        <plugin name="acme_catalog_normalize_product_name" type="Acme\Catalog\Plugin\NormalizeProductName" sortOrder="10"/>
    </type>
</config>
```

`app/code/Acme/Catalog/Plugin/NormalizeProductName.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Plugin;

use Magento\Catalog\Api\Data\ProductInterface;
use Magento\Catalog\Api\ProductRepositoryInterface;

class NormalizeProductName
{
    /**
     * Trim and collapse whitespace in the name before every save.
     *
     * @param bool $saveOptions
     * @return array{ProductInterface, bool}
     */
    public function beforeSave(ProductRepositoryInterface $subject, ProductInterface $product, $saveOptions = false): array
    {
        $name = $product->getName();
        if ($name !== null) {
            $product->setName(trim((string) preg_replace('/\s+/', ' ', $name)));
        }
        return [$product, $saveOptions];
    }
}
```

Why this shape: the plugin targets the *interface* so it fires for every implementation and every caller of the service contract (REST `POST /V1/products`, other modules' repositories, your own code) — but not for code that calls `$product->save()` on the model directly, as the admin product form does, or that bypasses the model altogether, as the CSV importer does (it writes through the resource model with `insertOnDuplicate`); `beforeSave` mirrors the subject's parameters after `$subject` — `save(ProductInterface $product, $saveOptions = false)` — without narrowing their types; no constructor is needed because the plugin has no dependencies. A `before` plugin returns the (possibly modified) argument list; return `null` to leave arguments untouched.

The same rules applied to an observer: `Observer/OrderPlacedLogger.php` implements `Magento\Framework\Event\ObserverInterface`, injects `Psr\Log\LoggerInterface` through its constructor, `execute(Observer $observer): void` reads `$observer->getEvent()->getData('order')` and logs; `etc/events.xml` binds it to `sales_order_place_after`. See `plugins-vs-observers.md` for the full listing.

## Routing table

| For | Read |
|---|---|
| New module files, directory layout, `composer.json`, admin/frontend controllers, ACL, menu, routes, enabling | `references/scaffold.md` |
| `type`/`virtualType`, argument types, `preference`, `plugin` attributes, area precedence, `shared`, proxies, factories, `commandList`, compile | `references/di-xml.md` |
| Plugin signatures and ordering, limitations, interface vs class targets; `events.xml`, observers, dispatching events, common core events | `references/plugins-vs-observers.md` |
| `crontab.xml`, cron groups, `cron:run`, `cron_schedule` states, idempotency; console command class and registration | `references/cron-and-cli.md` |
