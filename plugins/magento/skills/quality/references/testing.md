# Testing Magento 2 code: unit, integration, API functional, MFTF

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (A1 DI, A2 plugins, A3 observers, A10 config, Q2 strict types, Q3 what gets which test, S2 request-method interfaces).

PHPUnit major per release (root `composer.json` `require-dev` of `magento/magento2`): `~9.5` on 2.4.4–2.4.7, `^10.5` on 2.4.8, `^12.0` on 2.4.9 (12.5 resolves; `dev/tests/*/phpunit.xml.dist` reference the 12.5 schema). What that changes for a test you write: data-provider methods must be `public static` (deprecated otherwise in 10, removed in 11); doc-comment metadata such as `@dataProvider`, `@covers`, `@depends` is deprecated in 11 and **removed in 12** — on 2.4.8+ use `#[DataProvider('cases')]` from `PHPUnit\Framework\Attributes`, on 2.4.4–2.4.7 use the annotation (PHPUnit 9 ignores attributes, so a file carrying both runs everywhere); `getMockForAbstractClass()`, `getMockForTrait()`, `createTestProxy()`, `MockBuilder::addMethods()` and expectations on `createStub()` doubles are gone in 12; `assertContainsOnly()` is deprecated in 12. `setUp(): void`, `createMock()`, `createStub()`, `getMockBuilder()->disableOriginalConstructor()->onlyMethods([...])`, `willReturnMap()`, `willReturnCallback()` are the same on all of them. Magento's own `@magento*` doc-comment annotations are parsed by Magento's test framework, not PHPUnit, and keep working on 2.4.9.

## Unit tests

**Where**: `app/code/Acme/Catalog/Test/Unit/<same path as the class>/<Class>Test.php`, namespace `Acme\Catalog\Test\Unit\…`. The suite `Magento_Unit_Tests_App_Code` in `dev/tests/unit/phpunit.xml.dist` globs `app/code/*/*/Test/Unit` and `vendor/magento/module-*/Test/Unit`; Composer's `exclude-from-classmap` keeps `**/Test/**` out of the optimised autoloader, PSR-0 still resolves it.

**Bootstrap**: `dev/tests/unit/phpunit.xml.dist` (`bootstrap="./framework/bootstrap.php"`, `memory_limit -1`, timezone `America/Los_Angeles`, the Allure extension from `allure-framework/allure-phpunit` in core `require-dev`). `framework/bootstrap.php` loads `app/autoload.php`, sets `TESTS_TEMP_DIR` to `dev/tests/unit/tmp`, installs an error handler that turns notices into failures, and includes `framework/autoload.php`, which registers a `GeneratedClassesAutoloader` with `FactoryGenerator`, `ProxyGenerator`, `ExtensionAttributesGenerator` and `ExtensionAttributesInterfaceGenerator` — `XxxFactory`, `Xxx\Proxy` and extension-attribute classes are generated into `dev/tests/unit/tmp/generated/code` the first time a test touches them. No database, no `env.php`, no `setup:di:compile`.

```bash
vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist                                          # everything, including core — slow
vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist app/code/Acme/Catalog/Test/Unit           # one module
vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist app/code/Acme/Catalog/Test/Unit/Model/BrandListTest.php
vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist --filter 'BrandListTest::testGetNames' app/code/Acme
vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist --testsuite Magento_Unit_Tests_App_Code
php -f vendor/bin/phpunit -- -c dev/tests/unit/phpunit.xml.dist app/code/Acme                   # when vendor/bin is not executable (shared folders)
```

