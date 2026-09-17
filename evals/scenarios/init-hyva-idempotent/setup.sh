#!/usr/bin/env bash
set -euo pipefail
claude -p "/magento:init" --plugin-dir "$PLUGIN" --dangerously-skip-permissions --setting-sources project,local > .first-run.txt 2>&1 || true
[ -f CLAUDE.md ] || { echo "first init run produced no CLAUDE.md"; cat .first-run.txt; exit 1; }
printf '\nTeam note: keep me.\n' >> CLAUDE.md
