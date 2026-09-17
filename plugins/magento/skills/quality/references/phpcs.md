# PHPCS with the Magento2 coding standard

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (Q1 run the standard, A1 no ObjectManager, A5 no raw SQL, A6 declarative schema, A9 DI, S3 escaping, S5 insecure functions, L2 `$block`).

The standard is the Composer package `magento/magento-coding-standard` (`type: phpcodesniffer-standard`, latest tag 40 at the time of writing, requires `squizlabs/php_codesniffer ^3.10.2`, `phpcsstandards/phpcsutils` and `magento/php-compatibility-fork`). It installs four PHPCS standards: `Magento2` (the one you use), `Magento2Framework` (copyright/licence headers for core), `PHPCompatibility` and `PHPCSUtils`. `Magento2` contains 308 sniffs: 85 of its own under the `Magento2.*` prefix, 65 borrowed from Generic/PEAR/PSR1/PSR2/PSR12/Squiz, and 158 `PHPCompatibility` sniffs (its `testVersion` is set to `8.1-8.2` inside the ruleset).

## Install and register

```bash
composer require --dev magento/magento-coding-standard
vendor/bin/phpcs -i     # "... Magento2, Magento2Framework, PHPCompatibility and PHPCSUtils"
```

The root `composer.json` of `magento/magento2` lists `magento/magento-coding-standard` **and** `dealerdirect/phpcodesniffer-composer-installer` in `require-dev` on every release from 2.4.4 to 2.4.9, and allows the installer plugin in `config.allow-plugins`; a project created from `magento/project-community-edition` inherits that, so `composer install` (no `--no-dev`) is usually all it takes. `composer require --dev` is harmless when the package is already there.

PHPCS only knows a standard that is listed in its `installed_paths` config (`vendor/squizlabs/php_codesniffer/CodeSniffer.conf`). Three ways to get it there, in order of preference:

1. **The Composer plugin** — `dealerdirect/phpcodesniffer-composer-installer` rewrites `installed_paths` after every `composer install`/`update` with every `phpcodesniffer-standard` package it finds (`phpcsstandards/phpcsutils`, required by the standard, requires the plugin too, so it is present even in a project that never listed it). It only runs when `config.allow-plugins` contains `"dealerdirect/phpcodesniffer-composer-installer": true` — Composer 2.2+ asks interactively otherwise. `vendor/bin/phpcs --config-show` then prints `installed_paths: ../../magento/magento-coding-standard,../../magento/php-compatibility-fork,../../phpcsstandards/phpcsutils`.
2. **One manual command** — `vendor/bin/phpcs --config-set installed_paths ../../magento/magento-coding-standard/` (relative to `vendor/squizlabs/php_codesniffer/`). Note that the plugin, when allowed, overwrites this on the next install.
3. **Composer scripts** — what the package README recommends "due to security" (the plugin is not allowed by default):

```json
"scripts": {
    "post-install-cmd": ["([ $COMPOSER_DEV_MODE -eq 0 ] || vendor/bin/phpcs --config-set installed_paths ../../magento/magento-coding-standard/)"],
    "post-update-cmd":  ["([ $COMPOSER_DEV_MODE -eq 0 ] || vendor/bin/phpcs --config-set installed_paths ../../magento/magento-coding-standard/)"]
}
```

## Run

The review baseline (Q1) and the command the `magento:code-reviewer` agent executes:

```bash
vendor/bin/phpcs -q --standard=Magento2 --report=csv <paths>
```

Human-readable variant: `vendor/bin/phpcs -q --standard=Magento2 --report=full <paths>` (add `-s` to print the sniff code under each message, `--basepath=.` to shorten paths, `--colors`; drop `-q` and add `-p` for a progress line). `<paths>` are files or directories — `app/code/Acme/Catalog`, a list of changed files, or nothing at all when a `phpcs.xml.dist` names `<file>` entries.

Useful options:

