---
name: data
description: Magento 2 persistence — declarative db_schema.xml and whitelist, data/schema patches, models/resource models/collections, repositories and service contracts, extension attributes and EAV attributes. Use when adding tables, columns, attributes, or read/write code in Magento Open Source 2.4.
---

# Magento 2 persistence

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).*

Rules: see `magento:conventions` A4–A7, P1, P2. This skill cites them by ID and does not restate them.

## When to use

- Adding a table, column, index or foreign key that your module owns.
- Adding a field to products, categories, customers or addresses (EAV attribute) or to orders, quotes, invoices and other non-EAV entities (own table + extension attribute).
- Seeding, migrating or transforming data at deploy time (data patches).
- Reading and writing entities from PHP: models, resource models, collections, repositories, `SearchCriteria`.
- Defining the service contract (`Api/`, `Api/Data/`) other modules and the web API will use.

## When not to

- Business logic, `di.xml` wiring, plugins, observers, cron, console commands, controllers → `magento:module`.
- Exposing a repository over REST or GraphQL (`webapi.xml`, `schema.graphqls`, ACL resources) → `magento:api`.
- Rendering the data (templates, layout, ViewModels) → `magento:frontend-luma` or `magento:frontend-hyva`.

## Decision guide

| Need | Use | Reference |
|---|---|---|
| New table for your module | `etc/db_schema.xml` + regenerate whitelist | `db-schema.md` |
| Column/index/FK on **your** table | edit `db_schema.xml` + whitelist | `db-schema.md` |
| Extra field on product/category/customer/address | EAV attribute via `DataPatchInterface` + `EavSetupFactory` | `eav.md` |
| Extra field on order/quote/invoice (non-EAV) | own table keyed by entity id + extension attribute | `db-schema.md`, `service-contracts.md` |
| Field on a core table | **don't** (A7); use the two rows above | — |
| Seed or transform data | `DataPatchInterface` (+ `PatchRevertableInterface`) | `patches.md` |
| Read/write entities | Repository + `SearchCriteriaBuilder`; collections for admin grids only | `service-contracts.md` |

The first question is always *whose table is it?* `catalog_product_entity`, `catalog_category_entity`, `customer_entity`, `customer_address_entity`, `sales_order`, `quote` and every other table declared under `vendor/magento` belong to core. A `<table name="catalog_product_entity">` block in your module *would* merge into core's declaration and add the column, which is exactly why it is a trap: the column is invisible to everything built on attributes (the admin product form and attribute sets, `custom_attributes` in REST and GraphQL, import/export, search and layered navigation, store-view scoping), it lives on a table you do not own (A7), and its lifetime is tied to your module — disable the module and the next `setup:upgrade` drops the column with its data. When a request says "add a column to `catalog_product_entity`", implement the product attribute instead and say why in one paragraph; do not add the column "as asked" alongside it. Products, categories, customers and addresses get an EAV attribute (`eav.md`); orders, quotes, invoices, credit memos, shipments and everything else get a table of your own keyed by the entity id plus an extension attribute (`db-schema.md`, `service-contracts.md`).

## Rules that bite

