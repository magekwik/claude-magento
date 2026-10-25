# Changelog

## 1.1.2 — 2026-10-25

### Changed
- `/magekwik-magento:local-setup` never reads, copies or moves `auth.json`: it only checks that the file exists. On DDEV, which does not mount `~/.composer`, the run stops and gives you the `cp` command to put a copy in the project yourself.
- Commands that need a local password or `CRYPT_KEY` run through the new `local-setup-env.sh run <dir> -- <command>`, which fills `@{KEY}` from `.magento-local.env`, instead of inline shell reads of the ledger.

## 1.1.1 — 2026-10-17

### Added
- `/magekwik-magento:local-setup`: guided, resumable local environment setup on Warden, DDEV, docker-magento or Valet, for a new Magento Open Source or Mage-OS install or an existing git repository, with optional sanitised DB dump and media archive import. Nine steps recorded in a git-ignored `.magento-local.env` that also holds the generated local credentials; when a step needs the user it stops with exact instructions and resumes there. Picks free ports for DDEV and docker-magento when 80/443 are taken. Never runs `sudo` or global installers, never connects to a live store, and keeps passwords and the encryption key out of the chat.
- `local-setup-verifier` agent: read-only health check at the end of a setup.
- Scripts: `local-setup-detect.sh`, `local-setup-env.sh`, `local-setup-docker-magento.sh` (replaces upstream's `curl | bash`), `local-setup-media.sh`, `local-setup-ports.sh` — bash 3.2-safe and unit-tested.
- Eval scenario `local-setup-ddev-missing`.

### Fixed
- CI content check no longer flags the plugin's `icon.svg`.

## 1.0.2 — 2026-10-07

### Fixed
- `/magekwik-magento:init` recognises Mage-OS projects. `detect-project.sh` refused a Mage-OS root whose `composer.json` has no `magento/*` require (a fresh `mage-os/project-community-edition` install) and reported every other one as edition `unknown`. It now reports edition `mage-os` with the Mage-OS release as `version` and the Magento release it tracks (`extra.magento_version`) as the new `magento.base` key; for Magento editions `base` equals `version`. Reported on LinkedIn.

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
