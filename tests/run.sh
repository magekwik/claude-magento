#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
status=0
for t in tests/*.test.sh; do
  echo "== $t"
  bash "$t" || status=1
done
exit $status