| Option | Effect |
|---|---|
| `--severity=10` | show only severity-10 messages (every one an error except `Magento2.Html.HtmlClosingVoidTags`, a severity-10 warning); `--error-severity=N` / `--warning-severity=N` set the thresholds separately (default 5); `-n` = `--warning-severity=0`, which also removes warnings from the exit code |
| `--report=summary` | per-file error/warning counts; `--report=source` counts per sniff (what to fix first); `--report=json`, `--report=checkstyle`, `--report=junit` for CI; `--report-file=path` writes it instead of printing |
| `--extensions=php,phtml` | override the standard's file list (`php,phtml,graphqls,less,html,xml,js`); `--ignore=*/Test/*,*/generated/*` skips paths; `--exclude=Magento2.Annotation.MethodArguments` disables sniffs; `--sniffs=…` runs only the listed ones |
| `-q` | why it is in the command above: PHP_CodeSniffer ≥ 3.9 prints `DEPRECATED: Scanning CSS/JS files is deprecated …` lines for every `Magento2.Less.*` sniff to stdout *before* the CSV header; `-q` suppresses only that progress/verbose output (reports and exit code are unchanged) |
| `--parallel=4`, `--cache` | speed on large trees |
| `--runtime-set ignore_warnings_on_exit 1` | exit 0 when only warnings remain (see exit codes) |

Exit codes (PHP_CodeSniffer 3.x): `0` nothing found (or everything found is ignored on exit), `1` errors and/or warnings found, none fixable, `2` issues found and some are fixable by `phpcbf`. Warnings count — a file with one severity-5 DocBlock warning fails a plain `phpcs` in CI.

CSV columns: `File,Line,Column,Type,Message,Source,Severity,Fixable`, one row per message, `Type` is `error` or `warning`, `Source` is the full sniff code (e.g. `Magento2.Security.XssTemplate.FoundUnescaped`), `Fixable` is `1` when `phpcbf` can fix it. The header line is the first line of output once `-q` is set.

## `phpcs.xml.dist`

PHPCS looks for `.phpcs.xml`, `phpcs.xml`, `.phpcs.xml.dist`, `phpcs.xml.dist` in the current directory and its parents when `--standard` is not given, so the file makes `vendor/bin/phpcs` work with no arguments and pins the same defaults for everyone and CI:

```xml
<?xml version="1.0"?>
<ruleset name="Acme">
    <description>Magento2 standard on our own code.</description>
    <rule ref="Magento2">
        <!-- drop a sniff everywhere (only in a ruleset that is not submitted to the Marketplace) -->
        <exclude name="Magento2.Annotation.MethodArguments"/>
    </rule>
    <!-- silence one sniff for some paths only -->
    <rule ref="Magento2.Templates.ThisInTemplate">
        <exclude-pattern>*/view/frontend/templates/legacy/*</exclude-pattern>
    </rule>
    <file>app/code/Acme</file>
    <file>app/design/frontend/Acme</file>
    <exclude-pattern>*/Test/*</exclude-pattern>
    <exclude-pattern>*/web/js/lib/*</exclude-pattern>
    <arg name="basepath" value="."/>
    <arg name="parallel" value="4"/>
    <arg value="sp"/>
</ruleset>
```

`<rule ref="Magento2">` inherits everything the standard's own `ruleset.xml` declares, including its file list `<arg name="extensions" value="php,phtml,graphqls/GraphQL,less/CSS,html/PHP,xml,js/PHP"/>` (the suffix after `/` is the tokenizer — do not redeclare the list without it, or `.less` files are tokenised as PHP) and its `*.min.js` exclusion. Paths in `<file>` and `<arg name="basepath">` are relative to the ruleset file; command-line paths override `<file>`; `<arg value="sp"/>` is `-s -p`. Do not change severities or types of `Magento2.*` rules in a ruleset that will be submitted to the Marketplace — the Marketplace runs the unmodified standard.

## Severity bands

Every rule in the `Magento2` ruleset carries an explicit `<severity>` and `<type>`; the bands are the standard's own comments:

| Severity | Type | Band (examples) |
|---|---|---|
| 10 | **error** (one exception: `Magento2.Html.HtmlClosingVoidTags` is a severity-10 *warning*) | "Critical code issues": `Generic.PHP.Syntax`, `Generic.PHP.NoSilencedErrors`, `Magento2.Classes.DiscouragedDependencies` (A9 — excluded under `*/Test/*`), `Magento2.Legacy.InstallUpgrade` (A6), `Magento2.Legacy.MageEntity`, `Magento2.Legacy.AbstractBlock`, `Magento2.Legacy.RestrictedCode`, `Magento2.Security.IncludeFile`, `Magento2.Security.InsecureFunction` (S5), `Magento2.Security.LanguageConstruct`, `Magento2.Security.Superglobal.SuperglobalUsageError`, `Magento2.Security.XssTemplate.FoundUnescaped` (S3), `Magento2.Strings.ExecutableRegEx`, `Magento2.PHP.FinalImplementation`, `Magento2.PHP.Goto`, `Magento2.PHP.ReturnValueCheck`, `Magento2.PHP.AutogeneratedClassNotInConstructor`, `Magento2.Html.HtmlSelfClosingTags`, `PSR1.Classes.ClassDeclaration`, `PSR2.Files.ClosingTag`, `Squiz.PHP.Eval`, `PHPCompatibility.FunctionUse.RemovedFunctions` |
| 9 | warning | "Possible security and issues that may cause bugs": `Generic.Files.ByteOrderMark`, `Magento2.Security.Superglobal.SuperglobalUsageWarning`, the other `Magento2.Security.XssTemplate` codes, `Magento2.SQL.RawQuery` (A5), `Squiz.PHP.NonExecutableCode`, `Magento2.Html.HtmlBinding` |
| 8 | warning | "Magento specific code issues and design violations": `Magento2.Classes.AbstractApi`, `Magento2.Exceptions.DirectThrow`, `ThrowCatch`, `TryProcessSystemResources`, `Magento2.Functions.DiscouragedFunction`, `StaticFunction`, `Magento2.Namespaces.ImportsFromTestNamespace`, `Magento2.NamingConvention.InterfaceName`, `Magento2.PHP.ShortEchoSyntax`, `Magento2.Templates.ThisInTemplate` (L2), `Magento2.Templates.ObjectManager` (A1, `.phtml` only), `Magento2.Translation.ConstantUsage`, `Magento2.Methods.DeprecatedModelMethod`, `Magento2.Legacy.ModuleXML`, `DiConfig`, `WidgetXML`, `ObsoleteAcl`, `ObsoleteMenu`, `ObsoleteSystemConfiguration`, `PhtmlTemplate`, `ObsoleteConnection`, `Magento2.Html.HtmlDirective` |
| 7 | warning | "General code issues": `Generic.Arrays.DisallowLongArraySyntax`, `Generic.Metrics.NestingLevel`, `Generic.CodeAnalysis.*`, `Magento2.CodeAnalysis.EmptyBlock`, `Magento2.PHP.LiteralNamespaces`, `Magento2.PHP.Var`, `Magento2.PHP.ArrayAutovivification`, `Magento2.Performance.ForeachArrayMerge`, `Magento2.Strings.StringConcat`, `Magento2.Functions.FunctionsDeprecatedWithoutArgument`, `Squiz.Functions.GlobalFunction`, `Squiz.PHP.GlobalKeyword`, `Squiz.Scope.MemberVarScope` |
| 6 | warning | "Code style issues": PSR-2/PSR-12 layout sniffs, `Generic.Files.LineLength` (`lineLimit` 120, no absolute limit), `Generic.WhiteSpace.ScopeIndent`, `Magento2.Whitespace.MultipleEmptyLines`, `Magento2.GraphQL.*` naming, `Magento2.Less.*`, `Squiz.CSS.NamedColours` |
| 5 | warning | "PHPDoc formatting and commenting issues": `Magento2.Commenting.ClassAndInterfacePHPDocFormatting`, `ClassPropertyPHPDocFormatting`, `ConstantsPHPDocFormatting`, `Magento2.Annotation.*` (method DocBlocks and `@param` lines), `Squiz.Commenting.DocCommentAlignment`, `Squiz.PHP.CommentedOutCode` |

