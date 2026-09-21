# Marketplace submission

Third-party plugins are submitted to Anthropic's **community marketplace** (`anthropics/claude-plugins-community`, installed by users as `magento@claude-community`). The **official** marketplace (`claude-plugins-official`) is curated by Anthropic at its discretion — there is no application process, and the submission form does not add plugins to it.

## Where to submit

- **Console form** (individual authors): https://platform.claude.com/plugins/submit — sign in to the Claude Platform (Google / email / SSO).
- **claude.ai form** (Team/Enterprise orgs with directory management access): https://claude.ai/admin-settings/directory/submissions/plugins/new

The review pipeline runs `claude plugin validate` plus automated safety screening. Approved plugins are pinned to a commit SHA in the community catalog and CI bumps the pin automatically as new commits land on the repository. The public catalog syncs nightly, so there can be a delay before the plugin appears in the catalog's `marketplace.json`; check https://github.com/anthropics/claude-plugins-community/blob/main/.claude-plugin/marketplace.json.

## Values to enter (keep in sync with `plugins/magento/.claude-plugin/plugin.json`)

- Plugin name (slug): `magento`
- Display name: Magento
- Description: Magento Open Source 2.4 development toolkit: framework conventions, module/data/API/frontend skills for Luma and Hyvä, project setup (/magento:init) and Magento-aware code review (/magento:review).
- Category: development
- Author: Magekwik — https://magekwik.com
- Homepage / repository: https://github.com/magekwik/claude-magento (public)
- Plugin path within the repository: `plugins/magento`
- Release: `v1.0.0` — commit `2525390948c0936d760529c4fa75b66d94c4a2e2`
- License: MIT
- Keywords: magento, magento2, adobe-commerce, php, ecommerce, hyva, luma
- Components: 8 skills, 2 commands, 1 agent, 3 bash scripts. No hooks, no MCP servers, no network calls, no credentials.
- What it writes: `CLAUDE.md` (marked block) and `.claude/rules/magento.md` on `/magento:init`; PR comments only with `/magento:review N --comment`.
- Pre-submission check: `claude plugin validate ./plugins/magento --strict` → `✔ Validation passed` (run 2026-09-21).

After acceptance: update `plugins/magento/README.md` and the repo README install sections to mention `magento@claude-community`.

## Submissions

| Date | Form | Reference / status |
|---|---|---|
| — | — | not yet submitted |
