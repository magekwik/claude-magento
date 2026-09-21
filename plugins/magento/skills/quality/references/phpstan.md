# PHPStan and PHPMD on Magento 2 code

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magekwik-magento:conventions` (A9 factories and proxies, Q2 strict types, Q3 tests).

Core ships PHPStan `^1.x` (`phpstan/phpstan ~1.2` on 2.4.4, `^1.6.8` on 2.4.5, `^1.9` from 2.4.6; 1.12.x resolves on 2.4.9) and runs it at **level 1** over changed files in its own static suite (`dev/tests/static/testsuite/Magento/Test/Php/LiveCodeTest.php::testPhpStan`, via `Magento\TestFramework\CodingStandard\Tool\PhpStan`: `--level 1 --no-progress --error-format=filtered --memory-limit=4G --configuration dev/tests/static/testsuite/Magento/Test/Php/_files/phpstan/phpstan.neon`). That config, the custom error formatter and the reflection extension live under `dev/tests/static/`, which `magento/magento2-base` deploys into every Composer project, so everything below works in a `magento/project-community-edition` checkout without cloning the framework repo.

## How PHPStan sees a Magento project

- **Autoload**: PHPStan loads `vendor/autoload.php`. The root `composer.json` maps `psr-0` `""` to `app/code/` and `generated/code/`, so `Acme\Catalog\…` classes and every *already generated* factory, proxy and interceptor resolve without configuration.
- **Generated classes**: `XxxFactory`, `Xxx\Proxy`, `Xxx\Interceptor` and `XxxExtension`/`XxxExtensionInterface` do not exist as files until the object manager generates them (developer mode, on first use) or `bin/magento setup:di:compile` writes them all. A bare `phpstan.neon` therefore reports `Parameter $f … has invalid type Acme\Catalog\Model\BrandFactory` / `Property … has unknown class … as its type` for every factory the code base has not used yet.
- **The core config fixes that for factories**: its `bootstrapFiles` include `dev/tests/static/framework/Magento/PhpStan/autoload.php`, which registers `Magento\Framework\TestFramework\Unit\Autoloader\GeneratedClassesAutoloader` with a `FactoryGenerator`, an `ExtensionAttributesGenerator` and an `ExtensionAttributesInterfaceGenerator`. Any `…Factory` or extension-attributes class PHPStan asks for is generated on the fly into `dev/tests/static/tmp/generated/code/` (a temp directory, gitignored). Proxies and interceptors are **not** generated there — and never need to be: a proxy is declared in `di.xml` and never type-hinted (A9), and interceptors are never referenced from code. The unit-test bootstrap (`dev/tests/unit/framework/autoload.php`) does the same plus a `ProxyGenerator`.
- **`scanDirectories`** is for symbols PHPStan cannot reach through Composer: the core config lists the test-framework `testsuite` directories. Add `generated/code` only when the project's Composer autoload does not already cover it (it does in every stock 2.4 root `composer.json`); add `dev/tests/integration/framework` when analysing integration tests.
- **Magic getters/setters**: the config registers `Magento\PhpStan\Reflection\Php\DataObjectClassReflectionExtension`, which teaches PHPStan that `get*/set*/uns*/has*` exist on any `Magento\Framework\DataObject` subclass (and on `SessionManager`), so `$product->getSku()` on a model is not an "undefined method". Their return type is `mixed` — add `@var`/casts when a higher level complains.
- **`__()`** returns `Magento\Framework\Phrase`, not `string`: `(string) __('…')` where a string is required, and `Phrase` in `LocalizedException` constructors.

## Project `phpstan.neon`

Put this in the project root and analyse only your code:

```neon
includes:
    - dev/tests/static/testsuite/Magento/Test/Php/_files/phpstan/phpstan.neon

