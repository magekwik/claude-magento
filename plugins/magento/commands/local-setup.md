---
name: local-setup
description: Guided, resumable local Magento environment setup — Warden, DDEV, docker-magento or Valet on macOS, Linux, WSL2 or Windows; new Magento Open Source / Mage-OS install or an existing git repo. Step-wise with a git-ignored .magento-local.env ledger that ends up holding every local credential. Never touches a live database. User-invoked only.
argument-hint: "[--dir <path>] [--env warden|ddev|docker-magento|valet] [--repo <git-url>] [--new] [--status] [--reset]"
disable-model-invocation: true
---

# /magekwik-magento:local-setup

You are setting up a **local** Magento 2 development environment for the user, one step at a time, with a ledger that survives interruptions. Rules that hold for the whole run:

- **Nine steps, in order, each recorded in `.magento-local.env`** (via `local-setup-env.sh step N done|blocked`). On every invocation you resume at the first step that is not `done`. Never skip ahead; never re-run a `done` step unless `--reset`.
- **Human intervention stops the run, cleanly.** When a step needs something only the user can do (install Docker, run a `sudo` command, add Composer keys, drop in a DB dump, open a new shell after an install), do everything you can, mark the step `blocked` with a note, print exactly what they must do, then end with: `Finish that, then re-run /magekwik-magento:local-setup to resume from step N.` Do not loop, poll, or wait.
- **No live systems.** Never ask for, connect to, or read credentials of any staging/production database, host, API or admin. Every credential is generated locally into `.magento-local.env`. If the user wants real data, the only path is a sanitised dump they place at `.magento-local/db.sql` or `.sql.gz` themselves (step 7).
- **Ask with the AskUserQuestion tool** when it is available; otherwise ask in plain text and stop until answered. Ask only what the ledger does not already answer. Arguments (`$ARGUMENTS`) pre-answer questions: `--dir`, `--env`, `--repo`, `--new`.
- **Prefix every Magento/Composer command for the chosen environment** (`$MAGE` below). The table and per-tool details are in `${CLAUDE_PLUGIN_ROOT}/skills/ops/references/dev-envs.md` — read it once at step 5. In non-TTY runs add `-T` for Warden and Compose.
- **Write nothing outside the target directory** except the tool's own global config (`~/.warden`, `~/.ddev`, Valet's config) which the tools write themselves, and the empty `~/.composer` and `~/.ssh` directories docker-magento mounts.
- Keep output short: one line per action, no narration of what you are about to do.

