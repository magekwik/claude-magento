# Declarative schema: `db_schema.xml` and the whitelist

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (A6 for schema, A5 for access, A7 for ownership).

## How it works

Every module declares the tables it owns in `etc/db_schema.xml`. On `bin/magento setup:upgrade` (and `setup:install`) Magento merges the files of all enabled modules into one declared schema, reads the live database, diffs the two and runs the DDL that turns the database into the declaration — *before* any schema or data patch. The file is the desired end state, not a changelog: there are no versions, and `InstallSchema`/`UpgradeSchema` scripts are legacy (A6; `Magento2.Legacy.InstallUpgrade` flags them).

Two consequences drive everything below:

- A declaration only ever *extends* what other modules declared for the same table name; you cannot remove their elements except with `disabled="true"`, and you should not touch core tables at all (A7).
- Removing an element from your file means "drop it". The whitelist (below) is what lets Magento tell a dropped element from one that some legacy script created.

## `etc/db_schema.xml`

```xml
<?xml version="1.0"?>
<schema xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Setup/Declaration/Schema/etc/schema.xsd">
    <table name="acme_product_brand" resource="default" engine="innodb" comment="Acme Product Brand Assignment">
        <column xsi:type="int" name="entity_id" unsigned="true" nullable="false" identity="true" comment="Row ID"/>
        <column xsi:type="int" name="product_id" unsigned="true" nullable="false" comment="Product ID"/>
        <column xsi:type="int" name="brand_id" unsigned="true" nullable="false" comment="Brand ID"/>
        <column xsi:type="smallint" name="position" unsigned="true" nullable="false" default="0" comment="Position"/>
        <column xsi:type="decimal" name="royalty" unsigned="true" nullable="false" precision="12" scale="4" default="0" comment="Royalty"/>
        <column xsi:type="boolean" name="is_primary" nullable="false" default="false" comment="Is Primary Brand"/>
        <column xsi:type="text" name="notes" nullable="true" comment="Notes"/>
        <column xsi:type="json" name="meta" nullable="true" comment="Metadata"/>
        <column xsi:type="timestamp" name="created_at" nullable="false" default="CURRENT_TIMESTAMP" comment="Created At"/>
        <column xsi:type="timestamp" name="updated_at" nullable="false" default="CURRENT_TIMESTAMP" on_update="true" comment="Updated At"/>
        <constraint xsi:type="primary" referenceId="PRIMARY">
            <column name="entity_id"/>
        </constraint>
        <constraint xsi:type="unique" referenceId="ACME_PRODUCT_BRAND_PRODUCT_ID">
            <column name="product_id"/>
        </constraint>
        <constraint xsi:type="foreign" referenceId="ACME_PRODUCT_BRAND_PRODUCT_ID_CATALOG_PRODUCT_ENTITY_ENTITY_ID" table="acme_product_brand" column="product_id" referenceTable="catalog_product_entity" referenceColumn="entity_id" onDelete="CASCADE"/>
        <constraint xsi:type="foreign" referenceId="ACME_PRODUCT_BRAND_BRAND_ID_ACME_BRAND_ENTITY_ID" table="acme_product_brand" column="brand_id" referenceTable="acme_brand" referenceColumn="entity_id" onDelete="CASCADE"/>
        <index referenceId="ACME_PRODUCT_BRAND_BRAND_ID" indexType="btree">
            <column name="brand_id"/>
        </index>
    </table>
</schema>
```

This is the "own table with a foreign key to a core entity" pattern: one row per product, `onDelete="CASCADE"` so deleting the product removes the row, a unique constraint on `product_id` because it is one-to-one, and an index on `brand_id` for lookups. Expose it to other modules as an extension attribute on `ProductInterface` (`service-contracts.md`) and never as a column on `catalog_product_entity`.

### `<table>`