Consequences: `--severity=10` shows the error set plus the one severity-10 warning (`Magento2.Html.HtmlClosingVoidTags`); the default threshold (5) shows everything; there is no severity below 5 except a handful of codes disabled with `<severity>0</severity>`.

## Sniff families

The `Magento2.*` sniffs, by directory under `Magento2/Sniffs/` in the package (rule ID in parentheses where one applies):

| Family | Sniffs | Catches |
|---|---|---|
| `Annotation` | `MethodAnnotationStructure`, `MethodArguments` | method DocBlock present and well-formed, `@param` names/types match the signature |
| `Classes` | `AbstractApi`, `DiscouragedDependencies` | `@api` on an abstract class ("MUST NOT", Q4); a `\Proxy` or `\Interceptor` class requested explicitly in a constructor (A9) |
| `CodeAnalysis` | `EmptyBlock` | empty `if`/`catch`/function bodies |
| `Commenting` | `ClassAndInterfacePHPDocFormatting`, `ClassPropertyPHPDocFormatting`, `ConstantsPHPDocFormatting` | DocBlocks on classes, properties and constants |
| `Exceptions` | `DirectThrow`, `ThrowCatch`, `TryProcessSystemResources` | `throw new \Exception` instead of a `LocalizedException` subclass; throwing the exception you just caught; `stream_*`/`socket_*` calls outside a `try` block |
| `Functions` | `DiscouragedFunction`, `FunctionsDeprecatedWithoutArgument`, `StaticFunction` | 212 patterns — `file_get_contents`, `file_put_contents`, `fopen`, `mkdir` (use `Magento\Framework\Filesystem\DriverInterface`), `header`, `mail`, `sleep`, `var_dump`, `print_r`, `call_user_func` …; `static` methods |
| `GraphQL` | `ValidArgumentName`, `ValidEnumValue`, `ValidFieldName`, `ValidTopLevelFieldName`, `ValidTypeName` | schema naming in `.graphqls` |
| `Html` | `HtmlBinding`, `HtmlClosingVoidTags`, `HtmlCollapsibleAttribute`, `HtmlDirective`, `HtmlSelfClosingTags` | `.html` templates: Knockout `data-bind` variables, `{{if}}`/`{{depend}}`/`{{for}}`/`{{var}}` directive syntax, void and self-closing tags, collapsible attributes |
| `Legacy` | `AbstractBlock`, `ClassReferencesInConfigurationFiles`, `DiConfig`, `EmailTemplate`, `EscapeMethodsOnBlockClass` (S3, fixable), `InstallUpgrade` (A6), `Layout`, `MageEntity`, `ModuleXML`, `ObsoleteAcl`, `ObsoleteConfigNodes`, `ObsoleteConnection`, `ObsoleteMenu`, `ObsoleteSystemConfiguration`, `PhtmlTemplate`, `RestrictedCode`, `TableName`, `WidgetXML` | Magento 1 leftovers and obsolete XML nodes, `$block->escapeHtml()` and the other seven `escape*` methods on `$block` (rewritten to `$escaper`), install/upgrade scripts, `vendor/table`-style legacy table names in resource models, class names in XML that do not exist |
| `Less` | 18 sniffs (`AvoidId`, `BracesFormatting`, `ClassNaming`, `ColourDefinition`, `ImportantProperty`, `PropertiesSorting`, `Variables`, `ZeroUnits`, …) | Luma LESS style (L4) |
| `Methods` | `DeprecatedModelMethod` | `$model->getResource()->save()/load()/delete()` (A4) |
| `Namespaces` | `ImportsFromTestNamespace` | production code `use`-ing `*\Test\*` classes |
| `NamingConvention` | `InterfaceName`, `ReservedWords` | interfaces end in `Interface`; a class, interface, trait or namespace named `int`, `string`, `bool`, `float`, `void`, `iterable`, `resource`, `object`, `mixed`, `numeric`, `match`, `true`, `false`, `null` |
| `Performance` | `ForeachArrayMerge` | `array_merge()` inside a loop |
| `PHP` | `ArrayAutovivification`, `AutogeneratedClassNotInConstructor`, `FinalImplementation`, `Goto`, `LiteralNamespaces`, `ReturnValueCheck`, `ShortEchoSyntax`, `Var` | `final` (A2 — plugins cannot target it), `ObjectManager::getInstance()->get(XxxFactory::class)` for a generated class the constructor could inject, `strpos(...) == false` instead of `===`, `<?php echo` where `<?=` belongs, class names as string literals, `var` |
| `Security` | `IncludeFile`, `InsecureFunction`, `LanguageConstruct`, `Superglobal`, `XssTemplate` | `include`/`require` with a variable path; `eval`, `exec`, `system`, `shell_exec`, `passthru`, `proc_open`, `serialize`, `unserialize`, `md5`, `mt_rand`, `srand`, `assert`, `create_function` (S5); `exit`/`die`, backticks, direct output outside templates; `$_GET`/`$_POST`/`$_REQUEST`/`$_SESSION`/`$_ENV`/`$_FILES` (error) and `$_COOKIE`/`$_SERVER` (warning) (S6); unescaped output in `.phtml` (S3) |
| `SQL` | `RawQuery` | SQL keywords in string literals (A5) |
| `Strings` | `ExecutableRegEx`, `StringConcat` | `/e` modifier on `preg_replace`; `+` used to concatenate strings |
| `Templates` | `ObjectManager`, `ThisInTemplate` | `ObjectManager::getInstance()` in `.phtml` (A1 — the only ObjectManager sniff; PHP classes are not covered), `$this` in templates (L2, fixable) |
| `Translation` | `ConstantUsage` | constants inside `__()` |
| `Whitespace` | `MultipleEmptyLines` | blank-line runs |

