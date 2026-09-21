# Marketplace submission

Third-party plugins are submitted to Anthropic's **community marketplace** (`anthropics/claude-plugins-community`, installed by users as `magekwik-magento@claude-community`). The **official** marketplace (`claude-plugins-official`) is curated by Anthropic at its discretion — there is no application process, and the submission form does not add plugins to it.

## Where to submit

- **Console form** (individual authors): https://platform.claude.com/plugins/submit — sign in to the Claude Platform (Google / email / SSO).
- **claude.ai form** (Team/Enterprise orgs with directory management access): https://claude.ai/admin-settings/directory/submissions/plugins/new

The review pipeline runs `claude plugin validate` plus automated safety screening. Approved plugins are pinned to a commit SHA in the community catalog and CI bumps the pin automatically as new commits land on the repository. The public catalog syncs nightly, so there can be a delay before the plugin appears in the catalog's `marketplace.json`; check https://github.com/anthropics/claude-plugins-community/blob/main/.claude-plugin/marketplace.json.

## Values to enter (keep in sync with `plugins/magento/.claude-plugin/plugin.json`)

- Plugin name (slug): `magekwik-magento`
- Display name: Magekwik Magento Toolkit
- Description: Magento Open Source 2.4 development toolkit: framework conventions, module/data/API/frontend skills for Luma and Hyvä, project setup (/magekwik-magento:init) and Magento-aware code review (/magekwik-magento:review).
- Category: development
- Author: Magekwik — https://magekwik.com
- Homepage / repository: https://github.com/magekwik/claude-magento (public)
- Plugin path within the repository: `plugins/magento`
- Release: `v1.0.1` (slug renamed from `magento` to `magekwik-magento` before first submission)
- License: MIT
- Keywords: magento, magento2, adobe-commerce, php, ecommerce, hyva, luma
- Components: 8 skills, 2 commands, 1 agent, 3 bash scripts. No hooks, no MCP servers, no network calls, no credentials.
- What it writes: `CLAUDE.md` (marked block) and `.claude/rules/magento.md` on `/magekwik-magento:init`; PR comments only with `/magekwik-magento:review N --comment`.
- Pre-submission check: `claude plugin validate ./plugins/magento --strict` → `✔ Validation passed` (run 2026-09-21).

After acceptance: update `plugins/magento/README.md` and the repo README install sections to mention `magekwik-magento@claude-community`.

## Submissions

| Date | Form | Reference / status |
|---|---|---|
| 2026-09-21 | Console (platform.claude.com/plugins/submit), org **4KTechnologies Ltd**, account support@magekwik.com | **Submitted and pending review.** Listed at https://platform.claude.com/plugins/submissions as "Magento Toolkit by Magekwik" — the form was filed just before the slug rename, so its recorded display name and description still say `/magento:init` / `/magento:review`; the repository (`plugins/magento`, v1.0.1, slug `magekwik-magento`) is what the review pipeline pulls. Console submissions cannot be edited after filing; do not file a second one (it would be a duplicate). If reviewers query the name, point them at `plugin.json`. |