| Attribute | Values | Notes |
|---|---|---|
| `name` | table name without prefix | required; unique per file |
| `resource` | `default`, `checkout`, `sales` | connection name from `app/etc/env.php` `db/connection`; a name that is not configured there falls back to `default`, so in Open Source everything is `default` |
| `engine` | `innodb`, `memory` | `innodb` unless the table is a throwaway cache |
| `comment` | text | shows up in `SHOW CREATE TABLE`; give one |
| `onCreate` | `migrateDataFromAnotherTable(old_table)` | copies rows when the table is *created* (table rename); slow on big tables |
| `disabled` | `true` | removes a table another module declared — do not use on core tables (A7) |
| `charset`, `collation` | MySQL names | rarely needed; the default is the connection's |

### `<column>` types and attributes

Common attributes on every type: `name` (required, ≤ 64 characters), `comment`, `nullable`, `default`, `onCreate="migrateDataFrom(old_column)"`, `disabled`.

| `xsi:type` | Extra attributes | Notes |
|---|---|---|
| `int`, `smallint`, `bigint`, `tinyint` | `unsigned`, `identity` (auto-increment), `padding` | `default` is digits or `null`; `padding` is the integer display width (2–255; deprecated in MySQL 8, leave it out) |
| `decimal`, `float`, `double` | `precision`, `scale`, `unsigned` | `precision` ≥ `scale` or validation fails; money is `decimal` — core uses `precision="20" scale="4"` for order totals and `20`/`6` for product prices |
| `varchar`, `char` | `length` (varchar ≤ 1024 in the XSD) | `varchar` `length="255"` for names and codes |
| `text`, `mediumtext`, `longtext` | — | no `default`, no `length` |
| `json` | — | native JSON column; encode and decode through `SerializerInterface` (S5) |
| `blob`, `mediumblob`, `longblob`, `varbinary` | `varbinary` takes `length` | binary payloads |
| `boolean` | — | stored as `tinyint(1)`; `default="true"`/`"false"` |
| `date` | — | `nullable` only |
| `datetime`, `timestamp` | `on_update="true"` | `default` is `CURRENT_TIMESTAMP`, `0` (needs `NO_ZERO_DATE` off) or `NULL`; `on_update="true"` adds `ON UPDATE CURRENT_TIMESTAMP`; `timestamp` is stored in UTC and converted by the connection time zone, `datetime` is stored verbatim |

Booleans in attributes are the strings `true`/`false`. `identity="true"` needs the column in the primary key (or another index) — the validator rejects an auto-increment column without an index, and rejects a nullable column in a primary key.

### `<constraint>`

- `xsi:type="primary"` with `referenceId="PRIMARY"` and one or more `<column name=""/>` children. One per table; all columns `nullable="false"`.
- `xsi:type="unique"` with a `referenceId` and `<column>` children.
- `xsi:type="foreign"` with `referenceId`, `table` (this table), `column`, `referenceTable`, `referenceColumn` and `onDelete` = `CASCADE`, `SET NULL` or `NO ACTION`. There is no `onUpdate`. The two columns must have the same type, signedness and size or validation fails ("Column definition ... and reference column definition ... are different"), and the referenced column must be covered by a primary/unique constraint or an index in its own declaration. Both tables must be declarative — you can reference `catalog_product_entity`, `customer_entity`, `sales_order`, `store`, etc.

### `<index>`

`referenceId` plus `indexType` = `btree` (default), `fulltext` or `hash`, with `<column>` children. A `fulltext` index is what `MATCH ... AGAINST` needs; everything else is `btree`.

### Naming `referenceId`

With no table prefix configured, `referenceId` *is* the database name of the index or constraint, so use the names Magento itself generates — the whitelist generator writes exactly these and the diff matches on them:

- primary key: `PRIMARY`
- index and unique constraint: `<TABLE>_<COLUMN>[_<COLUMN>...]` upper-case, e.g. `ACME_PRODUCT_BRAND_BRAND_ID`
- foreign key: `<TABLE>_<COLUMN>_<REFERENCE_TABLE>_<REFERENCE_COLUMN>`, e.g. `ACME_PRODUCT_BRAND_PRODUCT_ID_CATALOG_PRODUCT_ENTITY_ENTITY_ID`

