# Service contracts: data interfaces, repositories, models and extension attributes

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (A4 contracts, A5 no raw SQL, A9 factories, P1/P2 paging, Q4 `@api`).

## The layers

- `Api/Data/` — data interfaces (`BrandInterface`) and search results interfaces; everyone may depend on them.
- `Api/` — service interfaces (`BrandRepositoryInterface`, `*ManagementInterface`); everyone may depend on them, and this is what `webapi.xml` exposes (`magento:api`).
- `Model/`, `Model/ResourceModel/` — model, resource model, collection, repository implementation; only this module.

Other modules type-hint the interfaces, `di.xml` binds them to your classes (A4). Everything below is the `acme_brand` table from `SKILL.md` (`entity_id`, `name`, `created_at`); `created_at` is filled by its column default and needs no setter.

## `Api/Data/BrandInterface`

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Api\Data;

/**
 * @api
 */
interface BrandInterface
{
    public const ENTITY_ID = 'entity_id';
    public const NAME = 'name';

    public function getEntityId(): ?int;

    public function setEntityId(int $entityId): self;

    public function getName(): ?string;

    public function setName(string $name): self;
}
```

Constants are the column names; getters/setters are camel-cased versions of them (`name` → `getName`). The web API and `DataObjectHelper` convert between the two with a strict camelCase↔snake_case rule, so avoid digits next to underscores in column names (`default_shipping1`, not `default_shipping_1`). Mark the interface `@api` (Q4). Scalar types only; a nested object is another `Api/Data` interface.

`Api/Data/BrandSearchResultsInterface` — one per entity, so `getList()` is typed:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Api\Data;

use Magento\Framework\Api\SearchResultsInterface;

/**
 * @api
 */
interface BrandSearchResultsInterface extends SearchResultsInterface
{
    /**
     * @return \Acme\Catalog\Api\Data\BrandInterface[]
     */
    public function getItems();
}
```

`SearchResultsInterface` already declares `getItems`, `setItems`, `getSearchCriteria`, `setSearchCriteria`, `getTotalCount`, `setTotalCount` without native types; redeclare only what you narrow (`getItems`, and `setItems` with `@param \Acme\Catalog\Api\Data\BrandInterface[] $items` if you want it typed too), with docblocks — the web API reads them.

## `Api/BrandRepositoryInterface`

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Api;

use Acme\Catalog\Api\Data\BrandInterface;
use Acme\Catalog\Api\Data\BrandSearchResultsInterface;
use Magento\Framework\Api\SearchCriteriaInterface;

/**
 * @api
 */
interface BrandRepositoryInterface
{
    public function save(BrandInterface $brand): BrandInterface;

    public function getById(int $entityId): BrandInterface;

    public function getList(SearchCriteriaInterface $searchCriteria): BrandSearchResultsInterface;

    public function delete(BrandInterface $brand): bool;

    public function deleteById(int $entityId): bool;
}
```

Document the exceptions with `@throws` docblocks (`save` → `CouldNotSaveException`, `getById`/`deleteById` → `NoSuchEntityException`, `delete` → `CouldNotDeleteException`); the web API turns them into HTTP errors. `save` creates when the id is empty and updates otherwise and returns the saved entity; `getById` throws rather than returning null; `getList` takes `SearchCriteriaInterface` and returns the search results interface. Operations that are not CRUD (`assignToProduct`, `publish`) go in a separate `Api/BrandManagementInterface`. Repositories are stateless: no memoised results across calls unless keyed by id and invalidated on save/delete.

## Model, resource model, collection

`Model/Brand.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Model;

use Acme\Catalog\Api\Data\BrandInterface;
use Acme\Catalog\Model\ResourceModel\Brand as BrandResource;
use Magento\Framework\Model\AbstractModel;

class Brand extends AbstractModel implements BrandInterface
{
    protected function _construct(): void
    {
        $this->_init(BrandResource::class);
    }

