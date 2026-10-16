# Adding `/magekwik-magento:local-setup` to claude-magento

Working plan for the `feat/local-setup` branch — delete this file once every step below is done. Do not merge to `main` until fully tested: auto-publish is on, so every passing push to `main` ships.

The seven new files are already in place under `plugins/magento/` (nothing overwritten):

```
plugins/magento/commands/local-setup.md            the step-wise, resumable command prompt
plugins/magento/agents/local-setup-verifier.md     read-only health-check agent (step 9)
plugins/magento/scripts/local-setup-detect.sh      host/OS/tool/port/dir detection → JSON
plugins/magento/scripts/local-setup-env.sh         .magento-local.env ledger + credentials manager
plugins/magento/scripts/local-setup-docker-magento.sh  docker-magento template copy (replaces upstream's curl | bash)
plugins/magento/scripts/local-setup-media.sh       validates a user-placed media archive and streams it into the container
plugins/magento/scripts/local-setup-ports.sh       picks free host ports so DDEV/docker-magento start next to other tools
```

Then apply the three edits below, run the checks, and release as 1.1.0.

## 1. `plugins/magento/.claude-plugin/plugin.json`

- `"version": "1.1.0"`
- description → append `, guided local environment setup (/magekwik-magento:local-setup)` before the closing `.` — and mirror the same text in `.claude-plugin/marketplace.json`.

## 2. `README.md` — insert after the `/magekwik-magento:init` section

```markdown
### `/magekwik-magento:local-setup` — a working local store in nine resumable steps

Guides you from an empty folder (or an existing repo) to a running Magento on **Warden, DDEV, docker-magento or Valet**, on macOS, Linux, WSL2 or Windows (DDEV). Asks only what it cannot detect: where, from what (git URL, latest Magento Open Source, or Mage-OS), and which tool.

Everything it decides and every credential it generates lives in one git-ignored file, `.magento-local.env`, created up front with sensible pre-filled values you can edit before the step that uses them. When a step needs *you* — install Docker, run one `sudo`, add Marketplace keys, drop a sanitised DB dump at `.magento-local/db.sql.gz` or a media archive at `.magento-local/media.tar.gz` — it stops, tells you exactly what to do, and `re-run /magekwik-magento:local-setup` picks up at that step. It never asks for or touches a live database.

| Step | Does |
|---|---|
| 1 Target | here or another directory; creates `.magento-local.env` |
| 2 Source | existing repo / new Magento Open Source / new Mage-OS |
| 3 Environment | Warden · DDEV · docker-magento · Valet — recommended per OS and installed tools |
| 4 Prerequisites | checks Docker/tools; prints per-OS install steps and stops if missing |
| 5 Scaffold | `warden env-init`, `ddev config`, docker-magento template, or Valet services; starts them |
| 6 Code | `git clone` + `composer install`, or `composer create-project` (keys checked, never requested in chat) |
| 7 Database | fresh `setup:install` from the ledger, or import of a dump *you* placed locally; optional media archive copied into the container |
| 8 Configure | developer mode, base URLs, 2FA off, no cron, reindex |
| 9 Verify | a read-only agent checks services, DB, search, storefront and admin → PASS/FAIL table |

At the end it prints the store URL, admin login, DB credentials and the CLI prefix — all also in `.magento-local.env`. `--status` shows the ledger; `--reset` starts over (deletes only the ledger).
```

Also extend the "What it touches" list:

```markdown
- `/magekwik-magento:local-setup` writes only inside the target directory (environment files for the chosen tool, the cloned/installed code, `.magento-local.env`, and the two ignore entries in `.git/info/exclude` / `.gitignore`). It runs the environment tool's own commands; it never runs global installers or `sudo` for you.
```

## 3. `CHANGELOG.md`

```markdown
## 1.1.0 — unreleased
### Added
- `/magekwik-magento:local-setup`: guided, resumable local environment setup for Warden, DDEV, docker-magento and Valet on macOS/Linux/WSL2/Windows; new Magento Open Source / Mage-OS install or existing git repo; all choices and credentials in a git-ignored `.magento-local.env`.
- `local-setup-verifier` agent: read-only post-setup health check.
- `scripts/local-setup-detect.sh`, `scripts/local-setup-env.sh`, `scripts/local-setup-docker-magento.sh`, `scripts/local-setup-media.sh`, `scripts/local-setup-ports.sh`.
```

## 4. Checks before merging

```
claude plugin validate ./plugins/magento --strict && claude plugin validate .
shellcheck plugins/magento/scripts/local-setup-*.sh          # both clean
bash tests/run.sh                                            # add the three cases below to tests/
claude --plugin-dir ./plugins/magento                        # then: /magekwik-magento:local-setup --dir /tmp/ls-test --new --env ddev
```

Done: these three cases, plus regressions for macOS bash 3.2, running from another repo and git worktrees, are in `tests/local-setup-env.test.sh` (each runs under both `bash` and `/bin/bash`):

1. `local-setup-detect.sh` on an empty dir → valid JSON, `dir.empty=true`, `recommend` ∈ {warden,ddev}.
2. `local-setup-env.sh init` then `next` → `1`; `step 1 done`, `step 2 blocked x`, `next` → `2`; `.git/info/exclude` contains the file; `git check-ignore` passes.
3. `set DB_PASSWORD 'a|b&c$d'` round-trips through `get` unchanged.

Eval idea for `evals/`: fixture = empty dir + `--new --env ddev` with no `ddev` on PATH → the run must end at step 4 with the "Finish that, then re-run…" block and `STEP_4_PREREQUISITES=blocked` in the ledger, and must not have run `curl | bash` or `sudo`.

## Design notes (why it is shaped this way)

- **Command, not agent, for the interactive part.** Subagents cannot prompt the user (no AskUserQuestion), so the questions and the step ledger live in the command; the agent is reserved for the thing that benefits from a fresh, read-only context — verifying the result without "grading its own work".
- **One file for ledger and credentials**, pre-filled and `chmod 600`, ignored via `.git/info/exclude` so it works in any clone without touching the committed `.gitignore` — and also appended to `.gitignore` when one exists, so a later `git add -A` on a new repo stays safe.
- **No live DB access** is enforced three ways: credentials are generated, not asked; the only import path is a file the user places under `.magento-local/`; the verifier never prints password values.
- **Resume is idempotent**: every step re-checks its precondition before acting, and `blocked` steps print the same instructions again if the condition is still unmet.
- DDEV's fixed `db/db/db` credentials and Warden's domain/subdomain split are the two places where the ledger defaults must be overridden; the command does both in step 3/5 so the printed credentials are always the real ones.