Copy `phpunit.xml.dist` to `phpunit.xml` (gitignored by convention) for local changes such as dropping the Allure `<extensions>` block or adding a coverage `<source>`; point `-c` at the copy. `bin/magento dev:tests:run unit` runs the *whole* unit suite (`dev/tests/unit`, plus the static and integration frameworks' own unit tests) — not a per-module tool.

**The `ObjectManager` helper** (`Magento\Framework\TestFramework\Unit\Helper\ObjectManager`, constructed with the test case):

| Call | Does |
|---|---|
| `getObject(Foo::class, ['bar' => $mock, 'limit' => 5])` | reflects `Foo::__construct`, passes the named arguments you gave, and for every other parameter creates a `createMock()` double of its class/interface (arrays become `[]`, scalar defaults are kept; `AbstractResource` and `TranslateInterface` get special mocks); keys that are not constructor parameters are written into same-named properties |
| `getConstructArguments(Foo::class, [...])` | the same argument array without instantiating — use it to grab the auto-generated mocks (`$args['logger']`) and set expectations on them |
| `getCollectionMock(Collection::class, [$item1, $item2])` | a collection double whose iterator yields the items |
| `setBackwardCompatibleProperty($object, 'name', $value)` | reflection write to a private/protected property — only for properties with no constructor path |
| `prepareObjectManager([[Foo::class, $fooMock]])` | installs a mocked `ObjectManagerInterface` for code that still calls `ObjectManager::getInstance()` (A1 — test the legacy code, then fix it) |

Mock interfaces, not implementations: `ScopeConfigInterface`, `LoggerInterface`, `ProductRepositoryInterface`, `SearchCriteriaBuilder` (a class, but final-free and cheap), `RequestInterface`, `StoreManagerInterface`. Never mock the class under test, never mock `DataObject` subclasses when a real one built with `new Product([...])`-style data is impossible — prefer the repository interface at the boundary (A4).

`ScopeConfigInterface` with an explicit scope (A10):

```php
$scopeConfig = $this->createMock(ScopeConfigInterface::class);
$scopeConfig->method('getValue')
    ->with(BrandList::XML_PATH_LIMIT, ScopeInterface::SCOPE_STORE, null)   // Magento\Store\Model\ScopeInterface
    ->willReturn('3');
$scopeConfig->method('isSetFlag')->willReturnMap([
    [BrandList::XML_PATH_ENABLED, ScopeInterface::SCOPE_STORE, null, true],
]);
$this->brandList = (new ObjectManager($this))->getObject(BrandList::class, ['scopeConfig' => $scopeConfig]);
```

A plugin is a plain class (A2): construct it, call the interception method directly, assert on what it returns or what it did to the argument — no `di.xml`, no interceptor:

```php
public function testAfterGetNameAppendsSuffix(): void
{
    $subject = $this->createMock(ProductInterface::class);
    $plugin = (new ObjectManager($this))->getObject(NameSuffix::class);
    self::assertSame('Chair (Acme)', $plugin->afterGetName($subject, 'Chair'));
}
```

`before*` plugins return the argument array (or `null`); assert `self::assertSame([$product, false], $plugin->beforeSave($repo, $product, false))`. For an `around*` plugin pass a closure as `$proceed` and assert it was (or was not) called.

An observer (A3) takes a `Magento\Framework\Event\Observer`, which is a `DataObject`; build a real one instead of mocking `getEvent()` chains:

```php
public function testExecuteLogsOrderIncrementId(): void
{
    $order = $this->createMock(OrderInterface::class);
    $order->method('getIncrementId')->willReturn('000000123');
    $logger = $this->createMock(LoggerInterface::class);
    $logger->expects(self::once())->method('info')->with('Order placed: 000000123');

    $observer = (new ObjectManager($this))->getObject(OrderPlacedLogger::class, ['logger' => $logger]);
    $observer->execute(new Observer(['event' => new Event(['order' => $order])]));   // Magento\Framework\Event
}
```

Data providers, portable across PHPUnit 9/10/12:

```php
use PHPUnit\Framework\Attributes\DataProvider;

/**
 * @dataProvider slugCases
 */
#[DataProvider('slugCases')]
public function testSlug(string $name, string $expected): void
{
    self::assertSame($expected, $this->brandList->slug($name));
}

public static function slugCases(): array
{
    return ['plain' => ['Acme', 'acme'], 'spaces' => ['Big Brand', 'big-brand']];
}
```

The annotation is what PHPUnit 9 (2.4.4–2.4.7) reads and PHPUnit 12 ignores; the attribute is what 10+ (2.4.8–2.4.9) reads and 9 ignores (the `use` of a class that does not exist under PHPUnit 9 is harmless — attributes are only instantiated on reflection). Drop the annotation on a 2.4.8+-only project. Do not unit-test what needs the framework running — resource models, collections, `di.xml` wiring, layout, ACL, cron scheduling — that is an integration test (Q3).

## Integration tests

**Where**: `app/code/Acme/Catalog/Test/Integration/…Test.php` (the `Magento Integration Tests Real Suite` in `dev/tests/integration/phpunit.xml.dist` includes `app/code/*/*/Test/Integration`), fixtures in `Test/Integration/_files/`. Tests extend `PHPUnit\Framework\TestCase` (or `Magento\TestFramework\TestCase\AbstractController` / `AbstractBackendController` for HTTP-level controller tests) and get everything through `Magento\TestFramework\Helper\Bootstrap::getObjectManager()` — here the object manager is the recommended tool, because the point is the real wiring: `$objectManager->get(ProductRepositoryInterface::class)` returns the interceptor with every `di.xml` plugin applied, `create()` gives a fresh instance.

**Setup** (once per machine/CI job):

1. Create a **dedicated** MySQL/MariaDB database and user (`magento_integration_tests`) — the framework installs Magento into it and, with `TESTS_CLEANUP` `enabled` (the default), reinstalls on every run: "Any data … will be lost" if you point it at the real one. The search engine from the same file (`opensearch`/`elasticsearch7` host and port) must be reachable too; the default `.dist` says OpenSearch on `localhost:9200`.
2. `cp dev/tests/integration/etc/install-config-mysql.php.dist dev/tests/integration/etc/install-config-mysql.php` and edit `db-host`, `db-user`, `db-password`, `db-name`, search engine, optionally `amqp-*`. Relative paths in the `<php>` constants resolve against `dev/tests/integration`, and the bootstrap falls back to the `.dist` when the copy is missing.
3. Optional: `config-global.php` (from `.dist`) for config values every test needs; `phpunit.xml` copy for `TESTS_CLEANUP` (`disabled` skips the reinstall between runs — faster locally, then clear `dev/tests/integration/tmp` when things go stale), `TESTS_MAGENTO_MODE` (`developer`), `TESTS_PARALLEL_RUN`.

```bash
vendor/bin/phpunit -c dev/tests/integration/phpunit.xml.dist app/code/Acme/Catalog/Test/Integration
cd dev/tests/integration && ../../../vendor/bin/phpunit ../../../app/code/Acme/Catalog/Test/Integration/Model/BrandListTest.php   # Adobe's documented form
```

The first run installs Magento (minutes); later runs reuse it while `TESTS_CLEANUP` is `disabled` or nothing in `app/etc`/`dev/tests/integration/etc` changed. Run one directory or one class at a time; the whole suite is hours.

**Annotations and attributes.** Every marker exists in two spellings: the doc-comment annotation (all releases, still used by 1080 core test files in 2.4.9) and, from 2.4.5, a PHP attribute in `Magento\TestFramework\Fixture` (what new core tests use — the framework's own `phpstan.neon` even ignores the "not repeatable" false positives PHPStan raises for them). Class-level applies to every test in the class; method-level overrides it.

| Annotation | Attribute (2.4.5+) | Effect |
|---|---|---|
| `@magentoDbIsolation enabled` | `#[DbIsolation(true)]` | wrap the test in a transaction that is rolled back; **off by default unless a data fixture is declared** |
| `@magentoAppIsolation enabled` | `#[AppIsolation(true)]` | re-initialise the application (fresh object manager, caches) for the test |
| `@magentoAppArea frontend` | `#[AppArea('frontend')]` | `frontend`, `adminhtml`, `webapi_rest`, `graphql`, `crontab`, `global` — required for anything that loads layout, area `di.xml` or `events.xml` |
| `@magentoDataFixture Acme_Catalog::Test/Integration/_files/brands.php` | `#[DataFixture('Acme_Catalog::Test/Integration/_files/brands.php')]` | run the file (module-relative `Vendor_Module::path`, or `Magento/Catalog/_files/product_simple.php` relative to `dev/tests/integration/testsuite`) before the test, `brands_rollback.php` from the same directory after; a method reference `ClassName::method` (with `ClassName::methodRollback`) also works |
| `@magentoDataFixtureBeforeTransaction …` | `#[DataFixtureBeforeTransaction(…)]` | same, outside the DB-isolation transaction (for data that needs commits: indexers, cron) |
| `@magentoConfigFixture current_store catalog/frontend/list_mode grid` (`<store_code>_store …`, `<website_code>_website …`, or a bare path / `default/…` for the default scope) | `#[Config('catalog/frontend/list_mode', 'grid', ScopeInterface::SCOPE_STORE, 'default')]` | set a config value for the test and restore it after |
| `@magentoAdminConfigFixture admin/security/use_form_key 0` | `#[Config(…)]` | admin-scope config |
| `@magentoCache full_page enabled` / `all disabled` | `#[Cache('full_page', true)]` | toggle cache types |
| `@magentoIndexerDimensionMode catalog_product_price website` | `#[IndexerDimensionMode(…)]` | price indexer dimension mode |
| `@magentoComponentsDir Acme/Catalog/Test/Integration/_files/modules` | `#[ComponentsDir(…)]` | register fixture modules/themes from a directory |

Parameterised fixtures (2.4.5+) replace hand-written `_files` for common entities: `#[DataFixture(ProductFixture::class, ['sku' => 'acme-chair', 'price' => 10], 'product')]` with `use Magento\Catalog\Test\Fixture\Product as ProductFixture;` creates the product and stores it under the alias; `DataFixtureStorageManager::getStorage()->get('product')` returns it (a `DataObject`, `->getId()`, `->getSku()`); `count: 3` builds several; `scope:` runs the fixture in a store view. Core ships fixtures under `vendor/magento/module-*/Test/Fixture/` (`Catalog`: `Category`, `Product`, `Attribute`; `Customer`: `Customer`, `CustomerGroup`; `Store`: `Store`, `Website`, `Group`; `Quote`: `GuestCart`, `CustomerCart`, `AddProductToCart`; `Sales`: `PlaceOrderWithCustomerOrGuest`, `Invoice`, `Shipment` …) — reuse them before writing a file fixture.

A resource-level test:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Test\Integration\Model;

use Acme\Catalog\Model\BrandList;
use Magento\TestFramework\Helper\Bootstrap;
use PHPUnit\Framework\TestCase;

class BrandListTest extends TestCase
{
    /**
     * @magentoDbIsolation enabled
     * @magentoAppArea frontend
     * @magentoConfigFixture current_store acme_catalog/brands/limit 2
     * @magentoDataFixture Acme_Catalog::Test/Integration/_files/brands.php
     */
    public function testGetNamesHonoursLimit(): void
    {
        $brandList = Bootstrap::getObjectManager()->create(BrandList::class);
        self::assertCount(2, $brandList->getNames());
    }
}
```

`_files/brands.php` is a plain script run inside the framework (object manager via `Bootstrap::getObjectManager()`, repositories to create data); `brands_rollback.php` deletes what it created — with DB isolation the transaction rollback also undoes it, but the rollback file is still required for `@magentoDbIsolation disabled` runs and for `TESTS_CLEANUP` `disabled`. Fixture scripts run with the `Magento\TestFramework\Workaround\Override\Fixture\Resolver` so one fixture can `requireDataFixture()` another.

Controllers: extend `AbstractController`, `$this->dispatch('acme/brand/index')`, then `$this->getResponse()->getBody()`, `assertRedirect()`, `assertSessionMessages()`; set `$this->getRequest()->setMethod('POST')->setPostValue([...])` for `HttpPostActionInterface` actions (S2). Admin: extend `AbstractBackendController`, set `protected $resource = 'Acme_Catalog::brands';` and `protected $uri = 'backend/acme/brand/index';` — the base class adds `testAclHasAccess`/`testAclNoAccess` for you (S1).

Plugins and preferences: an integration test is the only place a `di.xml` mistake shows — `Bootstrap::getObjectManager()->get(ProductRepositoryInterface::class)` is the interceptor, so calling `->get('sku')` exercises every plugin in `sortOrder`; `@magentoAppArea adminhtml` when the plugin is declared in `etc/adminhtml/di.xml`.

## API functional tests

`dev/tests/api-functional` runs REST (`phpunit_rest.xml.dist`), SOAP and GraphQL (`phpunit_graphql.xml.dist`) tests over HTTP against a running instance: `TESTS_BASE_URL`, `TESTS_WEBSERVICE_USER`/`TESTS_WEBSERVICE_APIKEY` (an admin), `TESTS_WEB_API_ADAPTER` (`rest`/`soap`), plus its own `config/install-config-mysql.php` — it installs into a separate test database exactly like the integration suite. The REST real suite includes `app/code/*/*/Test/Api`; tests extend `Magento\TestFramework\TestCase\WebapiAbstract` and call `$this->_webApiCall($serviceInfo, $requestData)`; GraphQL tests extend `GraphQlAbstract` (`$this->graphQlQuery($query)`). Use them for a `webapi.xml` route's ACL, input validation and response shape (`magento:api`); everything below the route is an integration test.

## MFTF

The Functional Testing Framework (`magento/magento2-functional-testing-framework`: 3.x on 2.4.4–2.4.5, 4.x on 2.4.6–2.4.7, 5.x on 2.4.8, 6.x on 2.4.9) generates Codeception/WebDriver tests from XML in `Test/Mftf/` (`Test/`, `ActionGroup/`, `Section/`, `Page/`, `Data/`, `Metadata/`, `Suite/`), drives a real browser through Selenium + ChromeDriver (Java required), and reports to Allure. It needs a running storefront and admin with `admin/security/admin_account_sharing 1`, `admin/security/use_form_key 0`, WYSIWYG disabled and 2FA disabled; then:

```bash
vendor/bin/mftf build:project                  # writes dev/tests/acceptance/.env, codeception.yml and tests/functional.suite.yml
cp dev/tests/acceptance/.htaccess.sample dev/tests/acceptance/.htaccess
# edit dev/tests/acceptance/.env: MAGENTO_BASE_URL, MAGENTO_BACKEND_NAME, MAGENTO_ADMIN_USERNAME (password via the credentials file)
vendor/bin/mftf generate:tests                 # XML → PHP under dev/tests/acceptance/tests/functional/Magento/_generated
vendor/bin/mftf run:test AdminLoginSuccessfulTest --remove
vendor/bin/mftf run:group acme                 # tests annotated <group value="acme"/>
```

Worth it for a flow that exists only in a browser (an admin grid mass action, a checkout step, a customer-account page with JS); not for anything an integration or API test covers — MFTF runs take minutes per test and break on markup changes. Reuse core action groups (`AdminLoginActionGroup`, `StorefrontOpenProductPageActionGroup`) and core `Section`/`Page` definitions from `vendor/magento/module-*/Test/Mftf/` instead of redefining selectors.

## Sources

- https://developer.adobe.com/commerce/testing/guide/unit/ — unit testing overview (CLI vs PhpStorm)
- https://developer.adobe.com/commerce/testing/guide/unit/command-line — `./vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist [dir]`, `phpunit.xml` copy, `php -f vendor/bin/phpunit --`, `memory_limit`, PHPUnit 10 on 2.4.8 and 9 on earlier 2.4.x, running from `dev/tests/unit` when the Allure extension fails
- https://developer.adobe.com/commerce/testing/guide/unit/writing-testable-code — constructor injection, no `new`/`ObjectManager` in production code, "the object manager is recommended for integration tests", mock interfaces
- https://developer.adobe.com/commerce/testing/guide/integration/ — dedicated database ("Any data … will be lost"), `install-config-mysql.php` and `config-global.php` from `.dist`, `phpunit.xml` copy, `TESTS_CLEANUP`, `cd dev/tests/integration && ../../../vendor/bin/phpunit`, `app/code/*/*/Test/Integration`
- https://developer.adobe.com/commerce/testing/guide/integration/annotations/ — the annotation list and syntax; "Database isolation is disabled by default unless `@magentoDataFixture` is used"
- https://developer.adobe.com/commerce/testing/guide/integration/annotations/magento-data-fixture — path formats (`dev/tests/integration/<suite>`-relative, `VendorName_ModuleName::Test/Integration/_files/…`), `_rollback` naming, class vs method scope
- https://developer.adobe.com/commerce/testing/guide/integration/attributes/ — the nine attributes
- https://developer.adobe.com/commerce/testing/guide/integration/attributes/data-fixture — `DataFixture(type, data, as, scope, count)`, `DataFixtureStorageManager::getStorage()->get('product')`, class vs method level
- https://developer.adobe.com/commerce/testing/functional-testing-framework/ — what MFTF is, `Test/Mftf` locations, Allure output
- https://developer.adobe.com/commerce/testing/functional-testing-framework/getting-started — prerequisites (Java, Selenium, ChromeDriver), `build:project`, `.env` keys, config:set commands, `generate:tests`, `run:test … --remove`, `allure serve`
- https://phpunit.de/announcements/phpunit-12.html — PHP 8.3+, annotations removed, abstract-class/trait mocking removed, no expectations on stubs
- Verified in a 2.4.9 install: `dev/tests/unit/phpunit.xml.dist` and `framework/{bootstrap,autoload}.php`, `vendor/magento/framework/TestFramework/Unit/Helper/ObjectManager.php`, `vendor/magento/framework/Event.php` and `Event/Observer.php`, `dev/tests/integration/{phpunit.xml.dist,etc/install-config-mysql.php.dist}`, `framework/Magento/TestFramework/{Bootstrap/Settings.php,Fixture/*.php,TestCase/AbstractController.php,TestCase/AbstractBackendController.php,Fixture/DataFixtureFactory.php}`, `vendor/magento/module-catalog/Test/Fixture/`, `dev/tests/api-functional/{phpunit_rest.xml.dist,framework/Magento/TestFramework/TestCase/WebapiAbstract.php}`, `vendor/magento/module-developer/Console/Command/DevTestsRunCommand.php`, PHPUnit ChangeLogs 10.0/11.0/12.0 (data-provider and metadata changes); `magento/magento2` at tags 2.4.4–2.4.9 for PHPUnit/MFTF constraints and the first release with `Fixture/DataFixture.php` (2.4.5); `grep -rl '@magentoDataFixture' dev/tests/integration/testsuite` (1080 files) vs `#[DataFixture` (3 files)
