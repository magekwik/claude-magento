# Changelog

## Unreleased

### Changed
- Licence holder stated as 4KTechnologies Ltd (trading as Magekwik); no code changes.
- CI content check allows the `magekwik-magento:` / `magekwik-magento@` namespace.

## 1.0.1 — 2026-09-21

### Changed
- Plugin slug renamed from `magento` to `magekwik-magento` (directory naming policy: brand names you do not own may not be the plugin name). Commands are now `/magekwik-magento:init` and `/magekwik-magento:review`; skills `magekwik-magento:*`. The marketplace carries a `renames` entry so existing installs migrate. `CLAUDE.md` markers and `.claude/rules/magento.md` are unchanged.

## 1.0.0 — 2026-09-21

### Added
- Skills: conventions, module, data, api, frontend-luma, frontend-hyva, ops, quality.
- `/magekwik-magento:init` — writes a project-facts block to CLAUDE.md and `.claude/rules/magento.md`.
- `/magekwik-magento:review` — Magento-aware review of a diff, branch or PR via the `code-reviewer` agent.
- Eval suite and CI.
