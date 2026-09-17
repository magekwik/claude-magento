# EAV attributes: products, categories, customers, addresses

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (A6 patches, A7 no core-table columns, P1/P5 loading and indexing).

## What you get, and where it lives

Products, categories, customers and customer addresses are EAV entities: the entity row (`catalog_product_entity`, `catalog_category_entity`, `customer_entity`, `customer_address_entity`) holds only static columns, and every other field is an *attribute* whose values sit in `<entity_table>_<backend_type>` (`catalog_product_entity_varchar`, `_int`, `_decimal`, `_text`, `_datetime`) keyed by entity, attribute and — for catalog — store. Adding a field to one of these entities therefore means adding an attribute, never a column (A7; `SKILL.md`).

| Table | Holds |
|---|---|
| `eav_entity_type` | the entity types: `catalog_product`, `catalog_category`, `customer`, `customer_address` (constants `Magento\Catalog\Model\Product::ENTITY`, `Category::ENTITY`, `Magento\Customer\Model\Customer::ENTITY`, `Magento\Customer\Api\AddressMetadataInterface::ENTITY_TYPE_ADDRESS`) |
| `eav_attribute` | one row per attribute: `attribute_code`, `backend_type`, `frontend_input`, `frontend_label`, `is_required`, `is_user_defined`, `source_model`, `backend_model`, `frontend_model`, `default_value`, `is_unique`, `note` |
| `catalog_eav_attribute` | catalog-only flags: `is_global`, `is_visible`, `is_searchable`, `is_filterable`, `is_filterable_in_search`, `is_visible_on_front`, `is_html_allowed_on_front`, `used_in_product_listing`, `used_for_sort_by`, `is_comparable`, `is_wysiwyg_enabled`, `apply_to`, `position`, grid flags |
| `customer_eav_attribute` | customer-only: `is_system`, `is_visible`, `sort_order`, `input_filter`, `validate_rules`, `multiline_count`, grid flags |
| `eav_attribute_set`, `eav_attribute_group`, `eav_entity_attribute` | which sets and groups an attribute appears in (the admin form layout) |
| `eav_attribute_option`, `eav_attribute_option_value` | options of `select`/`multiselect` attributes, per store |
| `customer_form_attribute` | which forms accept a customer/address attribute (`used_in_forms`) |

`EavSetup::addAttribute()` writes all of these from one options array; when debugging an attribute, query `eav_attribute` joined with the entity's additional table.

## Creating an attribute: the data patch

Always through a data patch (`patches.md`) with the entity's setup factory — never `EavSetup` itself, never the admin UI as the source of truth:

| Entity | Factory | Extra methods |
|---|---|---|
| product, category | `Magento\Eav\Setup\EavSetupFactory` (or `Magento\Catalog\Setup\CategorySetupFactory`, same API plus category helpers) | — |
| customer, address | `Magento\Customer\Setup\CustomerSetupFactory` | `getEavConfig()` for `used_in_forms` |

`$factory->create(['setup' => $this->moduleDataSetup])` binds it to the patch's setup connection. `addAttribute($entityType, $code, $options)` inserts the attribute or **updates it if the code already exists**, then — when `group` is given *or* `user_defined` is empty — adds it to that group (creating it) in **every** attribute set of the entity type, and finally inserts `option` values. The `SKILL.md` example is the product case; the customer case is below.

Attribute codes: `^[a-zA-Z][a-zA-Z0-9_]*$`, at most 60 characters, prefixed with your vendor for anything generic (`acme_brand_id`) so a merchant's own attribute cannot collide. A *user-defined* product attribute may not use a code that matches a `Product::get*()` accessor in snake_case (`status`, `name`, `type_id`, `store_id`, `category_ids`, `options`, `image`, `weight`, `price`…) — `addAttribute` throws "reserved by system".

### Option keys (`addAttribute` third argument)

Keys not in these tables are silently dropped (`is_html_allowed_on_frontend` — a common typo — does nothing). Booleans may be passed as `true`/`false`; they are stored as 1/0.

