# Official directory submission

Form: https://clau.de/plugin-directory-submission

Values to enter (keep in sync with `plugins/magento/.claude-plugin/plugin.json`):

- Plugin name (slug): `magento`
- Display name: Magento
- Description: Magento Open Source 2.4 development toolkit: framework conventions, module/data/API/frontend skills for Luma and Hyvä, project setup (/magento:init) and Magento-aware code review (/magento:review).
- Category: development
- Author: Magekwik — https://magekwik.com
- Homepage: https://github.com/magekwik/claude-magento
- Source (git-subdir): url `https://github.com/magekwik/claude-magento.git`, path `plugins/magento`, ref `v1.0.0`, sha: output of `git rev-parse v1.0.0^{commit}`
- License: MIT
- Keywords: magento, magento2, adobe-commerce, php, ecommerce, hyva, luma
- Components: 8 skills, 2 commands, 1 agent, 3 bash scripts. No hooks, no MCP servers, no network calls, no credentials.
- What it writes: `CLAUDE.md` (marked block) and `.claude/rules/magento.md` on `/magento:init`; PR comments only with `/magento:review N --comment`.

After acceptance: update `plugins/magento/README.md` install section to lead with `magento@claude-plugins-official`, and for each later release resubmit with the new tag + sha.

## Submissions

(recorded below with date and any reference)
