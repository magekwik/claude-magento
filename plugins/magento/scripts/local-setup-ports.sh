#!/usr/bin/env bash
# Chooses host ports for /magekwik-magento:local-setup so DDEV or docker-magento can start next to
# whatever already listens (another tool's router, a MailHog, a local MySQL…).
# Usage: local-setup-ports.sh pick <port>…
#   Prints one "<wanted>=<chosen>" line per port, in order. A free port keeps its number. A busy one
#   moves to the first free candidate: 8000+p below 1024 (80→8080, 443→8443), p+10000 above
#   (3306→13306), stepping +1 past anything busy or already chosen/wanted in this call.
#   Exit 1 if no free port is found below 65535, or if lsof/ss/netstat are all missing.
set -euo pipefail

busy() { # busy <port> → 0 when something listens on it
  local p="$1"
  if command -v lsof >/dev/null 2>&1; then lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v ss >/dev/null 2>&1; then ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p\$"
  elif command -v netstat >/dev/null 2>&1; then netstat -an 2>/dev/null | grep -E 'LISTEN' | grep -qE "[:.]${p}[[:space:]]"
  else echo "ports: need lsof, ss or netstat" >&2; exit 1; fi
}

[ "${1:-}" = pick ] && [ $# -ge 2 ] || { sed -n '4,9p' "$0"; exit 1; }
shift
for p in "$@"; do
  case "$p" in ''|*[!0-9]*) echo "ports: not a port: $p" >&2; exit 1 ;; esac
done

taken=" $* "   # every wanted port is reserved, so a moved port never lands on another wanted one
for p in "$@"; do
  if ! busy "$p"; then echo "$p=$p"; continue; fi
  if [ "$p" -lt 1024 ]; then c=$((8000 + p)); else c=$((p + 10000)); fi
  while [ "$c" -lt 65535 ]; do
    case "$taken" in *" $c "*) ;; *) busy "$c" || break ;; esac
    c=$((c + 1))
  done
  [ "$c" -lt 65535 ] || { echo "ports: no free port for $p" >&2; exit 1; }
  taken="$taken$c "
  echo "$p=$c"
done
