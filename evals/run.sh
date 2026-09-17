#!/usr/bin/env bash
# Runs eval scenarios against fixture trees using `claude -p` with the plugin loaded.
# Usage: evals/run.sh [scenario-name ...]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/plugins/magento"
WORKROOT="$ROOT/evals/.work"
mkdir -p "$WORKROOT"

if [ $# -gt 0 ]; then
  scenarios=("$@")
else
  scenarios=()
  for d in "$ROOT"/evals/scenarios/*/; do
    [ -d "$d" ] && scenarios+=("$(basename "$d")")
  done
fi

failed=0
if [ "${#scenarios[@]}" -gt 0 ]; then
  for name in "${scenarios[@]}"; do
    case "$name" in
      ''|*/*|*..*|.*) echo "bad scenario name: '$name'" >&2; exit 1;;
    esac
    dir="$ROOT/evals/scenarios/$name"
    [ -d "$dir" ] || { echo "no such scenario: $name" >&2; exit 1; }
    [ -f "$dir/prompt.md" ] || { echo "SKIP $name (no prompt.md)"; continue; }
    fixture=$(sed -n 's/^fixture: *//p' "$dir/prompt.md" | head -1)
    prompt=$(awk 'BEGIN{c=0} /^---$/ && c<2 {c++; next} c>=2 {print}' "$dir/prompt.md")
    [ -n "$fixture" ] && [ -d "$ROOT/evals/fixtures/$fixture" ] || { echo "FAIL $name  (bad or missing fixture: '$fixture')"; failed=1; continue; }
    work="$WORKROOT/$name"
    rm -rf "$work"; mkdir -p "$work"
    cp -R "$ROOT/evals/fixtures/$fixture/." "$work/"
    ( cd "$work" && git init -q -b main && printf '.transcript.txt\n.first-run.txt\n' > .git/info/exclude && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm "fixture: $fixture" )
    export WORK="$work" TRANSCRIPT="$work/.transcript.txt" PLUGIN="$PLUGIN"
    if [ -f "$dir/setup.sh" ]; then ( cd "$work" && bash "$dir/setup.sh" ); fi
    ( cd "$work" && claude -p "$prompt" --plugin-dir "$PLUGIN" --setting-sources project,local --dangerously-skip-permissions > "$TRANSCRIPT" 2>&1 ) || true
    if ( cd "$work" && bash "$dir/assert.sh" ); then
      echo "PASS $name"
    else
      echo "FAIL $name  (see $work and $TRANSCRIPT)"; failed=1
    fi
  done
fi
exit $failed