    public function getEntityId(): ?int
    {
        $id = $this->getData(self::ENTITY_ID);
        return $id === null ? null : (int) $id;
    }

    /**
     * @param int $entityId
     */
    public function setEntityId($entityId): self
    {
        return $this->setData(self::ENTITY_ID, (int) $entityId);
    }

    public function getName(): ?string
    {
        return $this->getData(self::NAME);
    }

    public function setName(string $name): self
    {
        return $this->setData(self::NAME, $name);
    }
}
```

`Model/ResourceModel/Brand.php` and `Model/ResourceModel/Brand/Collection.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Model\ResourceModel;

use Magento\Framework\Model\ResourceModel\Db\AbstractDb;

class Brand extends AbstractDb
{
    protected function _construct(): void
    {
        $this->_init('acme_brand', 'entity_id');
    }
}
```

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Model\ResourceModel\Brand;

use Acme\Catalog\Model\Brand as BrandModel;
use Acme\Catalog\Model\ResourceModel\Brand as BrandResource;
use Magento\Framework\Model\ResourceModel\Db\Collection\AbstractCollection;

class Collection extends AbstractCollection
{
    protected function _construct(): void
    {
        $this->_init(BrandModel::class, BrandResource::class);
    }
}
```

- The model holds data (`getData`/`setData`) and nothing else; `AbstractModel::save()`, `load()`, `delete()`, `getResource()`, `getCollection()` are deprecated — persistence goes through the resource model, and callers go through the repository. `AbstractModel` already defines untyped `getEntityId()` and `setEntityId($entityId)`: an override may add a return type but not a parameter type (PHP rejects the narrowing with a fatal error), so the setter keeps `$entityId` untyped and casts.
- The resource model maps table and id field; add `_beforeSave`/`_afterLoad` hooks or extra queries here. Every SQL string that must exist lives in a resource model method using `$this->getConnection()->select()` and bound parameters (A5).
- The collection is for admin grids (UI component data providers) and for the repository's `getList()`; other modules never see it (A4). Values come back from the DB as strings, so the typed getters cast; store dates as `Y-m-d H:i:s` UTC strings.

### Extensible entity

If other modules must be able to attach data to your entity, extend `Magento\Framework\Model\AbstractExtensibleModel` instead, have `BrandInterface` extend `Magento\Framework\Api\ExtensibleDataInterface`, and declare on both `getExtensionAttributes(): ?BrandExtensionInterface` (`return $this->_getExtensionAttributes();`) and `setExtensionAttributes(BrandExtensionInterface $extensionAttributes): self` (`$this->_setExtensionAttributes(...)`). `BrandExtensionInterface`, `BrandExtension` and `BrandExtensionFactory` are generated from every module's `extension_attributes.xml` entries `for="Acme\Catalog\Api\Data\BrandInterface"` and are empty until someone declares an attribute.

## Repository implementation

