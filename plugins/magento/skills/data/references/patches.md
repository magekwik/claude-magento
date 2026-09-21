# Data and schema patches

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magekwik-magento:conventions` (A6 for patches vs legacy scripts, A5 for data access, A1/A9 for construction).

## What a patch is

A patch is a class that `bin/magento setup:upgrade` runs **once** and records. Two kinds, by directory and interface:

| Kind | Path | Implements | Constructed with | Use for |
|---|---|---|---|---|
| Data patch | `Setup/Patch/Data/<Name>.php` | `Magento\Framework\Setup\Patch\DataPatchInterface` | `ModuleDataSetupInterface $moduleDataSetup` + any DI | EAV attributes, seed rows, config values, data migrations |
| Schema patch | `Setup/Patch/Schema/<Name>.php` | `Magento\Framework\Setup\Patch\SchemaPatchInterface` | `SchemaSetupInterface $schemaSetup` + any DI | DDL that `db_schema.xml` cannot express (data-dependent DDL, triggers, one-off conversions) — rare |

The class name is the identity: `Acme\Catalog\Setup\Patch\Data\AddBrandAttribute` is read from the file name (the reader globs `Setup/Patch/Data/*.php`, no subdirectories), so file name and class name must match and the namespace must be `<Vendor>\<Module>\Setup\Patch\Data`. Schema is *not* a patch's job: tables and columns go in `db_schema.xml` (A6); `InstallData`/`UpgradeData`/`InstallSchema`/`UpgradeSchema` are legacy and must not be added to new code.

Optional interfaces:

- `PatchRevertableInterface` — adds `revert()`, run on `module:uninstall` (below).
- `PatchVersionInterface` — `public static function getVersion()`; legacy bridge for modules converted from upgrade scripts (below).
- `NonTransactionableInterface` — marker; the applier then does not wrap `apply()` in a transaction. Use it when the patch runs DDL or its own transactions.

`DataPatchInterface` and `SchemaPatchInterface` both extend `PatchInterface`: `apply()`, `getAliases()`, and `public static function getDependencies()`.

## Lifecycle on `setup:upgrade`

1. Declarative schema for all modules (`db-schema.md`).
2. For each module in load order (`<sequence>`): schema patches not yet in `patch_list`.
3. For each module in load order: data patches not yet in `patch_list`.
4. `app:config:import`. Caches are cleaned before the data patches run, not after them — finish with `bin/magento cache:clean`.

Per patch: skip if its class name (or one of its `getAliases()`) is in `patch_list`; otherwise instantiate through the object manager, call `apply()`, insert the class name into `patch_list` (`patch_name` column) and insert each alias too. A data patch runs inside a transaction on the setup connection unless it is `NonTransactionableInterface`; an exception rolls it back, aborts `setup:upgrade` with *"Unable to apply data patch Acme\Catalog\Setup\Patch\Data\X for module Acme_Catalog. Original exception message: ..."*, and the patch stays unapplied — nothing later runs until it is fixed. Schema patches are not wrapped (DDL auto-commits) but abort the run the same way.

Because the record is the class name, **renaming or moving a patch makes it new** — list the old name in `getAliases()` (below). Deleting the file does nothing to the database.

## A data patch

Seed rows for the `acme_brand` table from `db-schema.md`, idempotently, with a revert:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Setup\Patch\Data;

use Magento\Framework\Setup\ModuleDataSetupInterface;
use Magento\Framework\Setup\Patch\DataPatchInterface;
use Magento\Framework\Setup\Patch\PatchRevertableInterface;

class SeedDefaultBrands implements DataPatchInterface, PatchRevertableInterface
{
    private const TABLE = 'acme_brand';
    private const BRANDS = ['Acme', 'Generic'];

    public function __construct(
        private readonly ModuleDataSetupInterface $moduleDataSetup
    ) {
    }

    public function apply(): self
    {
        $connection = $this->moduleDataSetup->getConnection();
        $connection->startSetup();
        $rows = array_map(static fn (string $name): array => ['name' => $name], self::BRANDS);
        $connection->insertOnDuplicate($this->moduleDataSetup->getTable(self::TABLE), $rows, ['name']);
        $connection->endSetup();
        return $this;
    }

    public function revert(): void
    {
        $connection = $this->moduleDataSetup->getConnection();
        $connection->startSetup();
        $connection->delete($this->moduleDataSetup->getTable(self::TABLE), ['name IN (?)' => self::BRANDS]);
        $connection->endSetup();
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

- The constructor parameter must be named `$moduleDataSetup`: the applier creates the patch with `['moduleDataSetup' => <setup bound to this run>]`, and DI matches by name. Any other injectable service can be added (A1/A9): `EavSetupFactory`, `CustomerSetupFactory`, a repository, `WriterInterface` for config, `Psr\Log\LoggerInterface`.
- `getTable('acme_brand')` resolves the table prefix; `getConnection()` is the setup adapter with bound-parameter methods — `insertOnDuplicate`, `insertMultiple`, `update($table, $bind, ['id = ?' => $id])`, `delete`, `fetchAll($select, $bind)` (A5). `startSetup()`/`endSetup()` switch foreign-key checks and `SQL_MODE` off and back on; keep them for anything that touches keys.
- Idempotent by construction (`insertOnDuplicate`, `addAttribute` which updates an existing attribute, `WriterInterface::save` which upserts): a patch that was applied by hand, or re-run after its `patch_list` row was deleted, must not duplicate anything. Treat `apply()` like a cron job (P6 spirit).
- Repositories are fine inside a patch when the entity is yours or the service is area-independent (`ProductRepositoryInterface::save` works; anything that needs a store view context needs `Magento\Store\Model\App\Emulation` or an explicit store id). Prefer setup-level writes for bulk data — they do not fire plugins, observers or indexers, which is usually what you want at deploy time, and reindex afterwards.
- `apply()` may return `$this` or nothing; the interface declares no return type. `revert()` does the exact opposite of `apply()` and must be safe when nothing is there to remove.

## A schema patch

Only for DDL that declarative schema cannot express — e.g. a one-off data-dependent conversion. The setup object is `SchemaSetupInterface`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Setup\Patch\Schema;

use Magento\Framework\Setup\Patch\SchemaPatchInterface;
use Magento\Framework\Setup\SchemaSetupInterface;

class DropLegacyBrandCache implements SchemaPatchInterface
{
    public function __construct(
        private readonly SchemaSetupInterface $schemaSetup
    ) {
    }

    public function apply(): self
    {
        $this->schemaSetup->startSetup();
        $connection = $this->schemaSetup->getConnection();
        $table = $this->schemaSetup->getTable('acme_brand_cache_legacy');
        if ($connection->isTableExists($table)) {
            $connection->dropTable($table);
        }
        $this->schemaSetup->endSetup();
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

The parameter name is `$schemaSetup` (the applier passes `['schemaSetup' => ...]`). Anything a schema patch creates is invisible to declarative schema — it will not be diffed, whitelisted or dropped for you — so keep them to clean-ups and conversions, never to tables your module reads.

## Dependencies, aliases and order

```php
public static function getDependencies(): array
{
    return [
        \Acme\Catalog\Setup\Patch\Data\AddBrandAttribute::class,
        \Magento\Catalog\Setup\Patch\Data\UpdateProductAttributes::class,
    ];
}

public function getAliases(): array
{
    return [\Acme\Catalog\Setup\Patch\Data\InstallBrands::class]; // former name of this patch
}
```

- Within one module, patches are read in file-name order (`glob` sorts), then reordered so that every dependency runs before the patch that names it. Do not rely on file names for ordering — declare the dependency.
- A dependency may be a patch of *any* module. It is registered into the current module's run and applied before your patch, even if its own module comes later in the load sequence (and is then skipped there as already applied). Declare the module in `module.xml` `<sequence>` too (A8) so the class exists.
- A dependency that is already in `patch_list` is skipped, along with its own chain. A cycle throws `LogicException("Cyclomatic dependency during patch installation")`.
- Across modules with no declared dependencies, order is the module load order: your patches run after those of every module in your `<sequence>`. Data patches of *all* modules run after schema patches of *all* modules, so a data patch can rely on every module's declarative tables.
- `getAliases()` returns former class names. When the applier finds an alias in `patch_list` it records the new name and skips `apply()`; when it applies the patch it records the aliases as well. Use it on every rename; never on a genuinely different patch.

## Reverting

`revert()` runs only from `bin/magento module:uninstall`, in reverse dependency order, each inside a transaction, removing the class from `patch_list`:

```bash
bin/magento module:uninstall --remove-data Acme_Catalog   # Composer-installed module: revert patches, run Setup/Uninstall.php, remove the package
bin/magento module:uninstall --non-composer Acme_Catalog  # app/code module: revert patches only, nothing else
```

Without `--remove-data` the Composer variant asks (or, non-interactively, proceeds) only when some module has an `Uninstall` class. `setup:upgrade`, `module:disable` and `cache:flush` never call `revert()`. Declarative tables are not touched by `revert()` either — a disabled module's whitelisted tables are dropped by the next `setup:upgrade` (`db-schema.md`), and a Composer uninstall with `--remove-data` runs `Setup/Uninstall.php` (`Magento\Framework\Setup\UninstallInterface`) for anything else.

## Re-running a patch in development

```sql
DELETE FROM patch_list WHERE patch_name = 'Acme\\Catalog\\Setup\\Patch\\Data\\AddBrandAttribute';
```

then `bin/magento setup:upgrade`. The name is stored without a leading backslash. Since `apply()` is idempotent (above), this is safe; if it is not, fix the patch rather than the database. Patches are not the place for environment-specific data (admin users, API keys, sample content) — that is `setup:install` options, `config:set`, or fixtures.

## Legacy `PatchVersionInterface`

Only for a module that shipped `InstallData`/`UpgradeData` scripts before 2.3 and was converted. `getVersion()` returns the module version whose script already made this change; the applier skips the patch when the module's recorded data version in `setup_module` is greater than or equal to it, and records it as applied. New modules have no `setup_version` and never implement this.

## Generating a stub

```bash
bin/magento setup:db-declaration:generate-patch Acme_Catalog AddBrandAttribute --type=data --revertable=true
```

writes `Setup/Patch/Data/AddBrandAttribute.php` (`--type=schema` for a schema patch) with `declare(strict_types=1)`, the constructor, `apply()`, `revert()` when requested, and empty `getAliases()`/`getDependencies()`. It still uses an untyped property; add the types (Q2).

## Checklist

- Class in `Setup/Patch/Data` (or `Schema`), name = file name, implements the interface, static `getDependencies()`.
- `apply()` is idempotent, wrapped in `startSetup()`/`endSetup()` when it touches keys, throws on failure (never swallow exceptions — a caught exception marks the patch applied with nothing done).
- Attribute or config patches depend on the core patch that defines what they modify when order matters.
- `revert()` for anything a merchant could reasonably uninstall (attributes, seed rows); `getAliases()` on rename.
- After `setup:upgrade`: `bin/magento cache:clean`, and `indexer:reindex` for anything the patch wrote around (products, attributes, prices).

## Sources

- https://developer.adobe.com/commerce/php/development/components/declarative-schema/patches — Develop data and schema patches (paths, interfaces, `patch_list`, run once, `getDependencies()` in any module, `PatchRevertableInterface` + `module:uninstall` with and without `--non-composer`, `PatchVersionInterface` skip rule, declarative schema runs first)
- https://developer.adobe.com/commerce/php/development/components/declarative-schema/migration-scripts — Migrate install/upgrade scripts (`setup:db-declaration:generate-patch [--revertable] [--type] <module> <patch>`, "once you start with data patches, you cannot continue to use upgrade scripts", `PatchVersionInterface` for converted modules)
- https://developer.adobe.com/commerce/php/tutorials/admin/custom-text-field-attribute — Add a custom text field attribute (data patch anatomy: `$moduleDataSetup`, `startSetup()`/`endSetup()` "turns off foreign key checks and sets the SQL mode", `getDependencies()`/`getAliases()`)
- https://developer.adobe.com/commerce/php/development/components/attributes — EAV and extension attributes (the note that patch constructors take `EavSetupFactory`, not `EavSetup`)