1. **A6** — Regenerate the whitelist after every `db_schema.xml` change and commit it: `bin/magento setup:db-declaration:generate-whitelist --module-name=Acme_Catalog`. New tables and columns are created without it, but every *drop* — a removed column, index, FK or table, and the drop half of a renamed column or a changed index/FK — is silently skipped for an element that is not in `db_schema_whitelist.json`, and the add half of a changed index/FK then fails with a duplicate-name error.
2. **A6** — `bin/magento setup:upgrade` applies declarative schema for all modules first, then schema patches, then data patches, in module load order. `setup:upgrade --dry-run=1` writes the DDL it would run to `var/log/dry-run-installation.log` without changing the database (and skips patches); `--safe-mode=1` dumps every dropped table and column to `var/declarative_dumps_csv/` before dropping it; `--data-restore=1` reads those dumps back.
3. **A6** — `db_schema.xml` is the desired end state, not a changelog: delete a column or table from it and the next `setup:upgrade` drops it, data included (given rule 1). A changed type, a shorter length or a new `nullable="false"` is applied in place. Rename a column with a new declaration carrying `onCreate="migrateDataFrom(old_column)"`; never rename by editing `name` (that is a drop plus an empty add).
4. **A6** — A patch runs once: `patch_list` stores its class name, and `setup:upgrade` skips anything already listed. To re-run one in development, `DELETE FROM patch_list WHERE patch_name = 'Acme\\Catalog\\Setup\\Patch\\Data\\AddBrandAttribute'` and run `setup:upgrade` again — so write `apply()` to be safe to re-run (`EavSetup::addAttribute` updates an existing attribute; use `insertOnDuplicate` for seed rows).
5. Within a module patches run in file-name order unless `getDependencies()` says otherwise; declare every patch that must run first (it may live in another module — it is then applied before yours). `getAliases()` lists former class names so a renamed patch is not applied a second time.
6. `revert()` (`PatchRevertableInterface`) runs only from `bin/magento module:uninstall` — `--remove-data` for Composer-installed modules, `--non-composer` for `app/code` modules. It never runs on `setup:upgrade`, `module:disable`, or when you delete the patch file.
7. **A4** — Repository and data-service methods take and return `Api/Data/*Interface` types (`BrandInterface`, `BrandSearchResultsInterface`), never a model, resource model or collection; `di.xml` `preference` binds each interface to its implementation. Collections stay inside the model layer (resource models, repositories, admin grid data providers).
8. **P1/P2** — Every `getList()` call sets `setPageSize()` (and `setCurrentPage()` when paging); `setTotalCount($collection->getSize())` before `getItems()`. Never `getById()`/`get()`/`->load()` inside a loop — one `getList()` with an `in` filter and a page size.
9. `getById()`/`get()` throw `NoSuchEntityException` when nothing matches — catch it at the call site instead of testing for null; `save()` wraps failures in `CouldNotSaveException`, `delete()` in `CouldNotDeleteException`.
10. **A4** — An extension attribute is `etc/extension_attributes.xml` *plus* code that fills it. A `<join>` fills it only for `getList()`, and only when the repository runs the join processor (the core product, customer and order repositories do); `get()`/`getById()` need an `afterGet` plugin on the repository interface and `save()` needs an `afterSave` plugin that persists your side and returns the entity.
11. `EavSetup::addAttribute` option keys map onto columns of two tables: `type`, `input`, `label`, `required`, `user_defined`, `source`, `backend`, `default`, `unique` → `eav_attribute`; `global`, `visible`, `visible_on_front`, `searchable`, `filterable`, `used_in_product_listing`, `is_html_allowed_on_front`, `apply_to` → `catalog_eav_attribute` (customer/address: `customer_eav_attribute` with `system`, `position`, `is_used_in_grid`...). Unknown keys are dropped without an error, and `required` defaults to **1** — always pass it explicitly.
12. **P5** — `global` is `ScopedAttributeInterface::SCOPE_GLOBAL` (1, the default), `SCOPE_WEBSITE` (2) or `SCOPE_STORE` (0). `visible` = 1 shows the attribute in the admin form; `used_in_product_listing` = 1 loads it in category and search listing collections; `searchable`/`filterable` need `bin/magento indexer:reindex catalogsearch_fulltext catalog_product_attribute` from the deploy (never from request code) — `EavSetup` writes straight to the tables and does not invalidate indexers or the `eav` cache, so end with `bin/magento cache:clean`.

## Minimal correct example

A `brand` text attribute on products (the request "add a `brand` column to `catalog_product_entity`" ends up here), plus a small owned table for a later brand entity.

`app/code/Acme/Catalog/etc/db_schema.xml`:

```xml
<?xml version="1.0"?>
<schema xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Setup/Declaration/Schema/etc/schema.xsd">
    <table name="acme_brand" resource="default" engine="innodb" comment="Acme Brand">
        <column xsi:type="int" name="entity_id" unsigned="true" nullable="false" identity="true" comment="Brand ID"/>
        <column xsi:type="varchar" name="name" nullable="false" length="255" comment="Brand Name"/>
        <column xsi:type="timestamp" name="created_at" nullable="false" default="CURRENT_TIMESTAMP" comment="Created At"/>
        <constraint xsi:type="primary" referenceId="PRIMARY">
            <column name="entity_id"/>
        </constraint>
        <constraint xsi:type="unique" referenceId="ACME_BRAND_NAME">
            <column name="name"/>
        </constraint>
    </table>
</schema>
```

`app/code/Acme/Catalog/etc/db_schema_whitelist.json` (generated by `setup:db-declaration:generate-whitelist --module-name=Acme_Catalog`; shown so you can check what it should contain):

