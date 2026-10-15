#!/usr/bin/env bash
# Copies the docker-magento (markshust) Compose template into <dir> for /magekwik-magento:local-setup.
# It installs the same files as upstream's lib/template, but without piping a download into a shell,
# and it leaves <dir>'s own .git alone (upstream deletes it and runs `git init`, which would drop the
# ledger's ignore rules). Existing files are never overwritten; .gitignore is merged line by line.
# Usage: local-setup-docker-magento.sh <dir>
# Env:   DM_REPO (default https://github.com/markshust/docker-magento), DM_REF (default master)
# Prints one line per skipped/merged file, then "template: <repo>@<short sha>".
# Exits 1 when <dir>/bin already exists (template already present, or bin/ belongs to something else).
set -euo pipefail

dir="${1:?usage: local-setup-docker-magento.sh <dir>}"
repo="${DM_REPO:-https://github.com/markshust/docker-magento}"
ref="${DM_REF:-master}"

[ -d "$dir" ] || { echo "no such directory: $dir" >&2; exit 1; }
if [ -e "$dir/bin" ]; then echo "exists: $dir/bin — template already present, or bin/ belongs to something else" >&2; exit 1; fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 --branch "$ref" "$repo" "$tmp/dm"
src="$tmp/dm/compose"
[ -d "$src" ] || { echo "no compose/ directory in $repo@$ref" >&2; exit 1; }

(cd "$src" && find . -type f) | sort | while IFS= read -r f; do
  f="${f#./}"
  if [ "$f" = ".gitignore" ] && [ -f "$dir/.gitignore" ]; then
    [ -z "$(tail -c1 "$dir/.gitignore")" ] || echo >> "$dir/.gitignore"
    while IFS= read -r line; do
      [ -z "$line" ] || grep -qxF -- "$line" "$dir/.gitignore" || printf '%s\n' "$line" >> "$dir/.gitignore"
    done < "$src/.gitignore"
    echo "merged: .gitignore"
  elif [ -e "$dir/$f" ]; then
    echo "skipped (exists): $f"
  else
    mkdir -p "$dir/$(dirname "$f")"
    cp -p "$src/$f" "$dir/$f"
  fi
done

# Upstream creates these so Docker does not create them as root when compose.yaml mounts them.
mkdir -p "$HOME/.composer" "$HOME/.ssh"

echo "template: $repo@$(git -C "$tmp/dm" rev-parse --short HEAD)"
