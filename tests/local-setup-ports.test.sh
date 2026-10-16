#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/plugins/magento/scripts/local-setup-ports.sh"
tmp=$(mktemp -d)

# Hold a real listening socket on a free port in 20000-29999, so port+10000 stays below 40000.
listen() { # listen <outfile> → prints the bound port into <outfile>; caller kills $!
  python3 -c '
import socket, sys, time, random
for _ in range(200):
    s = socket.socket(); p = random.randint(20000, 29999)
    try: s.bind(("127.0.0.1", p)); break
    except OSError: s.close()
s.listen(); print(p, flush=True); time.sleep(120)' > "$1" &
  for _ in $(seq 1 50); do [ -s "$1" ] && return 0; sleep 0.1; done; return 1
}
listening() { python3 -c 'import socket,sys; s=socket.socket(); sys.exit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)' "$1"; }

shells="bash"
[ -x /bin/bash ] && shells="bash /bin/bash"

listen "$tmp/p" || { echo "  FAIL: could not open a listening socket"; exit 1; }
lpid=$!
P="$(cat "$tmp/p")"
listening "$P"; assert_eq "$?" "0" "fixture port $P is listening"

for sh in $shells; do
  # A. a busy port moves, to a free port that is not itself busy
  out="$($sh "$S" pick "$P")"
  q="${out#*=}"
  assert_eq "${out%%=*}" "$P" "$sh A reports the wanted port"
  assert_eq "$([ "$q" != "$P" ] && echo moved || echo same)" "moved" "$sh A busy port moved"
  listening "$q"; assert_eq "$?" "1" "$sh A chosen port is free"
  assert_eq "$q" "$((P + 10000))" "$sh A high port moves to p+10000"

  # B. a free port keeps its number
  F=$((P + 1)); while listening "$F"; do F=$((F + 1)); done
  assert_eq "$($sh "$S" pick "$F")" "$F=$F" "$sh B free port kept"

  # C. a moved port never lands on another port wanted in the same call
  W=$((P + 10000))
  out="$($sh "$S" pick "$P" "$W")"
  first="$(echo "$out" | sed -n 1p)"; second="$(echo "$out" | sed -n 2p)"
  assert_eq "$([ "${first#*=}" != "$W" ] && echo ok || echo clash)" "ok" "$sh C moved port avoids a wanted port"
  assert_eq "$second" "$W=$W" "$sh C the wanted port keeps its number"

  # D. bad input
  $sh "$S" pick abc > /dev/null 2>&1; assert_eq "$?" "1" "$sh D non-numeric refused"
  $sh "$S" pick > /dev/null 2>&1; assert_eq "$?" "1" "$sh D no ports refused"
  $sh "$S" > /dev/null 2>&1; assert_eq "$?" "1" "$sh D no command refused"
done

kill "$lpid" 2>/dev/null; wait "$lpid" 2>/dev/null
rm -rf "$tmp"
report