```json
{
    "acme_brand": {
        "column": {
            "entity_id": true,
            "name": true,
            "created_at": true
        },
        "constraint": {
            "PRIMARY": true,
            "ACME_BRAND_NAME": true
        }
    }
}
```

`app/code/Acme/Catalog/Setup/Patch/Data/AddBrandAttribute.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Setup\Patch\Data;

use Magento\Catalog\Model\Product;
use Magento\Eav\Model\Entity\Attribute\ScopedAttributeInterface;
use Magento\Eav\Setup\EavSetupFactory;
use Magento\Framework\Setup\ModuleDataSetupInterface;
use Magento\Framework\Setup\Patch\DataPatchInterface;
use Magento\Framework\Setup\Patch\PatchRevertableInterface;

class AddBrandAttribute implements DataPatchInterface, PatchRevertableInterface
{
    private const ATTRIBUTE_CODE = 'brand';

    public function __construct(
        private readonly ModuleDataSetupInterface $moduleDataSetup,
        private readonly EavSetupFactory $eavSetupFactory
    ) {
    }

    public function apply(): self
    {
        $this->moduleDataSetup->getConnection()->startSetup();
        $eavSetup = $this->eavSetupFactory->create(['setup' => $this->moduleDataSetup]);
        $eavSetup->addAttribute(Product::ENTITY, self::ATTRIBUTE_CODE, [
            'type' => 'varchar',
            'label' => 'Brand',
            'input' => 'text',
            'group' => 'Product Details',
            'global' => ScopedAttributeInterface::SCOPE_STORE,
            'required' => false,
            'user_defined' => true,
            'visible' => true,
            'visible_on_front' => true,
            'used_in_product_listing' => true,
            'searchable' => true,
            'sort_order' => 60,
        ]);
        $this->moduleDataSetup->getConnection()->endSetup();
        return $this;
    }

    public function revert(): void
    {
        $this->moduleDataSetup->getConnection()->startSetup();
        $eavSetup = $this->eavSetupFactory->create(['setup' => $this->moduleDataSetup]);
        $eavSetup->removeAttribute(Product::ENTITY, self::ATTRIBUTE_CODE);
        $this->moduleDataSetup->getConnection()->endSetup();
    }

    public static function getDependencies(): array
    {
        return [];
    }

    public function getAliases(): array
    {
        return [];
    }
}
```

Why this shape: the value lands in `catalog_product_entity_varchar` keyed by product, attribute and store, so it is store-scoped (`SCOPE_STORE`), editable in the admin form (`visible`; `group` = `Product Details` resolves by group code `product-details` to the default tab of every attribute set — do **not** write `General`: `EavSetup` maps that name through `default_id` = 1 onto the same tab and renames it "General" in every set), returned as `custom_attributes` by `GET /V1/products/:sku`, loaded in listings (`used_in_product_listing`) and searchable after a reindex — none of which a raw column gives you. The patch constructor takes `ModuleDataSetupInterface` under that exact parameter name (the applier injects the setup-bound instance by name) and `EavSetupFactory` (never `EavSetup` directly); `startSetup()`/`endSetup()` disable foreign-key checks and set the SQL mode around the writes; `revert()` mirrors `apply()` for `module:uninstall`. Apply with `bin/magento setup:upgrade && bin/magento cache:clean && bin/magento indexer:reindex catalogsearch_fulltext`. Read it with `$product->getData('brand')` or `$product->getCustomAttribute('brand')?->getValue()`.

## Routing table

| For | Read |
|---|---|
| `db_schema.xml` elements and column types, constraints/indexes and their names, whitelist, `setup:upgrade` flags, renaming and dropping safely, own table + FK to a core entity | `references/db-schema.md` |
| `DataPatchInterface`/`SchemaPatchInterface`, `PatchRevertableInterface`, dependencies and aliases, `patch_list`, re-running, ordering across modules, legacy `PatchVersionInterface` | `references/patches.md` |
| `Api/Data` interfaces, repository interface and implementation, search results, model/resource model/collection, `CollectionProcessorInterface`, `di.xml` preferences, `SearchCriteriaBuilder`, extension attributes and `<join>` | `references/service-contracts.md` |
| Product/category/customer/address attributes with `EavSetupFactory`, every option key, attribute sets and groups, source models, customer forms, reading values on the frontend, reindexing | `references/eav.md` |
