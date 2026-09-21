# di.xml — dependency injection configuration

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magekwik-magento:conventions` (A1, A2, A9 apply throughout).

`di.xml` tells the object manager how to build classes: which implementation satisfies an interface (`preference`), what constructor arguments a class receives (`type`/`arguments`), named variants of a class (`virtualType`), and which interceptors wrap it (`plugin`). Every file starts:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:ObjectManager/etc/config.xsd">
    <!-- preference | type | virtualType -->
</config>
```

## Where the file lives — scope and precedence

| Path | Scope |
|---|---|
| `app/etc/di.xml` | Framework defaults (never edit) |
| `<module>/etc/di.xml` | Global — every area, including CLI and cron |
| `<module>/etc/frontend/di.xml` | Storefront requests |
| `<module>/etc/adminhtml/di.xml` | Admin requests |
| `<module>/etc/webapi_rest/di.xml`, `etc/webapi_soap/di.xml` | REST / SOAP requests |
| `<module>/etc/graphql/di.xml` | GraphQL requests |
| `<module>/etc/crontab/di.xml` | `bin/magento cron:run` (the `crontab` area) |

Load order is initial (`app/etc/di.xml`) → global → area. Later files merge on top: a `preference`, plugin or scalar argument declared in an area file replaces the global one for that area; `array` arguments with the same name are merged (items with the same key are replaced, new keys added). Across modules the order is `module.xml` `<sequence>` order (A8), so a module that must override another module's `di.xml` lists it in `<sequence>`.

Put a plugin, preference or argument in the narrowest area that needs it: an `adminhtml`-only plugin in `etc/adminhtml/di.xml` costs nothing on the storefront. Anything a CLI command or cron job relies on must be global or in `etc/crontab/di.xml`.

## `preference` — interface to implementation

```xml
<preference for="Acme\Catalog\Api\BadgeResolverInterface" type="Acme\Catalog\Model\BadgeResolver"/>
```

- Required for every interface your own code injects; without it object creation fails with PHP's *"Cannot instantiate interface ..."* error.
- Overriding a *core* preference (`<preference for="Magento\Catalog\Api\ProductRepositoryInterface" type="Acme\..."/>`) replaces the class for everyone; two modules doing it conflict and the last in `<sequence>` wins silently. Use it only to swap an implementation wholesale (A2); to change one method, write a plugin.
- If you must override, extend the original class so unlisted methods and future core additions keep working.

## `type` — configure a real class

```xml
<type name="Acme\Catalog\Model\BadgeResolver">
    <arguments>
        <argument name="threshold" xsi:type="number">100</argument>
        <argument name="label" xsi:type="string">premium</argument>
        <argument name="enabled" xsi:type="boolean">true</argument>
        <argument name="scope" xsi:type="const">Magento\Store\Model\ScopeInterface::SCOPE_STORE</argument>
        <argument name="logger" xsi:type="object">Psr\Log\LoggerInterface</argument>
        <argument name="rules" xsi:type="array">
            <item name="price" xsi:type="object">Acme\Catalog\Model\Rule\Price</item>
            <item name="stock" xsi:type="object">Acme\Catalog\Model\Rule\Stock</item>
        </argument>
        <argument name="appMode" xsi:type="init_parameter">Magento\Framework\App\State::PARAM_MODE</argument>
        <argument name="optional" xsi:type="null"/>
    </arguments>
</type>
```

`name` attributes match constructor parameter names exactly. Argument `xsi:type` values:

| `xsi:type` | Injects |
|---|---|
| `string` | The text (`translatable="true"` marks it for translation) |
| `number` | Int or float |
| `boolean` | `true`/`false` (also `1`/`0`) |
| `const` | The value of a class constant, written `Fully\Qualified\Class::CONST` |
| `object` | An instance of the named class, interface (resolved through `preference`) or virtual type; add `shared="false"` for a fresh instance |
| `array` | An array of `<item name="key" xsi:type="...">` entries; nested `array` items allowed; DI orders items by a `sortOrder="N"` *attribute* on `object`/`string` items — a nested `<item name="sortOrder">` entry (the core pool pattern) is sorted by the consuming pool class, not by DI |
| `init_parameter` | A bootstrap parameter (the `$params` passed to `Bootstrap::create`, e.g. `MAGE_MODE`) named by a constant, e.g. `Magento\Framework\App\State::PARAM_MODE` |
| `null` | `null` |

