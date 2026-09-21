# Release checklist

1. `bash tests/run.sh` and `claude plugin validate ./plugins/magento --strict && claude plugin validate .` are green. Also: `shellcheck -x -P SCRIPTDIR -e SC2015 -e SC2016 plugins/magento/scripts/*.sh evals/run.sh tests/*.sh` (matches CI).
2. `bash evals/run.sh` — every scenario PASS. Investigate any FAIL via `evals/.work/<name>/.transcript.txt`.
3. Real-world run A — Magekwik store (Warden, 2.4.9, LiteMage, custom modules):
   `cd ~/Repos/magekwik && claude --plugin-dir ~/Repos/claude-magento/plugins/magento`
   - `/magekwik-magento:init` → block shows Warden prefix, Magekwik modules, Luma; rules file written; re-run → still one block.
   - `/magekwik-magento:review master` → findings reference real files; PHPCS line says whether it ran.
   - Ask: "add a `before` plugin on the cart add so quantities over 10 are rejected" → uses `magekwik-magento:module`, no ObjectManager, plugin on an interface.
   - Ask: "why would `setup:upgrade` be slow here?" → uses `magekwik-magento:ops`, mentions Warden prefix from CLAUDE.md.
4. Real-world run B — fresh install:
   `composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=2.4.9 ~/tmp/m249 && cd ~/tmp/m249 && claude --plugin-dir ~/Repos/claude-magento/plugins/magento`
   - `/magekwik-magento:init` → native prefix, no modules, `Magento/luma` not listed as custom, Luma rules.
   - Ask: "scaffold a module Acme_Hello with a frontend route /hello" → complete module, `HttpGetActionInterface`, `routes.xml`.
   - Ask: "expose the hello message over GraphQL" → `schema.graphqls` + resolver, no per-row DB work.
   Nothing in the answers should mention Magekwik.
5. Bump `plugins/magento/.claude-plugin/plugin.json` `version`; add the CHANGELOG entry; commit `chore: release vX.Y.Z`.
6. `git tag vX.Y.Z && git push origin main --tags`; create the GitHub release from the tag with the CHANGELOG entry as body.
7. In a Claude Code session: `/plugin marketplace update magekwik` then `/plugin install magekwik-magento@magekwik` → the new version installs and `/magekwik-magento:init` runs.
8. Community marketplace (first release): submit at https://platform.claude.com/plugins/submit — see `docs/submission.md`. Later releases are picked up automatically (the catalog pins the latest commit SHA).
