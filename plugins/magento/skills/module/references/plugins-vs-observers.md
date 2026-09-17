# Plugins vs observers

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (A1, A2, A3 apply throughout).

**Plugin** (interceptor): wraps one public method of one class or interface; can read/replace arguments, read/replace the result, or skip the call. **Observer**: runs when a named event is dispatched; receives the event payload; its return value is ignored. Choose by asking whether you must change the method's input/output (plugin) or only react to the fact that something happened (observer).

## Plugins

### The three method types

For a subject method `Subject::doThing(string $sku, int $qty): Result`, a plugin class declares any of:

```php
public function beforeDoThing(Subject $subject, string $sku, int $qty): ?array
{
    // return null to leave arguments untouched, or the full new argument list
    return [strtoupper($sku), $qty];
}

public function aroundDoThing(Subject $subject, callable $proceed, string $sku, int $qty): Result
{
    // must call $proceed(...) (with the same or modified arguments) unless deliberately skipping the original
    return $proceed($sku, $qty);
}

public function afterDoThing(Subject $subject, Result $result, string $sku, int $qty): Result
{
    // receives the return value; must return it (or a replacement)
    return $result;
}
```

- Name = `before`/`around`/`after` + the method name with its first letter upper-cased (`save` → `beforeSave`).
- `$subject` is the intercepted object; type-hint the class or interface named in `di.xml`.
- `before`: returns `null` (no change) or an array of *all* arguments in order. Return a partial array and the method is called with only those arguments.
- `around`: `$proceed` is the next plugin or the original method; forgetting to call it silently disables every later plugin and the original (A2). Use only when the original must be skipped (a cache, a feature flag that short-circuits). It also makes stack traces deeper and slower on hot paths (P4).
- `after`: `$result` is `null` when the method returns `void`; the original arguments follow it, so an `after` plugin can vary by input without an `around`.
- A plugin class needs no interface and no base class. It is built by the object manager: constructor-inject services only (A1, A9); no `ObjectManager`, no runtime values. Plugins are stateless and do not mutate `$subject` (technical guidelines 4.4, 4.5); do not plugin your own module's classes — call the code directly (4.2).

### Declaring the plugin

`etc/di.xml` (or an area file — see `di-xml.md`):

```xml
<type name="Magento\Catalog\Api\ProductRepositoryInterface">
    <plugin name="acme_catalog_normalize_product_name" type="Acme\Catalog\Plugin\NormalizeProductName" sortOrder="10"/>
</type>
```

`name` (required, unique per subject), `type` (plugin class), `sortOrder` (int, optional), `disabled` (`true` to switch off, optional).

### Interface or class?