`Model/BrandRepository.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Model;

use Acme\Catalog\Api\BrandRepositoryInterface;
use Acme\Catalog\Api\Data\BrandInterface;
use Acme\Catalog\Api\Data\BrandInterfaceFactory;
use Acme\Catalog\Api\Data\BrandSearchResultsInterface;
use Acme\Catalog\Api\Data\BrandSearchResultsInterfaceFactory;
use Acme\Catalog\Model\ResourceModel\Brand as BrandResource;
use Acme\Catalog\Model\ResourceModel\Brand\CollectionFactory;
use Magento\Framework\Api\SearchCriteria\CollectionProcessorInterface;
use Magento\Framework\Api\SearchCriteriaInterface;
use Magento\Framework\Exception\CouldNotDeleteException;
use Magento\Framework\Exception\CouldNotSaveException;
use Magento\Framework\Exception\NoSuchEntityException;

class BrandRepository implements BrandRepositoryInterface
{
    public function __construct(
        private readonly BrandResource $resource,
        private readonly BrandInterfaceFactory $brandFactory,
        private readonly CollectionFactory $collectionFactory,
        private readonly BrandSearchResultsInterfaceFactory $searchResultsFactory,
        private readonly CollectionProcessorInterface $collectionProcessor
    ) {
    }

    public function save(BrandInterface $brand): BrandInterface
    {
        try {
            $this->resource->save($brand);
        } catch (\Exception $e) {
            throw new CouldNotSaveException(__('Could not save the brand: %1', $e->getMessage()), $e);
        }
        return $brand;
    }

    public function getById(int $entityId): BrandInterface
    {
        $brand = $this->brandFactory->create();
        $this->resource->load($brand, $entityId);
        if (!$brand->getEntityId()) {
            throw NoSuchEntityException::singleField('entity_id', $entityId);
        }
        return $brand;
    }

    public function getList(SearchCriteriaInterface $searchCriteria): BrandSearchResultsInterface
    {
        $collection = $this->collectionFactory->create();
        $this->collectionProcessor->process($searchCriteria, $collection);

        $searchResults = $this->searchResultsFactory->create();
        $searchResults->setSearchCriteria($searchCriteria);
        $searchResults->setItems($collection->getItems());
        $searchResults->setTotalCount($collection->getSize());
        return $searchResults;
    }

    public function delete(BrandInterface $brand): bool
    {
        try {
            $this->resource->delete($brand);
        } catch (\Exception $e) {
            throw new CouldNotDeleteException(__('Could not delete the brand: %1', $e->getMessage()), $e);
        }
        return true;
    }

    public function deleteById(int $entityId): bool
    {
        return $this->delete($this->getById($entityId));
    }
}
```

- `BrandInterfaceFactory` and `BrandSearchResultsInterfaceFactory` are generated factories (A9); they create whatever `di.xml` prefers for the interface. `resource->save()`/`load()`/`delete()` take the model (`BrandInterface` is the model via the preference) — if you accept other implementations, copy the data across with `DataObjectHelper::populateWithArray` first.
- `CollectionProcessorInterface` is the framework's default chain (filters → sorting → pagination) and maps every `SearchCriteria` field name straight to a column. For a joined or renamed field do what core does: declare a virtual type of `Magento\Framework\Api\SearchCriteria\CollectionProcessor\FilterProcessor` with `fieldMapping`/`customFilters` (and of `SortingProcessor` with `fieldMapping`), wrap them in a virtual type of `Magento\Framework\Api\SearchCriteria\CollectionProcessor` whose `processors` array lists your `filters`, `sorting` and the stock `pagination` processor, and pass that as the repository's `collectionProcessor` argument in `di.xml`. `getTotalCount()` is `getSize()` — a `COUNT(*)` of the filtered query, independent of paging (P2); never fetch the collection to count it.

`Model/BrandSearchResults.php` — `Magento\Framework\Api\SearchResults` implements `SearchResultsInterface` generically, but `getList()` has a native return type, so the preference must point at a subclass that also implements *your* interface (as core does with `Magento\Cms\Model\BlockSearchResults`):

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Model;

use Acme\Catalog\Api\Data\BrandSearchResultsInterface;
use Magento\Framework\Api\SearchResults;

class BrandSearchResults extends SearchResults implements BrandSearchResultsInterface
{
}
```

`etc/di.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:ObjectManager/etc/config.xsd">
    <preference for="Acme\Catalog\Api\Data\BrandInterface" type="Acme\Catalog\Model\Brand"/>
    <preference for="Acme\Catalog\Api\Data\BrandSearchResultsInterface" type="Acme\Catalog\Model\BrandSearchResults"/>
    <preference for="Acme\Catalog\Api\BrandRepositoryInterface" type="Acme\Catalog\Model\BrandRepository"/>