Names are capped at 64 characters; longer ones are abbreviated (core's `CAT_PRD_ENTT_DTIME_ATTR_ID_EAV_ATTR_ATTR_ID`). When in doubt run the whitelist generator and copy the name it wrote into `referenceId`. With a table prefix Magento generates the real names itself and the whitelist cannot be generated on that install — generate it on a prefix-less development database.

## `etc/db_schema_whitelist.json`

The whitelist is the module's record of every table, column, index and constraint its declarative schema has ever created. Regenerate it after **every** change to `db_schema.xml` and commit it:

```bash
bin/magento setup:db-declaration:generate-whitelist --module-name=Acme_Catalog   # one module
bin/magento setup:db-declaration:generate-whitelist                              # all modules (--module-name=all)
```

The generator merges into the existing file and never removes entries — that is intended: the file is a history, and an old name has to stay so the element can still be dropped.

What it gates (2.4.9 `Magento\Framework\Setup\Declaration\Schema\Diff\Diff::canBeRegistered`): only *destructive* operations — dropping a table, column, index or constraint, dropping a foreign key reference, and re-creating a table. Adding and modifying is never gated. So:

- A brand-new table or column is created even if you forgot the whitelist — which is how modules ship without one and then cannot evolve.
- Removing a column, index, FK or table from the XML does nothing unless that element is whitelisted (docs: "It is possible to drop a column only if it exists in the `db_schema_whitelist.json` file").
- Changing an index's or constraint's columns is a drop plus an add. If the old one is not whitelisted the drop is skipped and the add fails on the existing name (`Duplicate key name` / duplicate foreign key).
- Renaming a column is an add (new name) plus a drop (old name): whitelist both, i.e. regenerate after the rename so the file contains the old and the new name.
- Whitelists of *disabled* modules are still read, so a disabled module's whitelisted tables are dropped on the next `setup:upgrade` (see below).

Shape (the generator writes it; shown for review):

```json
{
    "acme_product_brand": {
        "column": {
            "entity_id": true,
            "product_id": true,
            "brand_id": true,
            "position": true,
            "royalty": true,
            "is_primary": true,
            "notes": true,
            "meta": true,
            "created_at": true,
            "updated_at": true
        },
        "index": {
            "ACME_PRODUCT_BRAND_BRAND_ID": true
        },
        "constraint": {
            "PRIMARY": true,
            "ACME_PRODUCT_BRAND_PRODUCT_ID": true,
            "ACME_PRODUCT_BRAND_PRODUCT_ID_CATALOG_PRODUCT_ENTITY_ENTITY_ID": true,
            "ACME_PRODUCT_BRAND_BRAND_ID_ACME_BRAND_ENTITY_ID": true
        }
    }
}
```

Unique constraints are listed under `constraint`, plain indexes under `index`.

## Commands

```bash
bin/magento setup:upgrade                    # declarative schema (all modules) → schema patches → data patches → config import
bin/magento setup:upgrade --dry-run=1        # log the DDL to var/log/dry-run-installation.log; no DB change, patches skipped
bin/magento setup:upgrade --safe-mode=1      # dump every dropped table/column to var/declarative_dumps_csv/*.csv first
bin/magento setup:upgrade --data-restore=1   # read those dumps back after checking out the previous code
bin/magento setup:upgrade --keep-generated   # production deploys only: do not delete generated/ code
bin/magento setup:db:status                  # "All modules are up to date." or which module needs setup:upgrade
```

`--dry-run=1` runs the diff and writes the resulting `CREATE`/`ALTER` statements (data-migration triggers such as `migrateDataFrom` are not logged); read the log before every schema-changing deploy. `--safe-mode=1` dumps only for the destructive operations above; a type change is applied in place without a dump, so back up the table yourself before shrinking or retyping a column. In-place changes and drops run inside `startSetup()` (foreign-key checks off), so a failed `ALTER` leaves the run half applied — fix and rerun `setup:upgrade`, the diff is idempotent.

Also relevant: `setup:db-declaration:generate-whitelist` (above), `setup:db-schema:upgrade` / `setup:db-data:upgrade` (the two halves of `setup:upgrade`, for ops scripts).

## Evolving a schema safely

| Change | How | Data |
|---|---|---|
| Add a column | add `<column>`; `nullable="true"` or a `default` so existing rows are valid | kept |
| Add an index/unique/FK | add the element; regenerate whitelist | kept; a new unique constraint or FK fails on existing duplicates/orphans, and declarative schema runs *before* patches, so ship the clean-up patch one release earlier |
| Widen a column (`length` up, `int` → `bigint`) | edit the attribute; applied as `MODIFY COLUMN` | kept |
| Shrink, retype, or add `nullable="false"` | same edit; applied in place, no dump | may be truncated or fail on NULLs — migrate data in an earlier release |
| Rename a column | new `<column name="new" onCreate="migrateDataFrom(old)"/>`, delete the old `<column>`; regenerate whitelist | copied (`UPDATE t SET new = old` after the add, then the old column is dropped) |
| Rename a table | new `<table name="new" onCreate="migrateDataFromAnotherTable(old)">`, delete the old `<table>`; regenerate whitelist | copied row by row; not combined with column renames; slow on big tables — for those dump with `--safe-mode=1` and reload in a patch |
| Drop a column/index/FK/table | delete the element; it must be whitelisted | **lost** — `--safe-mode=1` if you may need it |
| Remove an element another module declared | redeclare it with `disabled="true"` | lost; only for modules that depend on yours, never core |
| Change a foreign key's `onDelete` | edit `onDelete` — it is dropped and re-added | kept |

Backward compatibility (Q4 spirit): within a release line only add columns (nullable or defaulted), add indexes, and widen types. Renames and drops are breaking changes for anyone who joined your table; schedule them for a major version and announce them.

## Disabling and uninstalling a module

When a module is disabled in `app/etc/config.php` its `db_schema.xml` is no longer read, but its whitelist still is — so the next `setup:upgrade` sees whitelisted tables and columns that no declaration claims and **drops them**. Before disabling a module with data you want: `bin/magento setup:upgrade --safe-mode=1`, and `--data-restore=1` after re-enabling it. `module:uninstall` is the deliberate path: it reverts revertable data patches and, with `--remove-data`, runs the module's `Setup/Uninstall.php` if any (`patches.md`).

## Reading the data (A5)

Declaring the table is half the job. Access goes through a resource model (`_init('acme_product_brand', 'entity_id')`), a collection and a repository — `service-contracts.md` — never `SELECT` strings. If you must touch the connection (bulk `insertOnDuplicate`, `deleteFromSelect`), get it from the resource model's `getConnection()` and use the adapter's bound methods (`fetchAll($select, $bind)`, `insertMultiple`, `update($table, $data, ['entity_id = ?' => $id])`); `getTable('acme_product_brand')` resolves the prefix.

## Sources

- https://developer.adobe.com/commerce/php/development/components/declarative-schema/configuration — Configure declarative schema (`schema`/`table`/`column`/`constraint`/`index` reference, `xsi:type` list, `onDelete` values, no `ON UPDATE`, `referenceId` from the whitelist, create/drop/rename/change-type/index/FK walkthroughs, `disabled`, disabled-module drop behaviour with `--safe-mode=1`/`--data-restore=1`)
- https://developer.adobe.com/commerce/php/development/components/declarative-schema/migration-scripts — Migrate install/upgrade scripts to declarative schema (`setup:db-declaration:generate-whitelist [--module-name]`, whitelist purpose "required to allow drop operations", prefix warning, `--dry-run=1` → `var/log/dry-run-installation.log`, `--safe-mode=1`/`--data-restore=1` → `var/declarative_dumps_csv/`, `--convert-old-scripts=1`, sample whitelist JSON)
- https://developer.adobe.com/commerce/php/development/components/declarative-schema/ — Declarative schema overview (desired end state, upgrade scripts being phased out)
- https://developer.adobe.com/commerce/php/development/components/declarative-schema/patches — Develop data and schema patches (declarative schema is applied before patches)