Typical uses: registering a class into a core pool (`<argument name="commands">`, `<argument name="handlers">`, `<argument name="pool">` arrays), tuning a scalar, swapping one dependency of one class for a proxy.

`<type ... shared="false">` makes every injection of that class a new instance (non-singleton); the default `shared="true"` means one instance per request. Use `shared="false"` for stateful objects that would otherwise leak state between callers; prefer a factory (below) when the caller decides when to create.

## `virtualType` — same class, different arguments

A virtual type is a *named* configuration of an existing class; no PHP file is generated. Use it when two consumers need the same class with different constructor arguments, or to give a core class a custom collaborator without a preference.

```xml
<virtualType name="Acme\Catalog\Model\BadgeResolver\Premium" type="Acme\Catalog\Model\BadgeResolver">
    <arguments>
        <argument name="threshold" xsi:type="number">500</argument>
        <argument name="label" xsi:type="string">luxury</argument>
    </arguments>
</virtualType>

<type name="Acme\Catalog\Block\Badge">
    <arguments>
        <argument name="resolver" xsi:type="object">Acme\Catalog\Model\BadgeResolver\Premium</argument>
    </arguments>
</type>
```

- `name` is any unique identifier; the namespaced form is convention. It can only be injected through `di.xml` (`xsi:type="object"`) or a factory argument — never type-hinted in PHP, because the class does not exist.
- Virtual types cannot be the target of a plugin (`<type name="...">` a virtual type's `name` is rejected by the interceptor); plugin the real class or interface instead.
- Common core pattern: a virtual `Collection` or `Grid\Collection` for a UI component data provider.

## `plugin` — interceptors

```xml
<type name="Magento\Catalog\Api\ProductRepositoryInterface">
    <plugin name="acme_catalog_normalize_product_name" type="Acme\Catalog\Plugin\NormalizeProductName" sortOrder="10" disabled="false"/>
</type>
```

| Attribute | Meaning |
|---|---|
| `name` | Required; unique per subject type. Another module can reference it to disable or reorder it |
| `type` | The plugin class (optional only when re-declaring an existing name to set `disabled`/`sortOrder`) |
| `sortOrder` | Integer; lower runs first. Plugins without one are treated as lowest and run first |
| `disabled` | `true` to switch off a plugin — yours or, by redeclaring its `name` under the same `type`, another module's |

- The plugin class needs no interface and no base class; the object manager constructs it, so its constructor takes injectable services only.
- `name` on `<type>` may be a class or an interface; an interface plugin applies to every implementation reached through the interface (A2). Method signatures, ordering and limitations: `plugins-vs-observers.md`.
- Disabling a core plugin: `<type name="Magento\Checkout\Model\Cart"><plugin name="the_core_plugin_name" disabled="true"/></type>` — find the name in the core module's `di.xml`.

## Proxies — lazy heavy dependencies

A proxy is a generated subclass (`\Original\Class\Proxy`) that instantiates the real object on first method call. Use one when a dependency is expensive to construct (opens sessions, loads collections, reads large config) and the consumer often does not use it — a frequently instantiated class such as a plugin, observer, block or ViewModel (A9, P4).

```xml
<type name="Acme\Catalog\Observer\OrderPlacedLogger">
    <arguments>
        <argument name="customerSession" xsi:type="object">Magento\Customer\Model\Session\Proxy</argument>
    </arguments>
</type>
```

- Type-hint the *real* class or interface in the constructor; the proxy extends/implements it. Never type-hint `\Proxy` in PHP (A9).
- Proxies of interfaces work too: `Magento\Catalog\Api\ProductRepositoryInterface\Proxy`.
- The core preference for `Psr\Log\LoggerInterface` is `Magento\Framework\Logger\LoggerProxy` (`app/etc/di.xml`), a lazy wrapper, so `LoggerInterface` is always cheap to inject.
- Generated on demand in developer/default mode into `generated/code/`; produced by `setup:di:compile` in production.

## Factories — creating non-injectable objects

Models, DTOs, collections, and anything that needs runtime data are *newable*, not injectable. Inject the generated factory (`\Class\NameFactory`) and call `create(array $data = [])`; never `new` them and never inject them directly (A9).

```php
public function __construct(
    private readonly \Magento\Catalog\Api\Data\ProductInterfaceFactory $productFactory,
    private readonly \Acme\Catalog\Model\ResourceModel\Badge\CollectionFactory $collectionFactory
) {
}

$product = $this->productFactory->create();              // preference resolves the interface
$collection = $this->collectionFactory->create();
```

- Factories are generated automatically (`generated/code/` in developer mode, `setup:di:compile` in production); write one by hand only when `create()` needs custom logic — then name it the same so the generator skips it.
- An interface factory (`ProductInterfaceFactory`) creates whatever the `preference` for that interface resolves to.
- `create($data)` passes `$data` as constructor arguments by name — not as model data; call `setData()` afterwards.

## Registering a console command

Commands are collected by `Magento\Framework\Console\CommandListInterface` through its `commands` array argument (core modules register on the interface; the docs' `Magento\Framework\Console\CommandList` class works too because DI arguments are inherited by implementations):

```xml
<type name="Magento\Framework\Console\CommandListInterface">
    <arguments>
        <argument name="commands" xsi:type="array">
            <item name="acme_catalog_badge_rebuild" xsi:type="object">Acme\Catalog\Console\Command\BadgeRebuild</item>
        </argument>
    </arguments>
</type>
```

This must be in the **global** `etc/di.xml`. If the command's constructor pulls in a heavy dependency, inject it as a proxy so `bin/magento list` stays fast. Command class: `cron-and-cli.md`.

## Applying changes and compiling

| Change | Developer / default mode | Production mode |
|---|---|---|
| Any `di.xml` edit | `bin/magento cache:clean config compiled_config` (the object manager config is in `config`, plugin lists in `compiled_config`) | `bin/magento setup:di:compile` then `cache:clean` |
| New factory/proxy/interceptor reference | Nothing — generated on the fly under `generated/code/` | `setup:di:compile` (production does not generate at runtime) |
| New module | `bin/magento setup:upgrade` | `setup:upgrade` then `setup:di:compile` |

- `setup:di:compile` is *only* required in production mode; running it in developer mode is pointless and leaves `generated/metadata` behind, after which di.xml edits are ignored until you delete `generated/metadata` (the object manager switches to the compiled DI whenever `generated/metadata/global.php` exists, regardless of `MAGE_MODE` — see `magekwik-magento:ops`). `deploy:mode:set production` runs it for you.
- After switching production → developer, delete `generated/code` and `generated/metadata` so stale compiled classes do not shadow edits.
- Compile errors like *"Missing required argument $x of Acme\..."* or *"Type Error occurred when creating object"* mean a constructor parameter has no preference, no `di.xml` argument and no default — fix the DI, do not add `ObjectManager` calls (A1).

## Sources

- https://developer.adobe.com/commerce/php/development/components/dependency-injection — Dependency injection (constructor injection, injectable vs newable objects, factories, proxies, compilation)
- https://developer.adobe.com/commerce/php/development/build/dependency-injection-file — The `di.xml` file (areas and load order, `type`, `virtualType`, argument `xsi:type`s, `shared`, `preference`, merge rules)
- https://developer.adobe.com/commerce/php/development/components/plugins — Plugins (`<plugin>` attributes `name`/`type`/`sortOrder`/`disabled`, limitations including virtual types)
- https://developer.adobe.com/commerce/php/development/components/proxies — Proxies (`\Class\Proxy` naming, `di.xml` injection, generated code)
- https://developer.adobe.com/commerce/php/development/components/factories — Factories (`\ClassFactory`, `create(array $data = [])`, interface resolution through preferences)
- https://developer.adobe.com/commerce/php/development/cli-commands/custom — Create a custom command (`commands` array registration, `cache:clean` and `setup:di:compile`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/setup/application-modes — Application modes (developer mode compiles automatically; production mode is pre-compiled)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/set-mode — Set the operation mode (`deploy:mode:set production` compiles; clear `generated/` when switching back)