Base keys (every entity type → `eav_attribute`):

| Key | Column | Default | What it controls |
|---|---|---|---|
| `type` | `backend_type` | `varchar` | value table: `varchar` (≤255), `int`, `decimal`, `text`, `datetime`, `static` (a real column on the entity table — core only). **Not derived from `input`**: pass `int` for `select`/`boolean`, `text` for `multiselect`/`textarea`, `datetime` for `date`, `decimal` for `price`/`weight` |
| `input` | `frontend_input` | `text` | admin form control: `text`, `textarea`, `select`, `multiselect`, `boolean`, `date`, `datetime`, `price`, `weight`, `media_image`, `hidden`, `gallery`. The admin's *Text Editor* type is not a stored value — it is `textarea` plus `wysiwyg_enabled` |
| `label` | `frontend_label` | — | admin label; translate in `i18n` by the label string (Q5) |
| `required` | `is_required` | **1** | pass `false` explicitly for optional fields — the default makes every existing product invalid in the form |
| `user_defined` | `is_user_defined` | 0 | 1 = merchant may edit/delete it in *Stores > Attributes* and it is added to sets only when `group` is given; 0 = system attribute, no Delete button, added to every set (into `group`, or the group with `default_id` = 1 — *Product Details* — when none is given) |
| `source` | `source_model` | — | class providing options: `Magento\Eav\Model\Entity\Attribute\Source\Boolean` (Yes/No), `...\Source\Table` (options from `eav_attribute_option`, the default for `select`/`multiselect` with `option`), or your own `AbstractSource` subclass with `getAllOptions()` |
| `backend` | `backend_model` | — | value handling: `Magento\Eav\Model\Entity\Attribute\Backend\ArrayBackend` (required for `multiselect` — stores `1,4,7`), `...\Backend\Datetime`, `Magento\Catalog\Model\Product\Attribute\Backend\Price` for `price` |
| `frontend` | `frontend_model` | — | rendering helper; rarely needed (`Magento\Eav\Model\Entity\Attribute\Frontend\Datetime`) |
| `frontend_class` | `frontend_class` | — | admin validation class: `validate-number`, `validate-digits`, `validate-email`, `validate-url`, `validate-alpha`, `validate-alphanum` |
| `default` | `default_value` | — | default for new entities (for `select`, the option id) |
| `unique` | `is_unique` | 0 | 1 = unique per entity type (validated on save) |
| `note` | `note` | — | help text under the field |
| `sort_order` | `eav_entity_attribute.sort_order` | — | position inside the group |
| `option` | option tables | — | `['values' => ['Red', 'Green']]` creates options (store 0), skipping values that already exist |
| `group` | `eav_entity_attribute` | — | attribute group (= admin form tab) name, matched by its code (`Product Details` → `product-details`) in every attribute set and created there if missing. The default product set has `Product Details` (the default landing tab, `default_id` = 1), `Content`, `Images`, `Search Engine Optimization`, `Advanced Pricing`, `Design`, `Schedule Design Update`, `Autosettings`. **Never pass `General`**: `EavSetup` maps the code `general` to `default_id` = 1, so it resolves to *Product Details* and **renames that tab to "General" in every set**. Any other unused name creates a genuinely new tab. Categories: `General Information`, `Display Settings`, `Custom Design` |

Catalog keys (product and category → `catalog_eav_attribute`):

