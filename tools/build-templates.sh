#!/usr/bin/env bash
# Regenerates plugins/magento/templates/rules-*.md, the pre-rendered rules files that
# /magekwik-magento:init copies into a project. Run after editing the conventions skill or
# bumping the plugin version; tests/templates.test.sh fails when they are out of date.
# Usage: tools/build-templates.sh [outdir]
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$root/plugins/magento/templates}"
version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$root/plugins/magento/.claude-plugin/plugin.json" | head -1)
[ -n "$version" ] || { echo "no version in plugin.json" >&2; exit 1; }
mkdir -p "$out"
bash "$root/tools/render-rules.sh" --version "$version" --hyva false --luma true  > "$out/rules-luma.md"
bash "$root/tools/render-rules.sh" --version "$version" --hyva true  --luma false > "$out/rules-hyva.md"
bash "$root/tools/render-rules.sh" --version "$version" --hyva true  --luma true  > "$out/rules-hyva-luma.md"
