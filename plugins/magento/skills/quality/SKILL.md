---
name: quality
description: Magento 2 code quality tooling — PHPCS with the Magento2 coding standard, PHPStan, PHPMD, unit tests with the Magento ObjectManager test helper, integration tests and MFTF basics. Use when setting up, running or fixing static analysis and tests for Magento Open Source 2.4 code.
---

# Magento 2 code quality

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).*

Rules: see `magento:conventions` Q1–Q6 (and A1, A9, S3 where a sniff enforces them). This skill cites them by ID and does not restate them.

## When to use

- Setting up PHPCS with the official `Magento2` standard for a project or a single module, reading its report, fixing or justifying what it finds, preparing a Marketplace (EQP) submission.
- Running PHPStan or PHPMD on `app/code/<Vendor>` without drowning in core noise.
- Writing or running unit tests (`Test/Unit`), integration tests (`Test/Integration`), API functional tests (`Test/Api`) or deciding whether MFTF is worth it.
- Wiring any of the above into CI on changed paths only.

## When not to

- Writing the module, schema, API or theme code itself → `magento:module`, `magento:data`, `magento:api`, `magento:frontend-luma`, `magento:frontend-hyva`.
- Running `bin/magento`, deploying, caches, upgrades, Xdebug → `magento:ops`.
- The rule *behind* a finding (why no `ObjectManager`, why escape output) → `magento:conventions`; this skill only tells you which tool reports it and how to run the tool.

## Decision guide

| Need | Use | Reference |
|---|---|---|
| Style and coding-standard violations, unescaped output, raw SQL, `ObjectManager` in templates, legacy install scripts | PHPCS with the `Magento2` standard (`vendor/bin/phpcs --standard=Magento2 <paths>`) | `phpcs.md` |
| Type errors, unknown classes/methods, wrong argument counts, undefined variables | PHPStan — level 1 is the floor Magento's own suite uses for framework-coupled code; 5–8 for pure classes (services, ViewModels, value objects) | `phpstan.md` |
| Cyclomatic complexity, unused code, too many fields/parameters, coupling | PHPMD with the core ruleset `dev/tests/static/testsuite/Magento/Test/Php/_files/phpmd/ruleset.xml` | `phpstan.md` (PHPMD section) |
| A class with logic (ViewModel, service, plugin method, observer, helper) | Unit test in `Test/Unit`, SUT built by `Magento\Framework\TestFramework\Unit\Helper\ObjectManager` | `testing.md` |
| Anything touching the database, DI wiring, `di.xml` plugins/preferences, layout, config values, events end to end | Integration test in `Test/Integration` against a dedicated test database | `testing.md` |
| REST/GraphQL endpoint behaviour over HTTP | API functional test in `Test/Api` (`dev/tests/api-functional`) | `testing.md` |
| A user flow through the browser (admin form, checkout) | MFTF (`Test/Mftf`, XML) — mention it, run it only when the flow really needs a browser | `testing.md` |
| Marketplace submission | `phpcs --standard=Magento2 --extensions=php,phtml --error-severity=10 --ignore-annotations …` — errors reject, warnings do not | `phpcs.md` |

Tool majors move with the release (PHPUnit 9 → 10 → 12 and PHPMD 2 → 3 across 2.4.4–2.4.9; the coding standard and its installer are in core `require-dev` throughout) — the per-release table is in `testing.md` (PHPUnit, MFTF) and `phpstan.md` (PHPStan, PHPMD).

## Rules that bite

