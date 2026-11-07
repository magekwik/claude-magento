#!/usr/bin/env bash
# Mirrors the claude.ai directory's file-type rule for non-Verified organizations (LOCAL_CODE_FILE_TYPE):
# the plugin may ship only Markdown, text, JSON, YAML and PNG/JPEG/GIF/WebP/ICO images; no file may
# start with #!, hold a NUL byte or be invalid UTF-8; no package-manager config. The plugin's icon is exempt
# from the type list when it is UTF-8 text.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$ROOT/plugins/magento"
while IFS= read -r -d '' f; do
  rel="${f#"$P"/}"
  case "$rel" in
    *.md|*.txt|*.json|*.yaml|*.yml) text=1 ;;
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico) text=0 ;;
    .claude-plugin/icon.svg) text=1 ;;
    *) FAIL=$((FAIL+1)); echo "  FAIL: $rel: type not accepted from non-Verified organizations"; continue ;;
  esac
  case "$(basename "$rel")" in
    package.json|package-lock.json|pnpm-workspace.yaml|pnpm-lock.yaml|yarn.lock|composer.json|composer.lock|.npmrc|.yarnrc.yml)
      FAIL=$((FAIL+1)); echo "  FAIL: $rel: package manager configuration"; continue ;;
  esac
  if [ "$text" = 1 ]; then
    if [ "$(head -c2 "$f")" = '#!' ]; then FAIL=$((FAIL+1)); echo "  FAIL: $rel: starts with #!"; continue; fi
    if [ "$(tr -d '\000' < "$f" | wc -c)" != "$(wc -c < "$f")" ]; then FAIL=$((FAIL+1)); echo "  FAIL: $rel: NUL byte"; continue; fi
    if ! python3 -c 'import sys; open(sys.argv[1], encoding="utf-8").read()' "$f" 2>/dev/null; then FAIL=$((FAIL+1)); echo "  FAIL: $rel: not UTF-8"; continue; fi
  fi
  PASS=$((PASS+1))
done < <(find "$P" -type f -print0)
report