JavaScript is not sniffed: the `js` extension is only tokenised for PHP, and JS style is checked with the ESLint configuration the same package ships (`eslint/eslint.config.mjs`, run as `npm run eslint -- <path>` from inside the package directory). XML files are checked by the `Legacy` sniffs listed above (`ModuleXML`, `DiConfig`, `Layout`, `ObsoleteAcl`, …).

## Reading a report

Fix in this order: every `error` (severity 10) first — they are what rejects a Marketplace submission and what the review agent reports as blocking; then severity 9 and 8 warnings (`RawQuery`, `DirectThrow`, `DiscouragedFunction`, `ThisInTemplate`), which usually map to a conventions rule; then style and DocBlock warnings, most of which `phpcbf` or a formatter handles. `--report=source` tells you which sniff produces the bulk; `--report=summary` which files. For a single sniff on a single file: `vendor/bin/phpcs --standard=Magento2 --sniffs=Magento2.Security.XssTemplate -s path/to/file.phtml`.

A message you disagree with is suppressed in code, next to the line, with the sniff code: `// phpcs:ignore Magento2.Functions.DiscouragedFunction` (single next line), `// phpcs:disable Magento2.Security.InsecureFunction` … `// phpcs:enable` (a block), `// phpcs:ignoreFile` (whole file). Always name the sniff; a bare `phpcs:ignore` hides everything. Q1 asks for the justification in the same comment. Suppressions are ignored by the Marketplace (`--ignore-annotations`), so they never rescue an error there.

## `phpcbf`

`vendor/bin/phpcbf --standard=Magento2 <paths>` rewrites files in place for every message whose sniff declares a fixer — the `[x]` lines of the full report or `Fixable=1` in CSV: indentation and whitespace, `array()` → `[]`, `$this->` → `$block->` in templates, `$block->escapeHtml()` → `$escaper->escapeHtml()`, lower-case keywords and constants, PSR-12 spacing. It never fixes `XssTemplate.FoundUnescaped`, `RawQuery`, `DiscouragedFunction`, `DirectThrow` or anything a human must decide. Run `phpcs` again afterwards, and commit the mechanical diff separately from behavioural changes. `phpcbf` exit codes (PHP_CodeSniffer 3.x): `0` nothing fixable found, `1` every fixable violation fixed, `2` some or all fixable violations could not be fixed; it prints a FIXED/REMAINING table per file.

