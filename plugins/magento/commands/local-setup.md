---
name: local-setup
description: Guided, resumable local Magento environment setup — Warden, DDEV, docker-magento or Valet on macOS, Linux, WSL2 or Windows; new Magento Open Source / Mage-OS install or an existing git repo. Step-wise with a git-ignored .magento-local.env ledger that ends up holding every local credential. Never touches a live database. User-invoked only.
argument-hint: "[--dir <path>] [--env warden|ddev|docker-magento|valet] [--repo <git-url>] [--new [--distro magento|mage-os]] [--db-dump <path>] [--media <path>] [--status] [--reset]"
disable-model-invocation: true
---

# /magekwik-magento:local-setup

You are setting up a **local** Magento 2 development environment for the user, one step at a time, with a ledger that survives interruptions. Rules that hold for the whole run:

- **Nine steps, in order, each recorded in `.magento-local.env`** (via `local-setup-env.sh step N done|blocked`). On every invocation you resume at the first step that is not `done`. Never skip ahead; never re-run a `done` step unless `--reset`.
- **Human intervention stops the run, cleanly.** When a step needs something only the user can do (install Docker, run a `sudo` command, add Composer keys, drop in a DB dump, open a new shell after an install), do everything you can, mark the step `blocked` with a note, print exactly what they must do, then end with: `Finish that, then re-run /magekwik-magento:local-setup to resume from step N.` Do not loop, poll, or wait.
- **No live systems.** Never ask for, connect to, or read credentials of any staging/production database, host, API or admin. Every credential is generated locally into `.magento-local.env`. If the user wants real data, the only path is a sanitised dump they place at `.magento-local/db.sql` or `.sql.gz` themselves (step 7).
- **Ask with the AskUserQuestion tool** when it is available; otherwise ask in plain text and stop until answered. Ask only what the ledger does not already answer. Arguments (`$ARGUMENTS`) pre-answer questions: `--dir`, `--env`, `--repo`, `--new`, `--distro`, `--db-dump`, `--media` (the last two set `DB_DUMP` / `MEDIA_ARCHIVE` in LEDGER, as paths under `.magento-local/`).
- **Prefix every Magento/Composer command for the chosen environment** (`$MAGE` below). The table and per-tool details are in `${CLAUDE_PLUGIN_ROOT}/skills/ops/references/dev-envs.md` — read it once at step 5. In non-TTY runs add `-T` for Warden and Compose. `$MAGE` is notation, not a shell variable: write the prefix out, or define a function (`M() { warden env exec -T php-fpm bin/magento "$@"; }`) — zsh does not word-split an unquoted variable, so `$M bin/magento` fails there.
- **Write nothing outside the target directory** except the tool's own global config (`~/.warden`, `~/.ddev`, Valet's config) which the tools write themselves, and the empty `~/.composer` and `~/.ssh` directories docker-magento mounts.
- Keep output short: one line per action, no narration of what you are about to do.