Helper scripts (always via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/…"`):

- `local-setup-detect.sh [dir]` → JSON: `os`, `tools{}`, `dir{}`, `ports{}`, `recommend`. Call it DETECT.
- `local-setup-env.sh init|get|set|step|next|status|show|ignore <dir> …` → the ledger. Call its file LEDGER.
- `local-setup-docker-magento.sh <dir>` → copies the docker-magento Compose template into DIR (step 5).

## 0. Resolve state

1. Parse `$ARGUMENTS`. `--status` → run `local-setup-env.sh status .` (or the `--dir`) and stop. `--reset` → confirm with the user, delete `.magento-local.env` only (never project files), then continue as a fresh run.
2. DIR = `--dir` if given, else the current directory. Run DETECT on DIR.
3. If `DETECT.dir.setup_file` is true: `N = local-setup-env.sh next DIR`. If N = 10 print the ledger `show` output and stop ("already complete"). Otherwise print `Resuming at step N (<name>)` plus `LAST_NOTE` if set, and jump to that step. Every value a resumed step needs comes from LEDGER (`get`), never from re-asking.
4. Otherwise start at step 1.

## 1. Target directory

Decide where the environment lives. Cases, from DETECT:

| DETECT.dir | Ask |
|---|---|
| `magento_root` true, `setup_file` false | "This directory already holds a Magento install (`bin/magento` found). Set up the local environment **here** (keeps the code, adds env + ledger) or in **another directory**?" |
| not empty, not a Magento root | "This directory isn't empty. Use it anyway (code goes in a subfolder you name), or give another path?" |
| empty or missing | use it, no question |

If the user names another path: create it (`mkdir -p`), re-run DETECT on it, and from now on DIR is that path. Run `local-setup-env.sh init DIR SETUP_OS=<DETECT.os> SETUP_DIR=<abs path>` (PROJECT_NAME = the directory's basename, lower-cased, non-alphanumerics → `-`; pass it as `PROJECT_NAME=…`). Tell the user the ledger was created and git-ignored, and that they may edit any value before the step that uses it. Mark step 1 `done`.

## 2. Source of the code

Skip the question when `--repo`/`--new` was given or `DETECT.dir.magento_root` is true (existing code → `SETUP_SOURCE=existing`). Otherwise ask:

- **Existing repository** → ask for the git URL (and optional branch). Validate shape only (`git ls-remote` is allowed and is not a live store). Set `SETUP_SOURCE=repo`, `SETUP_GIT_URL`, `SETUP_GIT_BRANCH`.
- **New install, latest Magento Open Source** → set `SETUP_SOURCE=new`, `SETUP_DISTRO=magento`, `SETUP_MAGENTO_VERSION=latest`. Note: this needs Adobe Marketplace keys (`auth.json`) — checked in step 6.
- **New install, latest Mage-OS** (community fork, no keys needed) → `SETUP_DISTRO=mage-os`.

For `repo`/`existing`, set `PHP_VERSION` from the repo's `composer.json` `require.php` / `config.platform.php` once the code is present (step 6); for `new`, 8.4 is the default. Mark step 2 `done`.

## 3. Environment tool

Choose `SETUP_ENV` ∈ `warden | ddev | docker-magento | valet`. Pre-answered by `--env` or by `DETECT.dir.existing_env` (a repo that already ships `.warden/`, `.ddev/` or docker-magento files → use that, say so, no question). Otherwise ask, listing the recommended one first (`DETECT.recommend`) with this guidance:

| Tool | Best when | OS support |
|---|---|---|
| **Warden** | several projects side by side, production-like stack (Traefik, Varnish, Redis, OpenSearch, RabbitMQ), Mutagen sync on macOS | macOS, Linux, WSL2 (Windows only inside WSL2) |
| **DDEV** | simplest install (one binary), one project at a time, cross-platform, good Windows support | macOS, Linux, WSL2, Windows (Docker Desktop + WSL2) |
| **docker-magento** (Mark Shust) | a standalone Compose stack with `bin/*` wrappers, no global daemon | macOS, Linux, WSL2 |
| **Valet** | no Docker, fastest page loads, services on the host | macOS (Laravel Valet) and Linux (valet-linux). **Not Windows** |

Hard rules: `valet` on `windows`/`wsl2` → refuse, offer DDEV. Any Docker tool on `windows` (non-WSL shell) → tell the user Claude Code must run **inside WSL2** for Warden/docker-magento; DDEV works from either. Ports: if `DETECT.ports.80` or `443` is `busy`, warn that Warden's Traefik / DDEV's router / docker-magento's nginx needs them and name the likely occupant (`lsof -nP -iTCP:80 -sTCP:LISTEN` / `sudo ss -ltnp`). Set `SETUP_ENV`; set hostnames in LEDGER to match the tool (`DB_HOST`, `SEARCH_HOST`, `REDIS_HOST`): Warden/docker-magento/valet below; DDEV → `DB_HOST=db DB_NAME=db DB_USER=db DB_PASSWORD=db` (DDEV's fixed database credentials) and `SEARCH_HOST=opensearch`; Valet → `DB_HOST=127.0.0.1 SEARCH_HOST=127.0.0.1 REDIS_HOST=127.0.0.1`. Mark step 3 `done`.

## 4. Prerequisites

Check DETECT.tools against the chosen tool. Everything missing is a **blocked** outcome: print the install instructions for `SETUP_OS` and stop — do not `curl | bash` global installers or run `sudo` yourself; the user does.

| `SETUP_ENV` | Needs |
|---|---|
| warden | Docker (running), `warden` — follow https://docs.warden.dev/installing.html. macOS and Linux with Homebrew: `brew install wardenenv/warden/warden`; Linux without Homebrew: the page's *Alternative Installation* (a `git clone` into `/opt/warden`, needs `sudo`); WSL2: its *Windows Installation (via WSL2)* section, including the Windows hosts/DNS step. Then `warden svc up` — its first run installs the CA → `sudo`. |
| ddev | Docker (running: Docker Desktop, OrbStack, Colima or Docker CE), `ddev` — macOS: `brew install ddev/ddev/ddev`; Linux/WSL2: the installer from docs.ddev.com; Windows: the `.exe` installer with the WSL2 backend. `mkcert -install` once (DDEV prompts). |
| docker-magento | Docker (running), `docker compose` v2, `curl`, `git`. |
| valet (macOS) | Homebrew, `php@<PHP_VERSION>`, `composer`, `mysql` (or `mariadb`) started (`brew services start mysql`), `opensearch` started (`brew services start opensearch`), `valet` (`composer global require laravel/valet && valet install`), optionally `redis`. |
| valet (linux) | `php<PHP_VERSION>` + fpm + extensions (`bcmath curl dom gd intl mbstring pdo_mysql soap sockets xsl zip`), `composer`, MariaDB/MySQL, OpenSearch (Docker is fine for search only), `valet-linux` (`composer global require cpriego/valet-linux && valet install`). |

When something is missing that the user can install without root (e.g. Composer global packages), still stop — the new binary needs a new shell/PATH. If everything is present and `docker_running` is true where required, mark step 4 `done` and continue in the same run.

## 5. Scaffold the environment

Read `${CLAUDE_PLUGIN_ROOT}/skills/ops/references/dev-envs.md` now. Work in DIR. Values come from LEDGER (`get`).

**First, for `SETUP_SOURCE=repo` only:** if CODE (DIR, or `DIR/src` for docker-magento) has no `composer.json`, clone now — `git clone [--branch <SETUP_GIT_BRANCH>] <SETUP_GIT_URL> <CODE>` (DIR non-empty because of the ledger only → clone into `_clone`, then `shopt -s dotglob; mv _clone/* .; rmdir _clone`). Scaffolding then lands on top of the repo, and the repo's own `.gitignore`/env files are respected. Clone failure (auth, wrong URL) → **blocked** with the git error. Then:

**warden**
1. `warden env-init <PROJECT_NAME> magento2` (skip if `.env` with `WARDEN_ENV_TYPE` exists). Edit `.env`: `TRAEFIK_DOMAIN=<DOMAIN>` (Warden wants domain + subdomain: set `TRAEFIK_DOMAIN` to the part after the first dot and `TRAEFIK_SUBDOMAIN` to the part before — `app.magento.test` → `magento.test` / `app`; a bare `magento.test` → `TRAEFIK_DOMAIN=magento.test`, `TRAEFIK_SUBDOMAIN=app`, and set `DOMAIN=app.magento.test` + `BASE_URL` in LEDGER), `PHP_VERSION`, `MYSQL_DISTRIBUTION`/`_VERSION` from `DB_DISTRIBUTION*`, `WARDEN_OPENSEARCH=1`, `WARDEN_REDIS=1`, `WARDEN_VARNISH=0`, `WARDEN_RABBITMQ=0`, `MYSQL_DATABASE=<DB_NAME> MYSQL_USER=<DB_USER> MYSQL_PASSWORD=<DB_PASSWORD> MYSQL_ROOT_PASSWORD=<DB_ROOT_PASSWORD>` (add the keys if absent).
2. `warden sign-certificate <TRAEFIK_DOMAIN>` — this calls `sudo` on first use. If it prompts or fails for lack of a TTY → **blocked**: tell the user to run that one command, then resume.
3. `warden env up`, then `warden env exec -T php-fpm mkdir -p pub/static pub/media var generated`.

**ddev**
1. `ddev config --project-name=<PROJECT_NAME> --project-type=magento2 --docroot=pub --upload-dirs=media --disable-settings-management --php-version=<PHP_VERSION> --database=<mariadb|mysql>:<DB_DISTRIBUTION_VERSION>` (skip when `.ddev/config.yaml` exists; then only reconcile `PHP_VERSION` from it into LEDGER). Set `DOMAIN=<PROJECT_NAME>.ddev.site`, `BASE_URL=https://<DOMAIN>/` in LEDGER.
2. `ddev add-on get ddev/ddev-opensearch` (or `ddev-elasticsearch` if `SEARCH_ENGINE=elasticsearch`).
3. `ddev start`. First start may ask for `sudo` to edit `/etc/hosts` or trust mkcert → **blocked** if it cannot complete non-interactively.

**docker-magento**
1. If `compose.yaml` + `bin/clinotty` are absent: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/local-setup-docker-magento.sh" DIR` — copies the template only (no install yet), never overwrites a file, merges `.gitignore`, and leaves DIR's `.git` alone. Never run upstream's `lib/template | bash` instead: it deletes DIR's `.git`, which drops the ledger's ignore rules. Exit 1 on an existing `bin/` → **blocked**: tell the user `bin/` is in the way. Record its last line's `<repo>@<sha>` as `SETUP_DM_TEMPLATE` in LEDGER. Code lives in `src/`; write `SETUP_CODE_DIR=src` to LEDGER (other tools: `.`).
2. Reconcile `env/db.env` to LEDGER (`MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`) and `env/magento.env` (`MAGENTO_ADMIN_*`, `MAGENTO_URL` = `DOMAIN`, hosts `db`/`opensearch`/`redis`) — the wrappers read these, so the two files must agree with LEDGER. Pin `compose.yaml` PHP image to `PHP_VERSION` if a matching tag exists (`markoshust/magento-php:<ver>-fpm-…`).
3. `bin/start` (pulls images; several minutes).

**valet**
1. `valet park` is not used; use `valet link <PROJECT_NAME>` from the code directory **after** step 6 — record `SETUP_VALET_LINK=pending`. Here: ensure services run (`brew services list` / `systemctl status`), create the database as root using `DB_ROOT_PASSWORD` only if the local MySQL has no root password yet (`mysql -uroot -e "CREATE DATABASE IF NOT EXISTS \`<DB_NAME>\`; CREATE USER IF NOT EXISTS '<DB_USER>'@'localhost' IDENTIFIED BY '<DB_PASSWORD>'; GRANT ALL ON \`<DB_NAME>\`.* TO '<DB_USER>'@'localhost';"`). If `mysql -uroot` needs a password you do not have → **blocked**: give the exact `CREATE …` statements and resume. Set `DOMAIN=<PROJECT_NAME>.test` (Valet's default TLD; read `valet tld` if changed).

Mark step 5 `done` only when services report healthy (`warden env ps` / `ddev describe` / `bin/status` / `brew services`).

## 6. Get the code

CODE = DIR, or DIR/`SETUP_CODE_DIR` for docker-magento. Composer and `bin/magento` run through `$MAGE` (Warden: `warden env exec -T php-fpm …` or `warden shell -c "…"`; DDEV: `ddev composer …`/`ddev magento …`; docker-magento: `bin/composer …`/`bin/magento …`; Valet: directly).

- **existing** (code already in DIR): nothing to fetch. Run `$MAGE composer install` (if `vendor/` missing). Needs `auth.json` when `composer.lock` references `repo.magento.com` → see Keys.
- **repo**: the clone already happened at the top of step 5 (so the scaffold sits on top of the repo). Here: read `composer.json` → if `require.php`/`config.platform.php` conflicts with `PHP_VERSION`, update LEDGER, fix the scaffold (`.env` `PHP_VERSION` / `ddev config --php-version` / docker-magento image tag), restart services, then `$MAGE composer install`.
- **new**: `$MAGE composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition <CODE-or-.>` (Mage-OS: `--repository-url=https://repo.mage-os.org/ mage-os/project-community-edition`). No version pin → latest. For Warden/DDEV when DIR already holds the env files, create into a temp subdir (`_app`) and move the contents up (`shopt -s dotglob; mv _app/* .`), because create-project refuses a non-empty directory.

**Keys (Magento, not Mage-OS):** `auth.json` at CODE root (git-ignored) or `~/.composer/auth.json` with `http-basic.repo.magento.com`. If absent → **blocked**: tell the user to create it (`composer config --global http-basic.repo.magento.com <public-key> <private-key>` — keys from marketplace.magento.com → My Profile → Access Keys), and resume. Never ask them to paste keys into the chat.

After install: `local-setup-env.sh ignore DIR` again (the new repo now has a `.git`), confirm `auth.json`, `app/etc/env.php` and `.magento-local.env` are all ignored (`git check-ignore -q <file>`). Mark step 6 `done`.

## 7. Database

Never connect anywhere outside the environment. Two paths:

**A. Import a dump** — only if `DB_DUMP` in LEDGER names an existing file (user placed it under `.magento-local/`). Tell the user before importing that it must be sanitised (no customer PII, no production keys). Import: Warden `warden db import < file` (gunzip first if `.gz`), DDEV `ddev import-db --file=<file>`, docker-magento `bin/mysql < file`, Valet `mysql -u<DB_USER> -p<DB_PASSWORD> <DB_NAME> < file`. Then write `app/etc/env.php` (if missing, `$MAGE bin/magento setup:config:set` with LEDGER values: `--db-host --db-name --db-user --db-password --backend-frontname=<ADMIN_URI> --key=<CRYPT_KEY>` — note: a dump with encrypted config needs the original `crypt/key`; say so and set `CRYPT_KEY` to what the user provides in LEDGER, never in chat), then `$MAGE bin/magento setup:upgrade`.

**B. Fresh install** (default):
```
$MAGE bin/magento setup:install \
  --base-url=<BASE_URL> --backend-frontname=<ADMIN_URI> \
  --db-host=<DB_HOST> --db-name=<DB_NAME> --db-user=<DB_USER> --db-password=<DB_PASSWORD> \
  --admin-firstname=<ADMIN_FIRSTNAME> --admin-lastname=<ADMIN_LASTNAME> --admin-email=<ADMIN_EMAIL> \
  --admin-user=<ADMIN_USER> --admin-password=<ADMIN_PASSWORD> \
  --language=<LOCALE> --currency=<CURRENCY> --timezone=<TIMEZONE> --use-rewrites=1 --key=<CRYPT_KEY> \
  --search-engine=<SEARCH_ENGINE> --<SEARCH_ENGINE>-host=<SEARCH_HOST> --<SEARCH_ENGINE>-port=<SEARCH_PORT> \
  --session-save=redis --session-save-redis-host=<REDIS_HOST> --session-save-redis-db=2 \
  --cache-backend=redis --cache-backend-redis-server=<REDIS_HOST> --cache-backend-redis-db=0 \
  --page-cache=redis --page-cache-redis-server=<REDIS_HOST> --page-cache-redis-db=1
```
Drop the three Redis groups when `REDIS_HOST` is empty or the tool has no Redis (Valet without `redis`). `--search-engine` value is `opensearch` or `elasticsearch7`; the host/port flags are `--opensearch-host/--opensearch-port` or `--elasticsearch-host/--elasticsearch-port`. Magento ≥ 2.4.6 defaults to OpenSearch. If `setup:install` fails on a missing `pub/static` write permission inside Warden, run the `mkdir` from step 5 and retry once. Any other failure: show the last 30 lines, mark `blocked` with the error summary, stop.

Sample data when `INSTALL_SAMPLE_DATA=yes`: `$MAGE bin/magento sampledata:deploy` (needs keys) then `setup:upgrade`.

Mark step 7 `done`.

## 8. Configure for local development

All through `$MAGE bin/magento …` (`config:set` writes DB config; `--lock-env` writes `env.php`):
```
deploy:mode:set developer
module:disable Magento_TwoFactorAuth Magento_AdminAdobeImsTwoFactorAuth   # local only; say so
config:set --lock-env web/unsecure/base_url <BASE_URL>   # https BASE_URL for both
config:set --lock-env web/secure/base_url <BASE_URL>
config:set --lock-env web/secure/use_in_frontend 1
config:set --lock-env web/secure/use_in_adminhtml 1
config:set --lock-env admin/security/session_lifetime 31536000
config:set --lock-env admin/security/password_lifetime 0
config:set --lock-env dev/static/sign 0
config:set --lock-env system/full_page_cache/caching_application 1
config:set --lock-env catalog/search/engine <SEARCH_ENGINE>
config:set --lock-env catalog/search/<SEARCH_ENGINE>_server_hostname <SEARCH_HOST>
cron:remove
indexer:reindex
cache:flush
```
For an imported dump additionally reset the admin: `admin:user:create --admin-user=<ADMIN_USER> --admin-password=<ADMIN_PASSWORD> --admin-email=<ADMIN_EMAIL> --admin-firstname=… --admin-lastname=…` (creates or updates), `cache:flush`. Valet only: `valet link <PROJECT_NAME>` in CODE, then `valet secure <PROJECT_NAME>` (may need `sudo` → blocked, resume), and set `SETUP_VALET_LINK=done`. Warden: if the domain was changed in step 5, `warden sign-certificate` again. Mark step 8 `done`.

## 9. Verify and hand over

1. Dispatch the `local-setup-verifier` agent with: DIR, the full LEDGER path, `SETUP_ENV`, `$MAGE` prefix, `BASE_URL`, `ADMIN_URI`. It is read-only and returns a `PASS`/`FAIL` table.
2. If any FAIL: fix what you can in this run (one retry per check: e.g. `cache:flush`, `indexer:reindex`, `warden env up`), re-dispatch once; still failing → mark step 9 `blocked` with the failing check names and stop with the agent's fix hints.
3. All PASS: mark step 9 `done`, run `/magekwik-magento:init` logic? **No** — just say one line: "Run `/magekwik-magento:init` to write CLAUDE.md for this project." Then print `local-setup-env.sh show DIR` verbatim, preceded by:

```
Local environment ready — <SETUP_ENV> at <DIR>
Store:  <BASE_URL>
Admin:  <BASE_URL><ADMIN_URI>   user <ADMIN_USER>   password <ADMIN_PASSWORD>
DB:     <DB_USER>/<DB_PASSWORD> @ <DB_HOST>/<DB_NAME>   (root <DB_ROOT_PASSWORD>)
CLI:    <$MAGE> bin/magento …
Credentials file: <DIR>/.magento-local.env (git-ignored; keep it, it is the only copy)
```

## Resume contract (what "blocked" prints)

```
Step N (<name>) needs you:
  1. <exact command or action>
  2. …
Finish that, then re-run /magekwik-magento:local-setup to resume from step N.
```
The ledger `LAST_NOTE` carries the same text so a later session can show it on resume. Re-running after a blocked step re-checks the condition first (tool present? file present? service up?) before doing any work, and if it is still unmet prints the same block again without side effects.