1. **Q1** — `magento/magento-coding-standard` is a dev dependency (`composer require --dev magento/magento-coding-standard`; the `magento/magento2` root `composer.json` already lists it on every 2.4.4–2.4.9 release, so a project created from `magento/project-community-edition` usually only needs `composer install` *without* `--no-dev`). The standard is registered with PHPCS through `installed_paths`: the Composer plugin `dealerdirect/phpcodesniffer-composer-installer` (also in core `require-dev`) writes it on every install/update when `config.allow-plugins` permits it; otherwise run `vendor/bin/phpcs --config-set installed_paths ../../magento/magento-coding-standard/` once (path relative to `vendor/squizlabs/php_codesniffer/`) or add the README's `post-install-cmd`/`post-update-cmd` script. `vendor/bin/phpcs -i` must list `Magento2`.
2. **Q1** — Run PHPCS on the paths you changed (`app/code/Acme/Catalog`, or `git diff --name-only … | xargs`), not on all of `app/code`, in CI and before finishing; a `phpcs.xml.dist` in the project root makes a bare `vendor/bin/phpcs` do the right thing and inherits the standard's file extensions (`php,phtml,graphqls,less,html,xml,js`).
3. **Q1** — In the `Magento2` ruleset every severity-10 rule but one is an `error` (`Magento2.Html.HtmlClosingVoidTags` is a severity-10 warning) and everything below 10 is a `warning` (9 security/bug risks, 8 Magento design rules, 7 general code, 6 style, 5 PHPDoc). `--severity=10` shows only the blockers. The Marketplace runs `--error-severity=10 --ignore-annotations`: errors reject the extension, warnings do not, and `phpcs:ignore` comments are not honoured there.
4. `phpcbf` fixes only sniffs that declare a fix (`[x]` in the full report, `Fixable=1` in CSV): whitespace, `array()` → `[]`, `$this` → `$block` in templates and the like. Unescaped output (S3), raw SQL (A5), `ObjectManager` (A1), discouraged functions stay for a human. Re-run `phpcs` after `phpcbf`, and review the diff.
5. PHPCS exits 1 (issues) or 2 (issues, some fixable) as soon as a *warning* is found, not only on errors. Keep warnings failing the build (Q1: justify what you leave), or pass `-n` / `--runtime-set ignore_warnings_on_exit 1` deliberately in CI. With PHP_CodeSniffer ≥ 3.9 the Less sniffs print `DEPRECATED:` lines to stdout before any report; `-q` (in the reviewer command in `phpcs.md`) suppresses that progress/verbose output and nothing else.
6. PHPStan: `includes:` the core config `dev/tests/static/testsuite/Magento/Test/Php/_files/phpstan/phpstan.neon` (shipped into every Composer project by `magento/magento2-base`; its `%rootDir%` is `vendor/phpstan/phpstan`) instead of a bare `phpstan.neon`. Its `bootstrapFiles` register an autoloader that generates `XxxFactory` and extension-attribute classes on the fly into `dev/tests/static/tmp/generated/code`, so `setup:di:compile` is not required to see factories; `\Proxy` and `\Interceptor` classes are *not* generated — never type-hint them (A9) and PHPStan never needs them. Core analyses at level 1 with `--memory-limit=4G`.
7. **Q3** — Unit tests run through Magento's bootstrap: `vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist app/code/Acme` (`app/code/*/*/Test/Unit` is already in the `Magento_Unit_Tests_App_Code` suite). Its `framework/autoload.php` generates factories, proxies and extension attributes into `dev/tests/unit/tmp` on demand; a hand-written root `phpunit.xml` bootstrapping only `vendor/autoload.php` fails on the first `XxxFactory` that `generated/code` does not contain yet.
8. **Q3** — `(new ObjectManager($this))->getObject(BrandList::class, ['scopeConfig' => $configMock])` instantiates the SUT with a `createMock()` double for every class- or interface-typed constructor parameter you do not pass by name; builtin-typed parameters (arrays, scalars) receive their declared default, or `null` when there is none — give array parameters a `= []` default or pass them explicitly. Mock interfaces (`ScopeConfigInterface`, `LoggerInterface`, `ProductRepositoryInterface`), not concrete classes; never mock the class under test; `setBackwardCompatibleProperty()` only when a private property has no constructor path.
9. **Q3** — PHPUnit major matters for a skeleton: data-provider methods are `public static` (deprecated otherwise in 10, removed in 11); doc-comment metadata (`@dataProvider`, `@covers`) is removed in PHPUnit 12 (2.4.9) — use `#[DataProvider('cases')]` from `PHPUnit\Framework\Attributes` on 2.4.8+, annotations only on 2.4.4–2.4.7; `getMockForAbstractClass()`/`getMockForTrait()` are gone and `assertContainsOnly()` is deprecated in 12. `setUp(): void` and `TestCase` from `PHPUnit\Framework` are the same on all of them.
10. **Q3** — Integration tests need `dev/tests/integration/etc/install-config-mysql.php` (copy the `.dist`) pointing at a **dedicated** database plus the search engine from the same file — the framework reinstalls Magento into it on every run while `TESTS_CLEANUP` is `enabled`. `app/code/*/*/Test/Integration` is in the default suite; run one directory at a time (`vendor/bin/phpunit -c dev/tests/integration/phpunit.xml.dist app/code/Acme/Catalog/Test/Integration`). `@magentoDbIsolation`, `@magentoAppArea`, `@magentoDataFixture`, `@magentoConfigFixture` doc-comment annotations work on every release including 2.4.9 (Magento parses them itself; 1080 core test files still use them in 2.4.9); the attribute forms `#[DbIsolation]`, `#[AppArea]`, `#[DataFixture]`, `#[Config]` from `Magento\TestFramework\Fixture` exist from 2.4.5 and are what Adobe's docs recommend for new tests. DB isolation is off by default unless a data fixture is declared.