Helper scripts (always via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/…"`):

- `local-setup-detect.sh [dir]` → JSON: `os`, `tools{}`, `dir{}`, `ports{}`, `recommend`. Call it DETECT.
- `local-setup-env.sh init|get|set|step|next|status|show|ignore <dir> …` → the ledger. Call its file LEDGER.
- `local-setup-docker-magento.sh <dir>` → copies the docker-magento Compose template into DIR (step 5).
- `local-setup-ports.sh pick <port>…` → a free host port for each wanted one (step 3).
- `local-setup-media.sh <dir> --check|--stream|--into <path>` → validates and delivers the media archive (step 7).

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

An explicit `--dir` answers the question: set up **here**, in that directory, keeping what is there (existing code → `SETUP_SOURCE=existing`; anything else stays alongside, and for `--repo` the clone in step 5 lands on top). Files the command itself created — `.magento-local.env` and `.magento-local/` — never make a directory count as non-empty.

If the user names another path: create it (`mkdir -p`), re-run DETECT on it, and from now on DIR is that path. Run `local-setup-env.sh init DIR SETUP_OS=<DETECT.os> SETUP_DIR=<abs path>` (PROJECT_NAME = the directory's basename, lower-cased, non-alphanumerics → `-`; pass it as `PROJECT_NAME=…`). Tell the user the ledger was created and git-ignored, and that they may edit any value before the step that uses it. Mark step 1 `done`.

## 2. Source of the code

Skip the question when `--repo`/`--new` was given or `DETECT.dir.magento_root` is true (existing code → `SETUP_SOURCE=existing`). `--new` alone means Magento Open Source; `--new --distro mage-os` means Mage-OS (`--distro` without `--new` implies it). Otherwise ask:

- **Existing repository** → ask for the git URL (and optional branch). Validate shape only (`git ls-remote` is allowed and is not a live store). Set `SETUP_SOURCE=repo`, `SETUP_GIT_URL`, `SETUP_GIT_BRANCH`.
- **New install, latest Magento Open Source** → set `SETUP_SOURCE=new`, `SETUP_DISTRO=magento`, `SETUP_MAGENTO_VERSION=latest`. Note: this needs Adobe Marketplace keys (`auth.json`) — checked in step 6.
- **New install, latest Mage-OS** (community fork, no keys needed) → `SETUP_DISTRO=mage-os`.

For `repo`/`existing`, set `PHP_VERSION` from the repo's `composer.json` `require.php` / `config.platform.php` once the code is present (step 6); for `new`, 8.4 is the default.

**Data, for `repo`/`existing` only** (a new install starts empty): unless `--db-dump` was given or `DB_DUMP` is already set, ask once — "Fresh install, or import a sanitised database dump you'll place locally?" Import → `DB_DUMP=.magento-local/db.sql.gz`, and if they also have media, `MEDIA_ARCHIVE=.magento-local/media.tar.gz`. Never ask for the dump's contents, a server or credentials in chat; the files arrive at step 7. Mark step 2 `done`.

## 3. Environment tool

Choose `SETUP_ENV` ∈ `warden | ddev | docker-magento | valet`. Pre-answered by `--env` or by `DETECT.dir.existing_env` (a repo that already ships `.warden/`, `.ddev/` or docker-magento files → use that, say so, no question). Otherwise ask, listing the recommended one first (`DETECT.recommend`) with this guidance:

| Tool | Best when | OS support |
|---|---|---|
| **Warden** | several projects side by side, production-like stack (Traefik, Varnish, Redis, OpenSearch, RabbitMQ), Mutagen sync on macOS | macOS, Linux, WSL2 (Windows only inside WSL2) |
| **DDEV** | simplest install (one binary), one project at a time, cross-platform, good Windows support | macOS, Linux, WSL2, Windows (Docker Desktop + WSL2) |
| **docker-magento** (Mark Shust) | a standalone Compose stack with `bin/*` wrappers, no global daemon | macOS, Linux, WSL2 |
| **Valet** | no Docker, fastest page loads, services on the host | macOS (Laravel Valet) and Linux (valet-linux). **Not Windows** |

Hard rules: `valet` on `windows`/`wsl2` → refuse, offer DDEV. Any Docker tool on `windows` (non-WSL shell) → tell the user Claude Code must run **inside WSL2** for Warden/docker-magento; DDEV works from either. Ports — never stop or reconfigure whatever already holds a port (another tool's router, a MailHog, a local database serve the user's other projects):
- **DDEV / docker-magento:** run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/local-setup-ports.sh" pick <ports>` with every host port the tool publishes — DDEV `80 443 8025 8026` (router HTTP/HTTPS, Mailpit HTTP/HTTPS); docker-magento `80 443 3306 6379 9200 9300 5672 15672 1080 8080` (app HTTP/HTTPS, db, redis, opensearch ×2, rabbitmq ×2, mailcatcher, phpmyadmin). It prints `wanted=chosen` per port; a busy port moves to a free one. Record `HTTP_PORT`/`HTTPS_PORT` (the choices for 80/443) in LEDGER, and when `HTTPS_PORT` is not 443 include it in the URL: `BASE_URL=https://<DOMAIN>:<HTTPS_PORT>/`. Tell the user in one line which ports moved and why; step 5 applies them.
- **Warden:** 80/443 held by Warden's own `traefik` container is normal (shared by all Warden projects). Held by anything else → warn and name the occupant (`lsof -nP -iTCP:80 -sTCP:LISTEN` / `sudo ss -ltnp`); Warden's router ports are global, so do not change them.
- **Valet:** its nginx needs 80/443 on the host; if busy, warn and name the occupant. Set `SETUP_ENV`; set hostnames in LEDGER to match the tool (`DB_HOST`, `SEARCH_HOST`, `REDIS_HOST`): Warden/docker-magento/valet below; DDEV → `DB_HOST=db DB_NAME=db DB_USER=db DB_PASSWORD=db DB_ROOT_PASSWORD=root` (DDEV's fixed database credentials), `SEARCH_HOST=opensearch`, and `REDIS_HOST=` (DDEV has no Redis unless the user adds `ddev add-on get ddev/ddev-redis`; with it empty, step 7 uses file cache and sessions); Valet → `DB_HOST=127.0.0.1 SEARCH_HOST=127.0.0.1 REDIS_HOST=127.0.0.1`. Mark step 3 `done`.

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

**First, for `SETUP_SOURCE=repo` only:** if CODE (DIR, or `DIR/src` for docker-magento) has no `composer.json`, clone now — `git clone [--branch <SETUP_GIT_BRANCH>] <SETUP_GIT_URL> <CODE>` (DIR holding only the ledger and `.magento-local/` → clone into `_clone`, then `shopt -s dotglob; mv _clone/* .; rmdir _clone` — this is on the host, before any container mounts exist, so `mv` is safe here). Scaffolding then lands on top of the repo, and the repo's own `.gitignore`/env files are respected. Clone failure (auth, wrong URL) → **blocked** with the git error. Then:

**warden**
1. `warden env-init <PROJECT_NAME> magento2` (skip if `.env` with `WARDEN_ENV_TYPE` exists). Edit `.env`: `TRAEFIK_DOMAIN=<DOMAIN>` (Warden wants domain + subdomain: set `TRAEFIK_DOMAIN` to the part after the first dot and `TRAEFIK_SUBDOMAIN` to the part before — `app.magento.test` → `magento.test` / `app`; a bare `magento.test` → `TRAEFIK_DOMAIN=magento.test`, `TRAEFIK_SUBDOMAIN=app`, and set `DOMAIN=app.magento.test` + `BASE_URL` in LEDGER), `PHP_VERSION`, `MYSQL_DISTRIBUTION`/`_VERSION` from `DB_DISTRIBUTION*`, `WARDEN_OPENSEARCH=1`, `WARDEN_REDIS=1`, `WARDEN_VARNISH=0`, `WARDEN_RABBITMQ=0`, `MYSQL_DATABASE=<DB_NAME> MYSQL_USER=<DB_USER> MYSQL_PASSWORD=<DB_PASSWORD> MYSQL_ROOT_PASSWORD=<DB_ROOT_PASSWORD>` (add the keys if absent). If `.env` is tracked by git (`git ls-files --error-unmatch .env` succeeds), ignoring it has no effect: tell the user the local passwords now show in its diff and must not be committed (`git update-index --skip-worktree .env` hides the change locally, if they want that).
2. `warden sign-certificate <TRAEFIK_DOMAIN>` — this calls `sudo` on first use. If it prompts or fails for lack of a TTY → **blocked**: tell the user to run that one command, then resume.
3. `warden env up`, then `warden env exec -T php-fpm mkdir -p pub/static pub/media var generated`.

**ddev**
1. `ddev config --project-name=<PROJECT_NAME> --project-type=magento2 --docroot=pub --upload-dirs=media --disable-settings-management --php-version=<PHP_VERSION> --database=<mariadb|mysql>:<DB_DISTRIBUTION_VERSION>` (skip when `.ddev/config.yaml` exists; then only reconcile `PHP_VERSION` from it into LEDGER). Set `DOMAIN=<PROJECT_NAME>.ddev.site`, `BASE_URL=https://<DOMAIN>/` in LEDGER.
2. `ddev add-on get ddev/ddev-opensearch` (or `ddev-elasticsearch` if `SEARCH_ENGINE=elasticsearch`).
3. If step 3 moved any port, write only the moved ones to `.ddev/config.local.yaml` (DDEV git-ignores it; it never touches DDEV's global config or other projects): `router_http_port`, `router_https_port`, `mailpit_http_port`, `mailpit_https_port`, as quoted strings, e.g. `router_https_port: "8443"`.
4. `ddev start`. First start may ask for `sudo` to edit `/etc/hosts` or trust mkcert → **blocked** if it cannot complete non-interactively.

**docker-magento**
1. If `compose.yaml` + `bin/clinotty` are absent: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/local-setup-docker-magento.sh" DIR` — copies the template only (no install yet), never overwrites a file, merges `.gitignore`, and leaves DIR's `.git` alone. Never run upstream's `lib/template | bash` instead: it deletes DIR's `.git`, which drops the ledger's ignore rules. Exit 1 on an existing `bin/` → **blocked**: tell the user `bin/` is in the way. Record its last line's `<repo>@<sha>` as `SETUP_DM_TEMPLATE` in LEDGER. Code lives in `src/`; write `SETUP_CODE_DIR=src` to LEDGER (other tools: `.`).
2. Reconcile `env/db.env` to LEDGER (`MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`) and `env/magento.env` (`MAGENTO_ADMIN_*`, `MAGENTO_URL` = `DOMAIN`, hosts `db`/`opensearch`/`redis`) — the wrappers read these, so the two files must agree with LEDGER. Pin `compose.yaml` PHP image to `PHP_VERSION` if a matching tag exists (`markoshust/magento-php:<ver>-fpm-…`).
3. If step 3 moved any port, write `compose.override.yaml` (the `bin/docker-compose` wrapper loads it last) replacing the ports of only the affected services with `!override` — a plain override would add to the list, not replace it, and the old port would still clash. Container ports stay as upstream: `app` `"<HTTP>:8000"`, `"<HTTPS>:8443"`; `db` `"<p>:3306"`; `redis` `"<p>:6379"`; `opensearch` `"<p>:9200"`, `"<p>:9300"`; `rabbitmq` `"<p>:15672"`, `"<p>:5672"`; `mailcatcher` `"<p>:1080"`; `phpmyadmin` `"<p>:80"`. Example: `services:\n  app:\n    ports: !override\n      - "8081:8000"\n      - "8443:8443"`. `!override` needs Docker Compose ≥ 2.24 (`docker compose version`); older → **blocked**: ask the user to update Docker. Add `/compose.override.yaml` to DIR's `.git/info/exclude` (or `.gitignore` outside a repo) — it is machine-specific.
4. The template bind-mounts `~/.ssh/id_rsa` and `~/.ssh/known_hosts`. For each that does not exist on the host (ed25519-only users have no `id_rsa`), Docker would create a **directory** at that path in the user's home: instead create an empty file under `.magento-local/` and mount it at the same container path in `compose.override.yaml` for `app`, `phpfpm` and `phpfpm-xdebug` (compose merges volumes by container path, so this replaces the upstream mount).
5. The domain must resolve to this machine: check `getent hosts <DOMAIN>` / `dscacheutil -q host -a name <DOMAIN>` (macOS) for `127.0.0.1`. Many machines resolve `*.test` already (Warden's or DDEV's DNS), but a bare one does not → **blocked**: the user runs `echo "127.0.0.1 <DOMAIN>" | sudo tee -a /etc/hosts` (what upstream's `bin/setup-domain` does with `sudo`), then resume.
6. `bin/start --no-dev` (pulls images; several minutes). Upstream's own install flow starts without the dev mounts while `src/` is still empty — `bin/start` in dev mode refuses to start when the `src/` files it mounts are missing. `bin/start` needs at least 6 GB of Docker memory; if containers are OOM-killed, **blocked**: free memory or raise Docker's limit — never stop the user's other projects yourself.

**valet**
1. `valet park` is not used; use `valet link <PROJECT_NAME>` from the code directory **after** step 6 — record `SETUP_VALET_LINK=pending`. Here: ensure services run (`brew services list` / `systemctl status`), create the database as root using `DB_ROOT_PASSWORD` only if the local MySQL has no root password yet (`mysql -uroot -e "CREATE DATABASE IF NOT EXISTS \`<DB_NAME>\`; CREATE USER IF NOT EXISTS '<DB_USER>'@'localhost' IDENTIFIED BY '<DB_PASSWORD>'; GRANT ALL ON \`<DB_NAME>\`.* TO '<DB_USER>'@'localhost';"`). If `mysql -uroot` needs a password you do not have → **blocked**: give the exact `CREATE …` statements and resume. Set `DOMAIN=<PROJECT_NAME>.test` (Valet's default TLD; read `valet tld` if changed).

Mark step 5 `done` only when services report healthy (`warden env ps` / `ddev describe` / `bin/status` / `brew services`).

## 6. Get the code

CODE = DIR, or DIR/`SETUP_CODE_DIR` for docker-magento. Composer and `bin/magento` run through `$MAGE` (Warden: `warden env exec -T php-fpm …` or `warden shell -c "…"`; DDEV: `ddev composer …`/`ddev magento …`; docker-magento: `bin/composer …`/`bin/magento …`; Valet: directly).

- **docker-magento**, all sources: the store runs from the `appdata` volume, and `src/` is the host copy. **new** → create the project inside the container (`bin/clinotty composer create-project … .` into `/var/www/html`; same repository URLs as below). **repo/existing** → `bin/copytocontainer --all` to push `src/` in, then `bin/composer install`. Either way, after `setup:install`/import in step 7: `mkdir -p src` (the copy fails without it), `bin/copyfromcontainer --all` so `src/` holds the code, `bin/setup-nginx` (the copied `nginx.conf` still holds a placeholder and nginx stops without this), then `bin/stop && bin/start` to switch to the dev mounts; if that start fails with containers still settling, run `bin/start` once more — upstream's `bin/setup` does the same sequence.
- **existing** (code already in DIR): nothing to fetch. Run `$MAGE composer install` (if `vendor/` missing). Needs `auth.json` when `composer.lock` references `repo.magento.com` → see Keys.
- **repo**: the clone already happened at the top of step 5 (so the scaffold sits on top of the repo). Here: read `composer.json` → if `require.php`/`config.platform.php` conflicts with `PHP_VERSION`, update LEDGER, fix the scaffold (`.env` `PHP_VERSION` / `ddev config --php-version` / docker-magento image tag), restart services, then `$MAGE composer install`.
- **new**: `$MAGE composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition <CODE-or-.>` (Mage-OS: `--repository-url=https://repo.mage-os.org/ mage-os/project-community-edition`). No version pin → latest. For Warden/DDEV when DIR already holds the env files, create into a temp subdir (`_app`) and copy the contents up with `cp -a _app/. . && rm -rf _app` (run it inside the container for Warden/DDEV), because create-project refuses a non-empty directory. Do not `mv`: Warden mounts `pub/media` as a volume, which cannot be replaced, and `cp -a` merges into it.

**Keys (Magento, not Mage-OS):** `auth.json` at CODE root (git-ignored) or `~/.composer/auth.json` with `http-basic.repo.magento.com`. Warden and docker-magento mount the host's `~/.composer` into the container; **DDEV does not** — when only the host file has the keys, copy it to `<CODE>/auth.json` (`chmod 600`; git-ignored by the ledger's rules, and Magento's usual place for it) before running Composer in the container. Never print its contents. If absent → **blocked**: tell the user to create it (`composer config --global http-basic.repo.magento.com <public-key> <private-key>` — keys from marketplace.magento.com → My Profile → Access Keys), and resume. Never ask them to paste keys into the chat.

Warden and DDEV on macOS sync code to the host with Mutagen, so files created in the container appear on the host only after the sync catches up: run host-side checks once `warden sync list` reports `Watching for changes` / after `ddev mutagen sync`, or check inside the container.

After install: `local-setup-env.sh ignore DIR` again (the new repo now has a `.git`; and if copying the project into place replaced `.gitignore`, this restores the entries — it adds only missing lines, so never save and re-append `.gitignore` by hand), confirm `auth.json`, `app/etc/env.php` and `.magento-local.env` are all ignored (`git check-ignore -q <file>`). Mark step 6 `done`.

## 7. Database

Never connect anywhere outside the environment. Two paths.

**Before either:** if `DB_DUMP` or `MEDIA_ARCHIVE` is set but its file is not there yet → **blocked**, listing: where to put each file (`.magento-local/` in DIR); that the dump must be sanitised (no customer PII, no production keys); and that if the source store keeps encrypted config, they must set `CRYPT_KEY` in `.magento-local.env` to that store's `crypt/key` from its `app/etc/env.php` — by editing the file, never by pasting it into the chat. To switch back to a fresh install they clear `DB_DUMP`. On resume, re-check the files before importing.

**A. Import a dump** — only if `DB_DUMP` in LEDGER names an existing file (user placed it under `.magento-local/`). Tell the user before importing that it must be sanitised (no customer PII, no production keys). Import: Warden `warden db import < file` (gunzip first if `.gz`), DDEV `ddev import-db --file=<file>`, docker-magento `bin/mysql < file`, Valet `mysql -u<DB_USER> -p<DB_PASSWORD> <DB_NAME> < file`. Then write `app/etc/env.php` (if missing, `$MAGE bin/magento setup:config:set` with LEDGER values: `--db-host --db-name --db-user --db-password --backend-frontname=<ADMIN_URI> --key=<CRYPT_KEY>` — `CRYPT_KEY` is whatever the user left in LEDGER). `setup:config:set` does not write `install/date`, and without it Magento treats the store as not installed and hides most commands; add it if missing: `$MAGE php -r '$f="app/etc/env.php"; $c=include $f; if (empty($c["install"]["date"])) { $c["install"]["date"]=gmdate("D, d M Y H:i:s +0000"); file_put_contents($f, "<?php\nreturn ".var_export($c, true).";\n"); }'`. Then `$MAGE bin/magento setup:upgrade`.

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

**Media (optional, after A or B)** — only if `MEDIA_ARCHIVE` in LEDGER names a file or folder the user placed under `.magento-local/` (`.tar.gz`, `.tgz`, `.tar`, `.zip` or a folder; its contents are `pub/media`, optionally wrapped in one `media/` or `pub/media/` folder). Never fetch media from a live store or ask for server access. Validate first: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/local-setup-media.sh" DIR --check` (refuses absolute or `..` paths, links, and anything outside `.magento-local/`; on refusal → **blocked** with its message). Then copy it **into the container**, not onto the host — Warden on macOS does not sync `pub/media` to the container, and DDEV/docker-magento treat it specially:
- Warden: `local-setup-media.sh DIR --stream | warden env exec -T php-fpm tar -xf - -C pub/media`
- DDEV: `local-setup-media.sh DIR --stream | ddev exec -s web tar -xf - -C pub/media`
- docker-magento: `local-setup-media.sh DIR --stream | (cd DIR && bin/docker-compose exec -T phpfpm tar -xf - -C /var/www/html/pub/media)` (`/var/www/html` is a named volume, so the host's `src/pub/media` is not it)
- Valet: `local-setup-media.sh DIR --into <CODE>/pub/media`
Then `$MAGE bin/magento cache:flush`. Do not run `catalog:images:resize` (slow); mention it as optional.

Sample data when `INSTALL_SAMPLE_DATA=yes`: `$MAGE bin/magento sampledata:deploy` (needs keys) then `setup:upgrade`.

Mark step 7 `done`.

## 8. Configure for local development

All through `$MAGE bin/magento …` (`config:set` writes DB config; `--lock-env` writes `env.php`):
```
deploy:mode:set developer
module:disable <the 2FA modules module:status lists>   # local only; say so. Magento_TwoFactorAuth, plus Magento_AdminAdobeImsTwoFactorAuth where it exists (not on Mage-OS) — one unknown name fails the whole command
setup:upgrade   # drops the disabled modules' tables, so setup:db:status is clean for the verifier
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
For an imported dump additionally reset the admin: `admin:user:create --admin-user=<ADMIN_USER> --admin-password=<ADMIN_PASSWORD> --admin-email=<ADMIN_EMAIL> --admin-firstname=… --admin-lastname=…` (creates or updates), `cache:flush`. docker-magento only: the HTTPS certificate is not trusted until the user runs `bin/setup-ssl-ca` and `bin/setup-ssl <DOMAIN>` (both use `sudo`) — never run them; list them in the hand-over, and expect the verifier's storefront check to WARN until then. Valet only: `valet link <PROJECT_NAME>` in CODE, then `valet secure <PROJECT_NAME>` (may need `sudo` → blocked, resume), and set `SETUP_VALET_LINK=done`. Warden: if the domain was changed in step 5, `warden sign-certificate` again. Mark step 8 `done`.

## 9. Verify and hand over

1. Dispatch the `local-setup-verifier` agent with: DIR, the full LEDGER path, `SETUP_ENV`, `$MAGE` prefix, `BASE_URL`, `ADMIN_URI`. It is read-only and returns a `PASS`/`FAIL` table.
2. If any FAIL: fix what you can in this run (one retry per check: e.g. `cache:flush`, `indexer:reindex`, `warden env up`), re-dispatch once; still failing → mark step 9 `blocked` with the failing check names and stop with the agent's fix hints.
3. All PASS: mark step 9 `done`. When a dump was imported, say the store uses the `CRYPT_KEY` from LEDGER and that encrypted settings decrypt only if it is the source store's key — you cannot tell whether it is, so do not claim either way. Do not run `/magekwik-magento:init` yourself; say one line: "Run `/magekwik-magento:init` to write CLAUDE.md for this project." Then print `local-setup-env.sh show DIR` verbatim, preceded by:

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