| Key | Column | Default | What it controls |
|---|---|---|---|
| `global` | `is_global` | `1` (GLOBAL) | scope: `ScopedAttributeInterface::SCOPE_GLOBAL` (1), `SCOPE_WEBSITE` (2), `SCOPE_STORE` (0). Store-scoped values are saved per `store_id` with `0` as the default |
| `visible` | `is_visible` | 1 | shown in the admin product/category form and attribute-set editor |
| `visible_on_front` | `is_visible_on_front` | 0 | listed on the product page *More Information* tab (Luma `catalog_product_view` attributes block) |
| `is_html_allowed_on_front` | `is_html_allowed_on_front` | 0 | 1 = that tab prints the value unescaped — only for trusted HTML (S3) |
| `used_in_product_listing` | `used_in_product_listing` | 0 | 1 = loaded in category/search listing collections and the flat table, so `$product->getData()` works in `list.phtml` |
| `used_for_sort_by` | `used_for_sort_by` | 0 | offered in the listing sort dropdown |
| `searchable` | `is_searchable` | 0 | indexed into `catalogsearch_fulltext` |
| `filterable` / `filterable_in_search` | `is_filterable` / `is_filterable_in_search` | 0 | layered navigation (category / search results); `select`/`multiselect`/`boolean`/`price` only; `is_filterable` = 1 with results, 2 without |
| `visible_in_advanced_search` | `is_visible_in_advanced_search` | 0 | Advanced Search form |
| `comparable` | `is_comparable` | 0 | product compare |
| `wysiwyg_enabled` | `is_wysiwyg_enabled` | 0 | WYSIWYG editor on `textarea` |
| `apply_to` | `apply_to` | all | comma-separated type ids (`simple,virtual,configurable`); empty = all types |
| `used_for_promo_rules` | `is_used_for_promo_rules` | 0 | usable in cart price rule conditions |
| `is_used_in_grid`, `is_visible_in_grid`, `is_filterable_in_grid` | same | 0 | admin product grid column/filter |
| `position` | `position` | 0 | order in layered navigation |
| `input_renderer` | `frontend_input_renderer` | — | custom admin form renderer block |

Customer keys (customer and address → `customer_eav_attribute`): `system` (`is_system`, default **1** — pass `false` for anything a merchant should see as custom), `visible` (`is_visible`, 1), `position` (`sort_order`), `input_filter`, `validate_rules`, `multiline_count`, `data` (`data_model`), and the grid flags `is_used_in_grid`, `is_visible_in_grid`, `is_filterable_in_grid`, `is_searchable_in_grid`. Customer attributes are always global.

## Product attribute variants

Select with options and a Yes/No flag, added to the `Product Details` tab of every set:

```php
$eavSetup->addAttribute(Product::ENTITY, 'acme_material', [
    'type' => 'int',
    'label' => 'Material',
    'input' => 'select',
    'source' => \Magento\Eav\Model\Entity\Attribute\Source\Table::class,
    'option' => ['values' => ['Cotton', 'Linen', 'Wool']],
    'group' => 'Product Details',
    'global' => ScopedAttributeInterface::SCOPE_GLOBAL,
    'required' => false,
    'user_defined' => true,
    'filterable' => true,
    'searchable' => true,
    'used_in_product_listing' => true,
    'apply_to' => 'simple,configurable',
]);
$eavSetup->addAttribute(Product::ENTITY, 'acme_is_organic', [
    'type' => 'int',
    'label' => 'Organic',
    'input' => 'boolean',
    'source' => \Magento\Eav\Model\Entity\Attribute\Source\Boolean::class,
    'default' => '0',
    'group' => 'Product Details',
    'required' => false,
    'user_defined' => true,
]);
```

A `multiselect` is `'type' => 'text'`, `'input' => 'multiselect'`, `'backend' => \Magento\Eav\Model\Entity\Attribute\Backend\ArrayBackend::class`, `'source' => Table::class`. A category attribute is the same call with `Category::ENTITY` and a category group. A custom source model extends `Magento\Eav\Model\Entity\Attribute\Source\AbstractSource` and implements `getAllOptions(): array` returning `[['value' => ..., 'label' => __('...')], ...]`.

Later changes go through `updateAttribute(Product::ENTITY, 'acme_material', 'is_searchable', 1)` (field name is the *column*, not the option key) in a new patch; add an option later with `addAttributeOption(['attribute_id' => $eavSetup->getAttributeId(Product::ENTITY, 'acme_material'), 'values' => ['Silk']])`; remove with `removeAttribute(Product::ENTITY, 'acme_material')` (drops the attribute and, through the foreign keys, all its values).