## Minimal correct example

Set a project up for PHPCS on `app/code/Acme`, then add a unit test skeleton for `Acme\Catalog\Model\BrandList::getNames(): array`.

```bash
composer require --dev magento/magento-coding-standard      # harmless when the 2.4.x root composer.json already lists it
vendor/bin/phpcs -i                                          # must list Magento2 — see rule 1 if it does not
vendor/bin/phpcs --standard=Magento2 app/code/Acme           # full report; add --severity=10 for Marketplace blockers only
vendor/bin/phpcbf --standard=Magento2 app/code/Acme          # only for the [x] fixable lines, then re-run phpcs
vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist app/code/Acme/Catalog/Test/Unit
```

`phpcs.xml.dist` in the project root (a bare `vendor/bin/phpcs` then checks `app/code/Acme` with the standard):

```xml
<?xml version="1.0"?>
<ruleset name="Acme">
    <description>Project rules: the Magento2 standard on our own code.</description>
    <rule ref="Magento2"/>
    <file>app/code/Acme</file>
    <exclude-pattern>*/Test/*</exclude-pattern>
    <arg name="basepath" value="."/>
    <arg name="colors"/>
    <arg value="sp"/>
</ruleset>
```

`app/code/Acme/Catalog/Test/Unit/Model/BrandListTest.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Test\Unit\Model;

use Acme\Catalog\Model\BrandList;
use Magento\Framework\TestFramework\Unit\Helper\ObjectManager;
use PHPUnit\Framework\TestCase;

class BrandListTest extends TestCase
{
    private BrandList $brandList;

    protected function setUp(): void
    {
        $this->brandList = (new ObjectManager($this))->getObject(BrandList::class);
    }

    public function testGetNamesReturnsNonEmptyList(): void
    {
        self::assertNotEmpty($this->brandList->getNames());
    }
}
```

Why this shape: `Test/Unit/Model/BrandListTest.php` mirrors `Model/BrandList.php`, which the unit suite's `<directory>` globs key on; `declare(strict_types=1)` and the typed property satisfy Q2; the `ObjectManager` helper (Q3) keeps building `BrandList` as its constructor grows — pass `['scopeConfig' => $this->createMock(ScopeConfigInterface::class)]` and set expectations on the mock instead of rewriting `setUp()`. No `@dataProvider`, no `getMockForAbstractClass`: it runs unchanged on PHPUnit 9, 10 and 12. The standard passes on everything above with exit 0; sniffing tests too reports one severity-5 warning (`Magento2.Commenting.ClassPropertyPHPDocFormatting.Missing`), which a `/** @var BrandList */` DocBlock clears.

## Routing table

| For | Read |
|---|---|
| Installing and registering the standard, `phpcs.xml.dist`, severity bands and every sniff family, reports (`full`, `summary`, `csv`, `json`, `source`), exit codes, `phpcbf`, suppressions, Marketplace EQP command, CI snippet, the exact command the review agent runs | `references/phpcs.md` |
| PHPStan on `app/code/<Vendor>`: autoload and generated code, the core `phpstan.neon` as base, levels, `scanDirectories`, `ignoreErrors` for `*Factory`/`*\Proxy`, baselines, CI; PHPMD 2 vs 3 syntax with the core ruleset and `@SuppressWarnings` | `references/phpstan.md` |
| Unit tests (bootstrap, `ObjectManager` helper, mocking `ScopeConfigInterface`, plugins, observers, data providers per PHPUnit major), integration tests (setup, DB, `Bootstrap::getObjectManager()`, fixtures as annotations and attributes, `@magentoAppArea`, `@magentoConfigFixture`), API functional tests, MFTF | `references/testing.md` |