parameters:
    level: 1
    paths:
        - app/code/Acme
    excludePaths:
        analyse:
            - app/code/Acme/*/Test/*
    tmpDir: var/phpstan
    # only when setup:di:compile is impossible AND code type-hints generated proxies (fix the code instead — A9)
    ignoreErrors:
        - '#unknown class [A-Za-z0-9\\_]+\\Proxy#'
        - '#invalid type [A-Za-z0-9\\_]+\\Proxy#'
```

```bash
vendor/bin/phpstan analyse --memory-limit=2G                     # uses phpstan.neon from the cwd
vendor/bin/phpstan analyse --memory-limit=2G --level 5 app/code/Acme/Catalog/ViewModel   # CLI paths and level override the file
vendor/bin/phpstan analyse --memory-limit=2G --error-format=github                        # annotations in GitHub Actions; also table (default), raw, json, checkstyle, junit
```

What the included core file brings, and why you keep it instead of copying pieces: `%rootDir%` in it is PHPStan's own directory (`vendor/phpstan/phpstan`), so `%rootDir%/../../../` is the project root and every path resolves in a stock install; `excludePaths` for `_files`, `Fixtures`, `pub`, test temp dirs; the three `scanDirectories`; the five `bootstrapFiles` (static, integration, api-functional and setup-integration framework autoloaders plus the generator autoloader above); `ignoreErrors` for unused constructor parameters (Magento keeps them for backward compatibility), the non-repeatable fixture-attribute warnings, `TESTS_*` constants and `T_*` tokens defined at runtime; `checkExplicitMixedMissingReturn` / `checkPhpDocMissingReturn`; `reportUnmatchedIgnoredErrors: false`; the `DataObject` reflection extension; and the `filtered` error formatter (`Magento\PhpStan\Formatters\FilteredErrorFormatter`, autoloaded through the root `autoload-dev` entry `Magento\PhpStan\` → `dev/tests/static/framework/Magento/PhpStan/`), which honours `// phpstan:ignore "message"` line comments — use `--error-format=filtered` only if you rely on those; the standard `// @phpstan-ignore-next-line` comment (every 1.x) and `// @phpstan-ignore <identifier>` (1.11+, so 2.4.9's 1.12) work with every formatter.

The core file has no `level`, so a project config (or `--level`) must set one — PHPStan does not default to 0 when a config file is used. The core file sets no `paths` either; without `paths` in yours you must pass them on the command line.

Ignore patterns for generated classes when compiling is not an option (a CI job without a database cannot run `setup:di:compile`; the generator autoloader above already covers factories, so `*Factory` patterns are only needed with a config that does *not* include the core file):

```neon
    ignoreErrors:
        - '#unknown class [A-Za-z0-9\\_]+Factory#'
        - '#invalid type [A-Za-z0-9\\_]+Factory#'
        - '#unknown class [A-Za-z0-9\\_]+\\Proxy#'
        - '#invalid type [A-Za-z0-9\\_]+\\Proxy#'
```

Prefer generating over ignoring: `bin/magento setup:di:compile` (needs a working database and `app/etc/env.php`) fills `generated/code` with every factory, proxy and interceptor for every enabled module, after which nothing is unknown. Compiled code is disposable — `rm -rf generated/code generated/metadata` afterwards on a developer machine (`magekwik-magento:ops`).

## Levels

Level 0 checks unknown classes/functions/methods on `$this` and argument counts; **level 1** adds possibly undefined variables and unknown magic methods/properties on classes with `__call`/`__get` (the ceiling Magento's own suite enforces, and a safe floor for anything that extends `AbstractModel`, `Template`, `AbstractDb`, `AbstractCollection` or `DataObject`); level 2 checks unknown methods on every expression and validates PHPDoc; 3 return and property types; 4 dead code; 5 argument types; 6 missing type hints; 7 partially wrong union types; 8 calls on nullable types; 9 explicit `mixed`; 10 (PHPStan 2 only) implicit `mixed`. For classes you wrote with typed signatures and no `DataObject` magic — services, ViewModels implementing `ArgumentInterface`, plugins, observers, console commands, resolvers — run level 5 to 8; `getData('key')` and repository `get*` results are where `mixed`/nullable errors will cluster, and casting or a `@var` on the boundary (Q2) is the fix, not an ignore. `--level max` follows the highest level of the installed version; pin a number in CI.

## Baseline

Adopt PHPStan on an existing module by recording today's errors and failing only on new ones:

```bash
vendor/bin/phpstan analyse --memory-limit=2G --generate-baseline            # writes phpstan-baseline.neon (add --allow-empty-baseline if there are none)
vendor/bin/phpstan analyse --memory-limit=2G --generate-baseline phpstan-baseline.php   # PHP format, faster to load when it is large
```

Then add `- phpstan-baseline.neon` under `includes:` in `phpstan.neon` and commit both. The baseline is a list of `ignoreErrors` entries with `message`, `count` and `path`; fixing an old error makes its entry unmatched, which the core config silently tolerates (`reportUnmatchedIgnoredErrors: false`) — regenerate the baseline periodically so it shrinks. Never baseline a new module; never regenerate to make a red build green.

## CI

```yaml
- run: composer install --no-interaction --prefer-dist                 # dev deps: phpstan + dev/tests from magento2-base
- run: vendor/bin/phpstan analyse --memory-limit=2G --no-progress --error-format=github
```

No database is required for the run above. Analyse `app/code/Acme` (or the changed files: `git diff --name-only … -- 'app/code/Acme/**/*.php' | xargs vendor/bin/phpstan analyse …`), never `vendor/` or `app/code/Magento`; the core suite already does that upstream. Cache lives in `tmpDir` — keep it between runs (`actions/cache` on `var/phpstan`) and PHPStan re-analyses only changed files and their dependents.

