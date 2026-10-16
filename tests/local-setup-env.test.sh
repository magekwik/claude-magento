#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/plugins/magento/scripts/local-setup-env.sh"
D="$ROOT/plugins/magento/scripts/local-setup-detect.sh"
tmp=$(mktemp -d)

# Run every case under the PATH bash and under /bin/bash — on macOS that is bash 3.2, which
# the command will meet on any machine without a Homebrew bash.
shells="bash"
[ -x /bin/bash ] && shells="bash /bin/bash"

for sh in $shells; do
  t="$tmp/$(echo "$sh" | tr -c 'a-z0-9' '_')"
  mkdir -p "$t"

  # A. init on a fresh git repo: file created, defaults filled, ignored, private
  mkdir "$t/a" && git -C "$t/a" init -q
  $sh "$S" init "$t/a" > "$t/a.out" 2>&1
  assert_contains "$t/a.out" "^created: " "$sh A created"
  assert_contains "$t/a/.magento-local.env" "^SETUP_VERSION=1$" "$sh A default SETUP_VERSION"
  assert_contains "$t/a/.magento-local.env" "^DOMAIN=magento\.test$" "$sh A derived DOMAIN"
  assert_contains "$t/a/.magento-local.env" "^BASE_URL=https://magento\.test/$" "$sh A derived BASE_URL"
  assert_contains "$t/a/.magento-local.env" "^ADMIN_PASSWORD=[A-Za-z0-9]{8}[0-9]{2}[A-Za-z0-9]{4}$" "$sh A admin password generated"
  assert_contains "$t/a/.magento-local.env" "^DB_PASSWORD=[A-Za-z0-9]{20}$" "$sh A DB password generated"
  assert_contains "$t/a/.magento-local.env" "^CRYPT_KEY=[A-Za-z0-9]{32}$" "$sh A crypt key generated"
  assert_contains "$t/a/.magento-local.env" "^SETUP_DIR=$t/a$" "$sh A SETUP_DIR absolute"
  assert_eq "$(grep -c '^STEP_[1-9]_[A-Z]*=pending$' "$t/a/.magento-local.env")" "9" "$sh A nine pending steps"
  assert_eq "$(find "$t/a/.magento-local.env" -perm 0600 | wc -l | tr -d ' ')" "1" "$sh A chmod 600"
  assert_contains "$t/a/.git/info/exclude" "^\.magento-local\.env$" "$sh A excluded"
  git -C "$t/a" check-ignore -q .magento-local.env; assert_eq "$?" "0" "$sh A check-ignore"
  assert_eq "$([ -e "$t/a/.gitignore" ] && echo yes || echo no)" "no" "$sh A repo without .gitignore gets none (exclude is enough)"
  assert_contains "$t/a/.magento-local.env" "^SETUP_CODE_DIR=\.$" "$sh A SETUP_CODE_DIR default"

  # A2. run from inside another repo: the ignore rules land in the target, never in the caller
  mkdir "$t/caller" "$t/a2" && git -C "$t/caller" init -q && git -C "$t/a2" init -q
  (cd "$t/caller" && $sh "$S" init "$t/a2" > /dev/null 2>&1)
  assert_contains "$t/a2/.git/info/exclude" "^\.magento-local\.env$" "$sh A2 target excluded"
  assert_not_contains "$t/caller/.git/info/exclude" "magento-local" "$sh A2 caller untouched"

  # A3. a git worktree: the shared exclude file is used, so the ledger is ignored there
  mkdir "$t/main" && git -C "$t/main" init -q && git -C "$t/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x
  git -C "$t/main" worktree add -q "$t/wt" 2>/dev/null
  $sh "$S" init "$t/wt" > /dev/null 2>&1
  git -C "$t/wt" check-ignore -q .magento-local.env; assert_eq "$?" "0" "$sh A3 ignored in worktree"

  # B. overrides win over defaults, and DOMAIN/BASE_URL derive from the overridden PROJECT_NAME
  mkdir "$t/b"
  $sh "$S" init "$t/b" PROJECT_NAME=acme SETUP_OS=macos DB_HOST=127.0.0.1 > /dev/null 2>&1
  assert_contains "$t/b/.magento-local.env" "^PROJECT_NAME=acme$" "$sh B override PROJECT_NAME"
  assert_contains "$t/b/.magento-local.env" "^SETUP_OS=macos$" "$sh B override SETUP_OS"
  assert_contains "$t/b/.magento-local.env" "^DB_HOST=127\.0\.0\.1$" "$sh B override DB_HOST"
  assert_contains "$t/b/.magento-local.env" "^DOMAIN=acme\.test$" "$sh B DOMAIN from override"
  # B2. not a repo: .gitignore is created, so a later `git init && git add -A` leaves the ledger out
  assert_contains "$t/b/.gitignore" "^\.magento-local\.env$" "$sh B2 .gitignore created outside a repo"
  git -C "$t/b" init -q && git -C "$t/b" add -A
  assert_eq "$(git -C "$t/b" diff --cached --name-only | grep -c 'magento-local' )" "0" "$sh B2 ledger not staged after git init"

  # C. a directory with spaces keeps its full path
  mkdir "$t/c d"
  $sh "$S" init "$t/c d" > /dev/null 2>&1
  assert_contains "$t/c d/.magento-local.env" "^SETUP_DIR=$t/c d$" "$sh C SETUP_DIR with space"

  # D. an invalid override key is refused and leaves no file
  mkdir "$t/d"
  $sh "$S" init "$t/d" 'BAD-KEY=x' > "$t/d.out" 2>&1; rc=$?
  assert_eq "$rc" "1" "$sh D invalid key exits 1"
  assert_contains "$t/d.out" "invalid key: BAD-KEY" "$sh D invalid key message"
  assert_eq "$([ -f "$t/d/.magento-local.env" ] && echo yes || echo no)" "no" "$sh D no file written"

  # E. init twice is a no-op (credentials are not regenerated)
  before="$(grep '^DB_PASSWORD=' "$t/a/.magento-local.env")"
  $sh "$S" init "$t/a" > "$t/e.out" 2>&1
  assert_contains "$t/e.out" "^exists: " "$sh E reports exists"
  assert_eq "$(grep '^DB_PASSWORD=' "$t/a/.magento-local.env")" "$before" "$sh E password kept"

  # F. step ledger: next follows done/blocked
  assert_eq "$($sh "$S" next "$t/a")" "1" "$sh F next starts at 1"
  $sh "$S" step "$t/a" 1 "done"; assert_eq "$?" "0" "$sh F step without a note exits 0"
  $sh "$S" step "$t/a" 2 blocked "install ddev"
  assert_eq "$($sh "$S" next "$t/a")" "2" "$sh F next after blocked"
  assert_contains "$t/a/.magento-local.env" "^STEP_2_SOURCE=blocked$" "$sh F step 2 blocked"
  assert_contains "$t/a/.magento-local.env" "^LAST_NOTE=\[step 2 blocked\] install ddev$" "$sh F note recorded"
  for n in 2 3 4 5 6 7 8 9; do $sh "$S" step "$t/a" "$n" "done"; done
  assert_eq "$($sh "$S" next "$t/a")" "10" "$sh F all done"

  # G. set/get round-trips sed-special characters
  $sh "$S" set "$t/a" DB_PASSWORD 'a|b&c$d\e/f'
  assert_eq "$($sh "$S" get "$t/a" DB_PASSWORD)" 'a|b&c$d\e/f' "$sh G round-trip existing key"
  $sh "$S" set "$t/a" NEW_KEY 'x|y&z'
  assert_eq "$($sh "$S" get "$t/a" NEW_KEY)" 'x|y&z' "$sh G round-trip new key"
  $sh "$S" set "$t/a" DB_HOST=db DB_NAME=db 'CRYPT_KEY=a=b|c'; assert_eq "$?" "0" "$sh G KEY=VALUE pairs exit 0"
  assert_eq "$($sh "$S" get "$t/a" DB_HOST)/$($sh "$S" get "$t/a" DB_NAME)" "db/db" "$sh G KEY=VALUE pairs set"
  assert_eq "$($sh "$S" get "$t/a" CRYPT_KEY)" 'a=b|c' "$sh G value keeps later '='"
  $sh "$S" set "$t/a" SEARCH_HOST 'x=y'; assert_eq "$($sh "$S" get "$t/a" SEARCH_HOST)" 'x=y' "$sh G KEY VALUE with '=' in value"
  $sh "$S" set "$t/a" DB_HOST=x stray > /dev/null 2>&1; assert_eq "$?" "1" "$sh G mixed pair and bare word refused"
  $sh "$S" set "$t/a" DB_HOST > /dev/null 2>&1; assert_eq "$?" "1" "$sh G missing value refused"

  # H. detect on an empty dir: valid JSON, empty, a known recommendation
  mkdir "$t/h"
  $sh "$D" "$t/h" > "$t/h.json" 2>/dev/null
  assert_eq "$(json_get "$t/h.json" dir.empty)" "true" "$sh H dir.empty"
  assert_eq "$(json_get "$t/h.json" dir.setup_file)" "false" "$sh H no setup file"
  case "$(json_get "$t/h.json" recommend)" in warden|ddev|docker-magento|valet) r=ok ;; *) r=bad ;; esac
  assert_eq "$r" "ok" "$sh H recommend is a known tool"

  # I. tool detection uses each tool's real version syntax. Stubs: warden rejects --version like the
  #    real one (0.15) and answers `warden version`; ddev prints nothing; docker has no compose plugin.
  stub="$t/stub" && mkdir -p "$stub"
  printf '#!/bin/sh\n[ "$1" = version ] && { echo 0.15.0; exit 0; }\necho "ERROR: Unsupported flag $1" >&2; exit 1\n' > "$stub/warden"
  printf '#!/bin/sh\nexit 0\n' > "$stub/ddev"
  printf '#!/bin/sh\n[ "$1" = --version ] && { echo "Docker version 99"; exit 0; }\nexit 1\n' > "$stub/docker"
  chmod +x "$stub"/*
  PATH="$stub:$PATH" $sh "$D" "$t/h" > "$t/i.json" 2>/dev/null
  assert_eq "$(json_get "$t/i.json" tools.warden)" "0.15.0" "$sh I warden detected via 'warden version'"
  assert_eq "$(json_get "$t/i.json" tools.ddev)" "installed (version unknown)" "$sh I silent tool still detected"
  assert_eq "$(json_get "$t/i.json" tools.docker_compose)" "null" "$sh I docker without compose plugin"
  assert_eq "$(json_get "$t/i.json" recommend)" "warden" "$sh I installed warden recommended"
done

rm -rf "$tmp"
report