</config>
```

## Calling a repository

Inside any service with `BrandRepositoryInterface $brandRepository`, `Magento\Framework\Api\SearchCriteriaBuilder $searchCriteriaBuilder` and `Magento\Framework\Api\SortOrderBuilder $sortOrderBuilder` constructor-injected:

```php
$sortOrder = $this->sortOrderBuilder
    ->setField(BrandInterface::NAME)
    ->setDirection(SortOrder::SORT_ASC)
    ->create();
$searchCriteria = $this->searchCriteriaBuilder
    ->addFilter(BrandInterface::NAME, $prefix . '%', 'like')
    ->addFilter(BrandInterface::ENTITY_ID, [1, 2, 3], 'nin')
    ->addSortOrder($sortOrder)
    ->setPageSize($pageSize)
    ->setCurrentPage($page)
    ->create();
/** @var BrandInterface[] $brands */
$brands = $this->brandRepository->getList($searchCriteria)->getItems();
```

- `SearchCriteriaBuilder` and `SortOrderBuilder` are injected, not shared instances: `create()` resets the builder, so build one criteria per query and never keep a half-built builder in a property.
- Each `addFilter()` becomes its own filter group, and groups are **AND**ed. For **OR**, pass several `Filter` objects (from `FilterBuilder`) to one `addFilters([...])` call: `(url like %x OR store_id eq 1) AND (url_type eq 1)`. Condition types: `eq`, `neq`, `like`, `nlike`, `in`, `nin`, `gt`, `lt`, `gteq`, `lteq`, `from`, `to`, `finset`, `nfinset`, `null`, `notnull`, `regexp` (`in`/`nin` take an array or a comma-separated string).
- Always `setPageSize()` (P2): with no page size the collection runs without `LIMIT`. Loop pages with `getTotalCount()` / page size when you must process everything. One entity: `getById()` inside `try { } catch (NoSuchEntityException $e) { }`; many: never `getById()` in a loop (P1) — one `getList()` with an `in` filter.
- `ProductRepositoryInterface::getList()` is a database query on the product collection; storefront search, layered navigation and the GraphQL `products` query go through Elasticsearch/OpenSearch instead. Use the repository for integrations and admin tooling, not to render catalogue listings.

## Extension attributes

An extension attribute adds a field to an entity you do not own — `ProductInterface`, `OrderInterface`, `CustomerInterface`, `CartInterface`, anything implementing `ExtensibleDataInterface` — without touching its table (A7). It is two things: a declaration and the code that fills and stores it.

`etc/extension_attributes.xml` — a `brand_id` on products backed by the `acme_product_brand` table from `db-schema.md`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Api/etc/extension_attributes.xsd">
    <extension_attributes for="Magento\Catalog\Api\Data\ProductInterface">
        <attribute code="brand_id" type="int">
            <join reference_table="acme_product_brand" reference_field="product_id" join_on_field="entity_id">
                <field>brand_id</field>
            </join>
        </attribute>
    </extension_attributes>
</config>
```

- `for` is the data interface (it must extend `ExtensibleDataInterface`); `code` is snake_case and becomes `getBrandId()`/`setBrandId()` on the generated `ProductExtensionInterface`; `type` is `int`, `string`, `float`, `boolean`, an `Api/Data` interface, or any of those with `[]`.
- `<join>` — `reference_table` is your table, `reference_field` its column matching the entity's `join_on_field`, and each `<field>` a column to select (`column="db_col"` when the property name differs). It applies **only** to `getList()`, and only when that repository calls `JoinProcessorInterface::process($collection)` — `ProductRepository`, `CustomerRepository` and `OrderRepository` do; your own repository must call it explicitly (inject `Magento\Framework\Api\ExtensionAttribute\JoinProcessorInterface`). A joined scalar takes the first `<field>`; an object type gets each field set through its setter. Array types cannot be joined.
- `<resources><resource ref="Acme_Catalog::brands"/></resources>` restricts the attribute in web API responses to users with that ACL resource.

Everything else needs plugins on the **repository interface** (`magento:module` for plugin mechanics):

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Plugin;