### Attribute sets and groups

`addAttribute` with `group` puts the attribute into every existing set. To target one set: leave `group` out (with `user_defined` = 1 nothing is assigned), then

```php
$setId = $eavSetup->getAttributeSetId(Product::ENTITY, 'Bag'); // by name or id; getDefaultAttributeSetId() for "Default"
$groupId = $eavSetup->getAttributeGroupId(Product::ENTITY, $setId, 'Product Details');
$eavSetup->addAttributeToGroup(Product::ENTITY, $setId, $groupId, 'acme_material', 60);
```

A set a merchant creates later copies the groups and attributes of the set it is "based on", so an attribute assigned to only some sets stays out of the others until an admin adds it.

## Customer and address attributes

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Setup\Patch\Data;

use Magento\Customer\Api\CustomerMetadataInterface;
use Magento\Customer\Model\ResourceModel\Attribute as AttributeResource;
use Magento\Customer\Setup\CustomerSetupFactory;
use Magento\Framework\Setup\ModuleDataSetupInterface;
use Magento\Framework\Setup\Patch\DataPatchInterface;

class AddCustomerLoyaltyIdAttribute implements DataPatchInterface
{
    private const ATTRIBUTE_CODE = 'acme_loyalty_id';

    public function __construct(
        private readonly ModuleDataSetupInterface $moduleDataSetup,
        private readonly CustomerSetupFactory $customerSetupFactory,
        private readonly AttributeResource $attributeResource
    ) {
    }