- Plugin the **interface** (`ProductRepositoryInterface`) when the behaviour belongs to the contract: it fires for every implementation reached through the interface (the preference'd class and anything else resolved via the interface), in every entry point.
- Plugin the **class** when the method is not on an interface, or you need a method only the class has.
- Plugins on a parent class are inherited by subclasses and by implementations of a plugged interface.

### Execution order with several plugins

Plugins on the same method are sorted by `sortOrder` ascending; a plugin with no `sortOrder` sorts first. The interceptor then runs:

1. the `before`s of every plugin up to and including the first plugin that has an `around`, in order;
2. that `around`; its `$proceed` runs the remaining plugins as a nested chain of the same shape (their `before`s, the next `around`, the original, their `after`s);
3. the `after`s of the plugins from step 1, in order.

Concretely, with `PluginA` (10), `PluginB` (20), `PluginC` (30) all defining `before`+`after`, and only `PluginB` defining `around`, a call to `dispatch()` runs:

`A::before → B::before → B::around (first half) → C::before → original → C::after → B::around (second half) → A::after → B::after`

Consequences: an `after` on a plugin sorted *before* an `around` still sees that `around`'s result; two plugins with equal `sortOrder` have undefined relative order — set explicit values when it matters.

### Limitations (A2)

Plugins cannot be applied to: `final` classes or methods; non-public methods; `static` methods; `__construct`/`__destruct`; virtual types; classes implementing `Magento\Framework\ObjectManager\NoninterceptableInterface`; objects created before the interception layer is bootstrapped. For those, you need a `preference` (last resort) or a different extension point.

### Worked example — `before` plugin

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

The subject is `save(ProductInterface $product, $saveOptions = false)`; the plugin's parameters mirror it after `$subject`, and `$saveOptions` stays untyped because the interface leaves it untyped — a plugin must never narrow the subject's parameter types. A `before` plugin returns the (possibly modified) argument list; return `null` to leave arguments untouched.

## Observers

### `events.xml`

`etc/events.xml` (global), `etc/frontend/events.xml`, `etc/adminhtml/events.xml`, `etc/webapi_rest/events.xml`, `etc/graphql/events.xml`, `etc/crontab/events.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Event/etc/events.xsd">
    <event name="sales_order_place_after">
        <observer name="acme_catalog_log_order_placed" instance="Acme\Catalog\Observer\OrderPlacedLogger"/>
    </event>
</config>
```

`<observer>` attributes: `name` (required; unique per event, used by other modules to disable or override), `instance` (class implementing `ObserverInterface`), `disabled` (`true` to switch off), `shared` (`false` for a new instance per dispatch — default `true`, a singleton).

- Scope the file to the area where the event matters. An observer in `etc/events.xml` runs for storefront, admin, REST, GraphQL, CLI and cron dispatches of that event; `etc/frontend/events.xml` runs only for storefront requests.
- To disable another module's observer, redeclare its `name` under the same event with `disabled="true"` — no class needed.
- Declare `shared="false"` when the observer keeps state in properties between calls; singletons persist for the whole request (and across requests under some runtimes).

### Observer class

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Observer;

use Magento\Framework\Event\Observer;
use Magento\Framework\Event\ObserverInterface;
use Magento\Sales\Api\Data\OrderInterface;
use Psr\Log\LoggerInterface;

class OrderPlacedLogger implements ObserverInterface
{
    public function __construct(
        private readonly LoggerInterface $logger
    ) {
    }

    public function execute(Observer $observer): void
    {
        /** @var OrderInterface $order */
        $order = $observer->getEvent()->getData('order');
        $this->logger->info(sprintf('Order %s placed for store %d', $order->getIncrementId(), (int) $order->getStoreId()));
    }
}
```

- `execute(Observer $observer)` is the only method; declare it `: void` — the dispatcher discards return values (A3).
- Payload: `$observer->getEvent()->getData('key')`. The dispatcher also copies the payload onto the observer wrapper, so `$observer->getData('order')` and the magic `$observer->getEvent()->getOrder()` work, but `getEvent()->getData('key')` is the explicit form.
- Read the dispatching code to learn the payload keys — `grep -rn "dispatch('event_name'" vendor/magento/` — and type-hint with the `Api\Data` interface where one exists.
- Keep observers small and side-effect-only: log, enqueue, update a flag, call a service. Business rules, validation that must block the flow, or anything that must return a value belong in a plugin or service (A3). Do not dispatch from an observer an event that can re-trigger it.
- Never rely on the order in which observers of the same event run; it is not defined by `events.xml`.
- The module that dispatches the event goes in `module.xml` `<sequence>` (A8): `Magento_Sales` for `sales_order_*`.

### Dispatching your own event

Inject `Magento\Framework\Event\ManagerInterface` and call `dispatch(string $eventName, array $data = [])`:

```php
public function __construct(
    private readonly \Magento\Framework\Event\ManagerInterface $eventManager
) {
}

public function markReviewed(BadgeInterface $badge): void
{
    // ... do the work ...
    $this->eventManager->dispatch('acme_badge_reviewed', ['badge' => $badge]);
}
```

- Name events `<vendor>_<entity>_<verb>` in lower snake case; suffix with `_before`/`_after` around an operation. Names are global — prefix with your vendor to avoid collisions.
- Pass objects, not IDs, so observers need no extra loads. Adobe's technical guidelines (14.1, 14.3) say observers must not modify the values passed with an event nor the state of observed objects — if the dispatcher needs an answer back, that is a plugin or an explicit extension point, not an event (A3). Never dispatch events from a constructor (2.3.2).
- Models extending `AbstractModel` already dispatch `<_eventPrefix>_load_after`, `_save_before`, `_save_after`, `_save_commit_after`, `_delete_before`, `_delete_after` with the entity under `<_eventObject>`; set `$_eventPrefix`/`$_eventObject` on your model to get them for free.

### Common core events

| Event | Dispatched from | Payload |
|---|---|---|
| `sales_order_place_before` / `sales_order_place_after` | `Magento\Sales\Model\Order::place()` — every checkout path (storefront, admin, REST, GraphQL) | `order` |
| `sales_order_save_before` / `sales_order_save_after` | `AbstractModel` save on `Order` (`_eventPrefix = 'sales_order'`) — fires on *every* save, not only placement | `order`, `data_object` |
| `catalog_product_save_before` / `catalog_product_save_after` | `AbstractModel` save on `Product` (`_eventPrefix = 'catalog_product'`) | `product`, `data_object` |
| `customer_register_success` | `Magento\Customer\Controller\Account\CreatePost` (storefront registration only; not REST) | `account_controller`, `customer` |
| `checkout_cart_product_add_after` | `Magento\Checkout\Model\Cart::addProduct()` | `quote_item`, `product` |
| `controller_action_predispatch` (+ `_<routeName>`, `_<full_action_name>` variants) | `Magento\Framework\App\FrontController::dispatchPreDispatchEvents()` before every action, `AbstractAction` subclass or plain `ActionInterface` alike (2.4.4–2.4.9) | `controller_action`, `request` |

`_save_after` events run inside the transaction; `_save_commit_after` runs after commit — use the latter for anything that reads the row back through another connection or enqueues work.

## Deciding

| Situation | Choice |
|---|---|
| Validate or normalise arguments before a core method runs | `before` plugin |
| Enrich, filter or replace a method's result | `after` plugin |
| Skip the original entirely (cache hit, feature disabled) | `around` plugin that returns without `$proceed` on that branch |
| Log, notify, sync, enqueue when something happened | Observer on the matching `_after` / `_success` event |
| The method is `private`/`final`/`static`, or there is no event | Refactor target via `preference` (A2, last resort) or an upstream extension point |
| A third-party module's plugin/observer misbehaves | Redeclare its `name` with `disabled="true"`; do not copy its class |

After adding or editing `di.xml`/`events.xml` in developer mode: `bin/magento cache:clean config compiled_config` (plugin lists are cached in `compiled_config`). Production: `setup:di:compile` for plugins (interceptors are generated), `cache:clean` for both.

## Sources

- https://developer.adobe.com/commerce/php/development/components/plugins — Plugins (limitations, `di.xml` declaration, `before`/`around`/`after` signatures, `sortOrder` and the multi-plugin execution example, `$proceed` warning)
- https://developer.adobe.com/commerce/php/development/components/events-and-observers/ — Events and observers (`ManagerInterface::dispatch`, `ObserverInterface::execute`, `events.xml` per area, `shared`/`disabled`, disabling another module's observer)
- https://developer.adobe.com/commerce/php/best-practices/extensions/observers — Observers best practices (efficient, no business logic, appropriate scope, no cyclical events, no reliance on invocation order)
- https://developer.adobe.com/commerce/php/development/build/dependency-injection-file — The `di.xml` file (`shared` object lifestyle referenced by `events.xml` `shared`)
- https://developer.adobe.com/commerce/php/coding-standards/technical-guidelines — Technical guidelines (4.1–4.5 plugins stateless, no `$subject` mutation, `around` only to substitute; 14.1–14.3 observers must not modify event values; 2.3.2 no events in constructors)