use Acme\Catalog\Model\ResourceModel\ProductBrand as ProductBrandResource;
use Magento\Catalog\Api\Data\ProductInterface;
use Magento\Catalog\Api\ProductRepositoryInterface;

class ProductBrandExtension
{
    public function __construct(
        private readonly ProductBrandResource $productBrandResource
    ) {
    }

    public function afterGet(ProductRepositoryInterface $subject, ProductInterface $product): ProductInterface
    {
        $extensionAttributes = $product->getExtensionAttributes();
        $extensionAttributes->setBrandId($this->productBrandResource->getBrandIdByProductId((int) $product->getId()));
        $product->setExtensionAttributes($extensionAttributes);
        return $product;
    }

    public function afterSave(ProductRepositoryInterface $subject, ProductInterface $result, ProductInterface $product): ProductInterface
    {
        $brandId = $product->getExtensionAttributes()?->getBrandId();
        if ($brandId !== null) {
            $this->productBrandResource->assign((int) $result->getId(), $brandId);
            $result->getExtensionAttributes()->setBrandId($brandId);
        }
        return $result;
    }
}
```

registered in `etc/di.xml` with `<type name="Magento\Catalog\Api\ProductRepositoryInterface"><plugin name="acme_catalog_product_brand_extension" type="Acme\Catalog\Plugin\ProductBrandExtension"/></type>`. `afterGet` covers `get()` (by SKU) — add `afterGetById` for `getById()`; `afterSave` receives the saved result *and* the original argument, reads the incoming value from the argument and writes it back onto the result. Without the `<join>`, add `afterGetList` that loads your rows for `$searchResults->getItems()` in one query (P1) and sets them. `getExtensionAttributes()` on core product/order/customer models never returns null (they create an empty object); on other entities guard with `?->` or the `afterGetExtensionAttributes` plugin from the docs. The `ProductBrandResource` methods are ordinary resource-model queries on `acme_product_brand` (`select()->from(...)->where('product_id = ?', $id)`; `insertOnDuplicate`), which is where the A5 rule is satisfied.

Extension attributes appear under `extension_attributes` in REST/GraphQL responses and are accepted on save; EAV attributes appear under `custom_attributes` (`eav.md`). Choose EAV for product/category/customer/address fields that merchants edit; choose an extension attribute for computed or relational data on any entity, and for any field on non-EAV entities (order, quote, invoice, shipment, credit memo).

## Sources

- https://developer.adobe.com/commerce/php/development/components/service-contracts/ — Service contracts (data interfaces + service interfaces, `@api`)
- https://developer.adobe.com/commerce/php/development/components/service-contracts/design-patterns — Service contract design patterns (`Api/Data` vs `Api`, repository methods `save`/`get`/`getList`/`delete`/`deleteById`, one search results interface per entity, camelCase↔snake_case conversion note, management interfaces)
- https://developer.adobe.com/commerce/php/development/components/searching-with-repositories — Searching with repositories (stateless repositories, `Filter`/`FilterGroup` OR-within/AND-between, `SortOrder`, `setPageSize`/`setCurrentPage`, search results total count, engine max results, `CollectionProcessorInterface` with Filter/Sorting/Pagination/Join processors and `fieldMapping`/`customFilters`)
- https://developer.adobe.com/commerce/php/development/components/attributes — EAV and extension attributes (`extension_attributes.xml` keywords `for`/`code`/`type`/`ref`/`reference_table`/`reference_field`/`join_on_field`/`field`, join applies on `getList()`, `ExtensionInterface` generation, resource restriction)
- https://developer.adobe.com/commerce/php/development/components/add-attributes — Add extension attributes (plugins on `save`/`get`/`getList`, `afterSave` result vs argument, `afterGetExtensionAttributes`, scalar/object/array `type` examples, `urn:magento:framework:Api/etc/extension_attributes.xsd`)