    public function apply(): self
    {
        $this->moduleDataSetup->getConnection()->startSetup();
        $customerSetup = $this->customerSetupFactory->create(['setup' => $this->moduleDataSetup]);
        $customerSetup->addAttribute(CustomerMetadataInterface::ENTITY_TYPE_CUSTOMER, self::ATTRIBUTE_CODE, [
            'type' => 'varchar',
            'label' => 'Loyalty ID',
            'input' => 'text',
            'required' => false,
            'visible' => true,
            'user_defined' => true,
            'system' => false,
            'position' => 200,
            'is_used_in_grid' => true,
            'is_visible_in_grid' => true,
            'is_filterable_in_grid' => true,
            'is_searchable_in_grid' => true,
        ]);
        $customerSetup->addAttributeToSet(
            CustomerMetadataInterface::ENTITY_TYPE_CUSTOMER,
            CustomerMetadataInterface::ATTRIBUTE_SET_ID_CUSTOMER,
            null,
            self::ATTRIBUTE_CODE
        );
        $attribute = $customerSetup->getEavConfig()
            ->getAttribute(CustomerMetadataInterface::ENTITY_TYPE_CUSTOMER, self::ATTRIBUTE_CODE);
        $attribute->setData('used_in_forms', ['adminhtml_customer', 'customer_account_create', 'customer_account_edit']);
        $this->attributeResource->save($attribute);
        $this->moduleDataSetup->getConnection()->endSetup();
        return $this;
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

- `system => false` and `user_defined => true` together make it a real custom attribute: it is returned in `custom_attributes` by the customer API (`system` attributes are not) and editable in admin.
- Customers have exactly one attribute set (`ATTRIBUTE_SET_ID_CUSTOMER` = 1; addresses `AddressMetadataInterface::ATTRIBUTE_SET_ID_ADDRESS` = 2); `addAttributeToSet` with group `null` uses the default group.
- `used_in_forms` decides which forms *accept, validate and save* the attribute; saving it goes through the customer attribute resource model, which rewrites `customer_form_attribute`. Form codes: customer `adminhtml_customer`, `customer_account_create`, `customer_account_edit`, `checkout_register`, `adminhtml_checkout`; address `adminhtml_customer_address`, `customer_address_edit`, `customer_register_address`. The admin customer form renders every attribute with `visible` = 1 automatically; storefront templates do not — the register/edit forms need the input added in the theme (`magento:frontend-luma` / `magento:frontend-hyva`), and the value then round-trips through `CustomerInterface::getCustomAttribute('acme_loyalty_id')`.
- Grid flags need `bin/magento indexer:reindex customer_grid` to show existing customers' values.
- Address attributes: `AddressMetadataInterface::ENTITY_TYPE_ADDRESS`, the address forms above, and the quote/order address copy needs `fieldset.xml` entries — out of scope here.

## Reading attribute values

```php
$product->getData('brand');                       // raw stored value for the loaded store; null when unset
$product->getBrand();                             // same, via the magic getter — prefer getData('brand') for greppability
$product->getAttributeText('acme_material');      // option label(s) of a select/multiselect for the current store; false if unset
$product->getCustomAttribute('brand')?->getValue(); // the API view (AttributeInterface), what REST returns in custom_attributes
$product->getResource()->getAttribute('brand')->getFrontend()->getValue($product); // formatted (dates, prices, labels)
```

- Loaded product (`ProductRepositoryInterface::get`, product page): every attribute is available. Listing and search collections load only static columns plus attributes with `used_in_product_listing` = 1 — or those you name with `$collection->addAttributeToSelect('brand')` in your own collection. Do not load products one by one to read an attribute in a listing (P1).
- Store scope: the value returned is the one for the collection's/repository's store with fallback to the default (`store_id` 0). Saving a store-scoped value through `ProductRepositoryInterface::save` uses the repository's store (`$product->setStoreId()` or the `store_id` argument on REST).
- Customer: `CustomerInterface::getCustomAttribute('acme_loyalty_id')?->getValue()`; the legacy `Customer` model has `getData()` as well.
- GraphQL adds a *user-defined* product attribute as a field of `ProductInterface` only when at least one of `comparable`, `filterable`, `filterable_in_search`, `visible_on_front`, `used_in_product_listing`, `used_for_sort_by` is 1 (and offers `custom_attributesV2` for the rest); REST returns every product attribute outside the built-in `ProductInterface::ATTRIBUTES` list in `custom_attributes` (`magento:api`).

## After the patch

```bash
bin/magento setup:upgrade
bin/magento cache:clean                                                      # eav + config caches; EavSetup does not invalidate them
bin/magento indexer:reindex catalog_product_attribute catalogsearch_fulltext # searchable/filterable/sort attributes
bin/magento indexer:reindex catalog_product_flat                             # only if the flat catalog is enabled
```

`EavSetup` writes rows directly, so the indexer-invalidation plugins that fire when an attribute is saved from the admin do not run; existing products get indexed values only after the reindex (P5: do it from the deploy, not from request code). `catalog_product_attribute` covers filterable/sortable `select`/`multiselect`/`boolean` attributes; `catalogsearch_fulltext` covers searchable ones.

## Sources

- https://developer.adobe.com/commerce/php/development/components/attributes — EAV and extension attributes (custom vs extension attributes, `system` option for customers and `getCustomAttributes()`, customer attribute data patch with `CustomerSetupFactory`, "customer custom attribute scope is Global only", the product `addAttribute` option reference with defaults — `required` 1, `global` 1, `user_defined` 0, `visible` 1, `type` varchar, `input` text)
- https://developer.adobe.com/commerce/php/tutorials/admin/custom-text-field-attribute — Add a custom text field attribute (customer attribute patch: `system` 0/`user_defined` 1, `addAttributeToSet(..., ATTRIBUTE_SET_ID_CUSTOMER, null, ...)`, `used_in_forms` saved through `Magento\Customer\Model\ResourceModel\Attribute`, grid flags)
- https://experienceleague.adobe.com/en/docs/commerce-learn/tutorials/backend-development/add-product-attribute — Create a product attribute (`Product::ENTITY` `addAttribute` example with `group`, `type`, `input`, `source`, `global`, `visible`, `visible_on_front`, grid flags; its sample is a legacy `InstallData` script — use a data patch, A6)
- https://developer.adobe.com/commerce/php/development/components/declarative-schema/patches — Develop data and schema patches (the patch mechanics the examples rely on)
