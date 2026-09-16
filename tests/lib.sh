#!/usr/bin/env bash
# Minimal assertion helpers for bash tests. Source this file; call report at the end.
PASS=0
FAIL=0

assert_eq() { # actual expected label
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: $3: expected '$2', got '$1'"; fi
}

assert_contains() { # file regex label
  if grep -Eq -- "$2" "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: $3: '$2' not found in $1"; fi
}

assert_not_contains() { # file regex label
  if grep -Eq -- "$2" "$1"; then FAIL=$((FAIL+1)); echo "  FAIL: $3: '$2' unexpectedly found in $1"; else PASS=$((PASS+1)); fi
}

json_get() { # file dot.path  -> prints value; null -> "null"; bools -> true/false
  python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d[int(k)] if isinstance(d, list) else d.get(k)
    if d is None: break
if d is None: print("null")
elif isinstance(d, bool): print(str(d).lower())
else: print(d)
PY
}

report() {
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
