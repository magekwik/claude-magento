# magento — Claude Code plugin

Makes Claude Code a competent Magento Open Source 2.4 developer: it knows the framework's conventions, scaffolds and reviews code the way an experienced Magento engineer would, and sets up any Magento project so Claude behaves consistently in it.

**Supports:** Magento Open Source 2.4.4–2.4.9 · PHP 8.1–8.5 · Luma and Hyvä frontends. Adobe Commerce-only features are referenced, not covered in depth.

## Install

```
/plugin marketplace add magekwik/claude-magento
/plugin install magento@magekwik
```

Once listed in the official directory: `/plugin install magento@claude-plugins-official`.

## What you get

| | |
|---|---|
| `/magento:init` | Detects edition/version, PHP, custom modules, themes (Luma/Hyvä), dev environment (Warden/DDEV/Docker/native) and tooling; writes a marked block into `CLAUDE.md` and a rules file into `.claude/rules/magento.md`. Re-run any time — it only touches its own block, and leaves the rules file alone once you edit its header away. |
| `/magento:review [branch\|PR] [--comment]` | Reviews your working tree (default), a branch diff, or a GitHub PR for Magento-specific defects — DI misuse, raw SQL, missing ACL/CSRF, plugin/observer misuse, layout and Luma/Hyvä mistakes — plus PHPCS Magento2 results when available. Findings are ranked with file:line, rule, why and fix. `--comment` posts them inline on the PR via `gh`. |
| `magento:conventions` | The rulebook (A1–Q6) the reviewer and `init` use. |
| `magento:module` | Modules, di.xml, plugins vs observers, cron, CLI, admin controllers. |
| `magento:data` | db_schema.xml, patches, service contracts, EAV, extension attributes. |
| `magento:api` | REST, GraphQL, ACL, tokens, CSRF. |
| `magento:frontend-luma` | Layout XML, templates, ViewModels, RequireJS/Knockout, LESS. |
| `magento:frontend-hyva` | Tailwind, Alpine, compat modules. |
| `magento:ops` | bin/magento workflows, caching, debugging, upgrades and patches, dev envs. |
| `magento:quality` | PHPCS, PHPStan, unit and integration tests. |

Skills load automatically when relevant; commands are explicit.

## What it touches

- `/magento:init` writes `CLAUDE.md` (a block between `<!-- magento:begin -->` / `<!-- magento:end -->`; marker lines inside ``` fences are ignored, so an unbalanced fence in CLAUDE.md can hide the live block) and `.claude/rules/magento.md`. Nothing else.
- `/magento:review` writes nothing. It runs `git`, and `vendor/bin/phpcs -q --standard=Magento2 --report=csv --basepath="$(git rev-parse --show-toplevel)"` if present. With a PR number it runs `gh`; with `--comment` it posts PR comments.
- No hooks, no MCP servers, no network calls of its own, no credentials.

## Requirements

Claude Code 2.1+ · `git` · `bash` · optional: `gh` (PR review), `vendor/bin/phpcs` with `magento/magento-coding-standard` (PHPCS findings).

## Development

See the repo README for tests and evals. Report issues at https://github.com/magekwik/claude-magento/issues.

MIT © Magekwik