## Common errors and what they mean

| PHPStan says | Cause | Fix |
|---|---|---|
| `Class Acme\Catalog\Model\BrandFactory not found` / `unknown class … as its type` | factory not generated and no generator autoloader (bare config) | include the core config; or `setup:di:compile`; or the `*Factory` ignore pattern as a last resort |
| `… has unknown class …\Proxy …` | a proxy type-hinted in a constructor | A9: type-hint the real class/interface and map the proxy in `di.xml` |
| `Call to an undefined method Magento\Catalog\Model\Product::getSomething()` | magic getter on a `DataObject` subclass **without** the core config's reflection extension | include the core config (`DataObjectClassReflectionExtension`) — or better, use the interface (`ProductInterface::getSku()`) or `getData('something')` |
| `Parameter #1 $message of class …LocalizedException constructor expects Magento\Framework\Phrase, string given` | `new LocalizedException('text')` | `new LocalizedException(__('text'))` |
| `Method … should return string but returns Magento\Framework\Phrase` | returning `__()` from a `: string` method | `(string) __('…')` |
| `Constructor of class … has an unused parameter` | kept for backward compatibility | ignored by the core config; in your own new class, remove the parameter |
| `Function setCustomErrorHandler not found` (or any `TESTS_*` constant) | analysing test bootstrap files | already ignored by the core config; add `dev/tests/*` to `excludePaths` in yours |
| `Attribute class Magento\TestFramework\Fixture\DataFixture is not repeatable` | repeated fixture attributes on 2.4.5+ tests | ignored by the core config |
| `Access to an undefined property …::$_scopeConfig` | protected property of a parent class only declared via `@var` in a DocBlock | declare the typed property in your class, or inject and keep your own private property |

## PHPMD