## Marketplace (Extension Quality Program)

The Marketplace technical review runs Code Sniffer on the whole package regardless of what changed, with:

```bash
phpcs --standard=Magento2 --extensions=php,phtml --error-severity=10 --ignore-annotations --report=json --report-file=report.json <path-to-extension>
```

"If PHPCS finds any errors, the extension … is rejected"; warnings are reported but do not block, and the docs encourage fixing them anyway. Reproduce that locally with `vendor/bin/phpcs --standard=Magento2 --extensions=php,phtml --error-severity=10 --ignore-annotations app/code/Acme/Catalog` before submitting — note `--ignore-annotations`, which discards every `phpcs:ignore`.

## CI

Changed files only (GitHub Actions; the same three commands work in GitLab CI or a pre-commit hook):

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0                                                   # full history, so origin/<base>...HEAD resolves
- run: composer install --no-interaction --prefer-dist              # dev dependencies included; the installer plugin registers Magento2
- run: vendor/bin/phpcs -i | grep -q Magento2
- run: |
    files=$(git diff --name-only --diff-filter=ACMR origin/${{ github.base_ref }}...HEAD -- 'app/code/Acme/**' 'app/design/frontend/Acme/**' | grep -E '\.(php|phtml|graphqls|less|html|xml|js)$' || true)
    [ -z "$files" ] || vendor/bin/phpcs -q --standard=Magento2 --report-checkstyle=phpcs.xml --report-summary $files
```

`--report-<type>=<file>` writes one report to a file while `--report-<type>` (no value) prints another — that is how one run feeds both the log and an annotation action; a second `--report=` on the same command line is ignored (the first wins; `--report=summary,source` is the form for two on stdout), and `--report-file` redirects the `--report=` output to the file and prints nothing. Whole-module runs belong in a nightly job, not on every push; `--cache` and `--parallel` make even those tolerable. Checkstyle is what annotation actions and IDEs consume.

## Sources

- https://github.com/magento/magento-coding-standard/blob/develop/README.md — install with `composer require --dev`, the "cannot be added automatically" note and the `post-install-cmd`/`post-update-cmd` scripts, `phpcs -i`, `phpcs --standard=Magento2`, `phpcbf`, ESLint and Rector usage
- https://developer.adobe.com/commerce/php/coding-standards/ — PHP_CodeSniffer as the inspection tool, `vendor/bin/phpcs --standard=Magento2 <path to inspect>` from the project root
- https://developer.adobe.com/commerce/marketplace/guides/sellers/code-sniffer — the Marketplace command with `--error-severity=10 --ignore-annotations --report=json`, errors reject the extension, warnings do not block
- https://github.com/PHPCSStandards/PHP_CodeSniffer/wiki/Usage — `--standard`, `--report` types, `--severity`/`--error-severity`/`--warning-severity`, `-n`, `-q`, `-p`, `-s`, `--extensions`, `--ignore`, `--exclude`, `--sniffs`, `--parallel`, `--cache`, `--basepath`, `--runtime-set`, `ignore_warnings_on_exit`, automatic `phpcs.xml.dist` discovery
- Verified in a 2.4.9 install: `vendor/magento/magento-coding-standard/composer.json` and `Magento2/ruleset.xml` (severity bands, types, extensions arg, `testVersion`), `Magento2/Sniffs/*` (family listing), `vendor/bin/phpcs --standard=Magento2 -e` (308 sniffs), `vendor/bin/phpcs --config-show` (installer-written `installed_paths`), `vendor/squizlabs/php_codesniffer/src/Runner.php` (phpcs and phpcbf exit codes) and `src/Config.php` (`--report=` vs `--report-<type>` parsing), a multi-report run (`--report-checkstyle=phpcs.xml --report-summary`) on a scratch tree, `magento/magento2` root `composer.json` at tags 2.4.4–2.4.9 (`require-dev`)
