#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/plugins/magento/scripts/local-setup-docker-magento.sh"
tmp=$(mktemp -d)

# A local stand-in for github.com/markshust/docker-magento: compose/ holds the template.
up="$tmp/upstream"
mkdir -p "$up/compose/bin" "$up/compose/env" "$up/compose/.vscode"
printf 'services: {}\n' > "$up/compose/compose.yaml"
printf '#!/usr/bin/env bash\n' > "$up/compose/bin/clinotty" && chmod +x "$up/compose/bin/clinotty"
printf 'MYSQL_DATABASE=magento\n' > "$up/compose/env/db.env"
printf '{}\n' > "$up/compose/.vscode/launch.json"
printf 'src/\ncompose.versions.yaml\n' > "$up/compose/.gitignore"
printf 'not part of the template\n' > "$up/README.md"
git -C "$up" init -q -b master && git -C "$up" add -A && git -C "$up" -c user.name=t -c user.email=t@t commit -qm template
export DM_REPO="file://$up" HOME="$tmp/home"

shells="bash"
[ -x /bin/bash ] && shells="bash /bin/bash"

for sh in $shells; do
  t="$tmp/$(echo "$sh" | tr -c 'a-z0-9' '_')"
  mkdir -p "$t"

  # A. fresh dir that is a git repo with the ledger ignored: template copied, .git and ignore rules kept
  mkdir "$t/a" && git -C "$t/a" init -q
  bash "$ROOT/plugins/magento/scripts/local-setup-env.sh" init "$t/a" > /dev/null
  $sh "$S" "$t/a" > "$t/a.out" 2>&1; rc=$?
  assert_eq "$rc" "0" "$sh A exits 0"
  assert_contains "$t/a.out" "^template: file://.*@[0-9a-f]{7,}$" "$sh A reports repo@sha"
  assert_contains "$t/a/compose.yaml" "services" "$sh A compose.yaml copied"
  assert_eq "$([ -x "$t/a/bin/clinotty" ] && echo yes || echo no)" "yes" "$sh A bin/clinotty executable"
  assert_contains "$t/a/env/db.env" "MYSQL_DATABASE" "$sh A env/ copied"
  assert_contains "$t/a/.vscode/launch.json" "{}" "$sh A dot-dirs copied"
  assert_eq "$([ -e "$t/a/README.md" ] && echo yes || echo no)" "no" "$sh A only compose/ copied"
  assert_eq "$([ -d "$t/a/compose" ] && echo yes || echo no)" "no" "$sh A no compose/ dir left"
  git -C "$t/a" check-ignore -q .magento-local.env; assert_eq "$?" "0" "$sh A ledger still ignored"
  assert_contains "$t/a/.gitignore" "^src/$" "$sh A upstream .gitignore installed"
  assert_eq "$([ -d "$HOME/.composer" ] && [ -d "$HOME/.ssh" ] && echo yes || echo no)" "yes" "$sh A home dirs created"

  # B. existing files are kept; .gitignore merged without duplicates, even with no trailing newline
  mkdir -p "$t/b/env"
  printf 'MYSQL_DATABASE=mine\n' > "$t/b/env/db.env"
  printf '.magento-local.env\nsrc/' > "$t/b/.gitignore"
  $sh "$S" "$t/b" > "$t/b.out" 2>&1
  assert_contains "$t/b.out" "^skipped \(exists\): env/db.env$" "$sh B reports skip"
  assert_contains "$t/b/env/db.env" "^MYSQL_DATABASE=mine$" "$sh B existing file kept"
  assert_contains "$t/b.out" "^merged: .gitignore$" "$sh B reports merge"
  assert_contains "$t/b/.gitignore" "^\.magento-local\.env$" "$sh B own ignore kept"
  assert_eq "$(grep -cx 'src/' "$t/b/.gitignore")" "1" "$sh B no duplicate line"
  assert_contains "$t/b/.gitignore" "^compose\.versions\.yaml$" "$sh B new line appended"

  # C. an existing bin/ is refused and nothing is written
  mkdir -p "$t/c/bin"
  $sh "$S" "$t/c" > "$t/c.out" 2>&1; rc=$?
  assert_eq "$rc" "1" "$sh C bin/ exits 1"
  assert_contains "$t/c.out" "^exists: " "$sh C reports bin/"
  assert_eq "$([ -e "$t/c/compose.yaml" ] && echo yes || echo no)" "no" "$sh C nothing written"

  # D. missing directory exits 1
  $sh "$S" "$t/missing" > /dev/null 2>&1; rc=$?
  assert_eq "$rc" "1" "$sh D missing dir exits 1"
done

rm -rf "$tmp"
report