Core also runs PHP Mess Detector over changed files (`LiveCodeTest::testCodeMess`) with the ruleset `dev/tests/static/testsuite/Magento/Test/Php/_files/phpmd/ruleset.xml`: `codesize` (`CyclomaticComplexity`, `NPathComplexity`, `ExcessiveMethodLength`, `ExcessiveParameterList`, `ExcessivePublicCount`, `TooManyFields`, `ExcessiveClassComplexity` with `maximum` 100), every `unusedcode` rule (with Magento's own `UnusedFormalParameter`, which does not count the `$subject`/`$proceed`/`$result` parameters of `around*`/`after*` plugin methods), `design` (`NumberOfChildren`, `DepthOfInheritance` with `minimum` 8, `CouplingBetweenObjects`), `naming` (`ShortMethodName`, `ConstantNamingConventions`, `BooleanGetMethodName`) and two Magento rules from `dev/tests/static/framework/Magento/CodeMessDetector/`: `AllPurposeAction` (a controller implementing `ActionInterface` but none of the `Http*ActionInterface` request-method interfaces — S2) and `CookieAndSessionMisuse` ("Session and Cookies must be used only in HTML Presentation layer": a `SessionManagerInterface`/`CookieReaderInterface` dependency in anything that is not a controller, block, UI data provider or layout processor). The ruleset's `<php-includepath>` points at `dev/tests/static/framework`, so PHPMD finds those rule classes on its own; the rules that reflect on the analysed class need it autoloadable, which `app/code` is.

The PHPMD major changed with 2.4.8 and the CLI with it:

```bash
# 2.4.4–2.4.7 (phpmd/phpmd ^2.9 / ^2.12): positional arguments
vendor/bin/phpmd app/code/Acme text dev/tests/static/testsuite/Magento/Test/Php/_files/phpmd/ruleset.xml --suffixes php --exclude '*/Test/*'

# 2.4.8–2.4.9 (phpmd/phpmd 3.x): `analyze` subcommand, named options
vendor/bin/phpmd analyze app/code/Acme --format text --ruleset dev/tests/static/testsuite/Magento/Test/Php/_files/phpmd/ruleset.xml --exclude '*/Test/*' --no-progress
```

PHPMD 3 renamed `--ignore` to `--exclude`, `--minimumpriority` to `--minimum-priority`, `--reportfile` to `--reportfile-text|xml|json|…`, and auto-detects `phpmd.xml`/`phpmd.yml`/`phpmd.json`/`phpmd.php` in the working directory. Exit codes on both majors: `0` clean, `1` exception, `2` violations (`--ignore-violations-on-exit` forces 0), `3` files that could not be processed (added in PHPMD 2.10; every 2.4.4–2.4.9 lock resolves 2.11 or later). Formats: `text`, `xml`, `json`, `html`, `ansi`, `checkstyle`, `github`, `gitlab`, `sarif`, `baseline`. `--generate-baseline` writes `phpmd.baseline.xml` next to the ruleset; `--update-baseline` prunes it.

Suppress a single rule where the complexity is inherent (a big `switch` over order states, a constructor with many collaborators) with a DocBlock annotation on the class or method, naming the rule: `@SuppressWarnings(PHPMD.CyclomaticComplexity)`, `@SuppressWarnings(PHPMD.ExcessiveParameterList)`, `@SuppressWarnings(PHPMD.CouplingBetweenObjects)`; `@SuppressWarnings(PHPMD)` mutes everything and should not pass review. `--strict` reports suppressed violations anyway. When PHPMD flags a method, the answer is usually to extract a class (the plugin/observer/ViewModel it wanted to be), not to raise the threshold in the ruleset.

## Sources

- https://phpstan.org/config-reference — `includes`, `level` must be set when a config file is used, `paths` (CLI paths win), `excludePaths` `analyse`/`analyseAndScan`, `scanDirectories`, `bootstrapFiles` (executed by PHP), `ignoreErrors` and `reportUnmatchedIgnoredErrors`, `%rootDir%` = `vendor/phpstan/phpstan`, `%currentWorkingDirectory%`, `tmpDir`, `phpVersion`
- https://phpstan.org/user-guide/discovering-symbols — Composer autoloader as the default, `scanFiles`/`scanDirectories` for code outside Composer, `bootstrapFiles` for custom autoloaders
- https://phpstan.org/user-guide/rule-levels — what levels 0–10 add, `--level max`
- https://phpstan.org/user-guide/baseline — `--generate-baseline [file]`, `includes: - phpstan-baseline.neon`, the PHP-format baseline, workflow
- https://phpmd.org/documentation/index.html — PHPMD 2.x synopsis `phpmd <path> <format> <ruleset>`, formats, `--suffixes`, `--exclude`, `--minimumpriority`, `--strict`, `--ignore-violations-on-exit`, baseline options, exit codes 0/1/2/3, `@SuppressWarnings`
- Verified in a 2.4.9 install: `dev/tests/static/testsuite/Magento/Test/Php/_files/phpstan/phpstan.neon`, `dev/tests/static/framework/Magento/PhpStan/{autoload.php,Formatters/FilteredErrorFormatter.php,Reflection/Php/DataObjectClassReflectionExtension.php}`, `dev/tests/static/framework/Magento/TestFramework/CodingStandard/Tool/{PhpStan.php,CodeMessDetector.php}` (level 1, `filtered`, 4G; `--format text --ruleset`), `dev/tests/static/testsuite/Magento/Test/Php/_files/phpmd/ruleset.xml`, `dev/tests/static/framework/Magento/CodeMessDetector/Rule/Design/AllPurposeAction.php`, `vendor/phpmd/phpmd/UPGRADING.md` (PHPMD 3 CLI changes), `vendor/bin/phpmd analyze --help`, `phpmd/phpmd` `TextUI/Command.php` at tags 2.9.1/2.10.0/2.12.0 (`EXIT_ERROR = 3` from 2.10; the constant is `ERROR = 3` in 3.x — `src/TextUI/Command.php` in the installed 3.0.0) and the 2.4.4 `composer.lock` (PHPMD 2.11.1), `vendor/bin/phpstan --version` (1.12.x), root `composer.json` (`psr-0` for `app/code/` and `generated/code/`, `autoload-dev` `Magento\PhpStan\`); `magento/magento2` root `composer.json` at tags 2.4.4–2.4.9 (`phpstan/phpstan`, `phpmd/phpmd` constraints); PHPStan runs with and without the core config against a class referencing an ungenerated `…Factory` and a `…\Proxy` reproduced the errors and the generated `dev/tests/static/tmp/generated/code/…Factory.php`
