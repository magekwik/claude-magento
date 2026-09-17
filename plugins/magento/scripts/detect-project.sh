#!/usr/bin/env bash
# Prints one JSON object describing a Magento 2 project. No jq dependency.
# Usage: detect-project.sh [root]   Exit 2 if root is not a Magento project.
set -euo pipefail

root="${1:-.}"
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "not a Magento root: ${1:-.}" >&2; exit 2; }
cd "$root"

if [ ! -f bin/magento ] && ! grep -q '"magento/' composer.json 2>/dev/null; then
  echo "not a Magento root: $root" >&2
  exit 2
fi

json_str() { # escape a string for JSON
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# --- edition / version from composer.lock ---
edition="unknown"; version="null"
if [ -f composer.lock ]; then
  if grep -q '"name": *"magento/product-enterprise-edition"' composer.lock; then edition="commerce"; pkg="magento/product-enterprise-edition"
  elif grep -q '"name": *"magento/product-community-edition"' composer.lock; then edition="open-source"; pkg="magento/product-community-edition"
  fi
  if [ "$edition" != "unknown" ]; then
    v=$(grep -A3 "\"name\": *\"$pkg\"" composer.lock | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$v" ] && version="\"$(json_str "$v")\""
  fi
fi

# --- php ---
php="null"
if command -v php >/dev/null 2>&1; then
  p=$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)
  [ -n "$p" ] && php="\"$(json_str "$p")\""
fi

# --- modules in app/code ---
modules=""
for reg in app/code/*/*/registration.php; do
  [ -f "$reg" ] || continue
  dir="${reg%/registration.php}"
  name=$(grep -o "'[A-Za-z0-9]*_[A-Za-z0-9]*'" "$reg" | head -1 | tr -d "'")
  if [ -z "$name" ]; then vendor=$(basename "$(dirname "$dir")"); name="${vendor}_$(basename "$dir")"; fi
  modules="${modules:+$modules,}{\"name\":\"$(json_str "$name")\",\"path\":\"$(json_str "$dir")\"}"
done

# --- themes in app/design ---
themes=""
for tx in app/design/*/*/*/theme.xml; do
  [ -f "$tx" ] || continue
  dir="${tx%/theme.xml}"
  area=$(echo "$dir" | cut -d/ -f3)
  vendor=$(echo "$dir" | cut -d/ -f4)
  theme=$(echo "$dir" | cut -d/ -f5)
  parent=$(sed -n 's/.*<parent>\([^<]*\)<\/parent>.*/\1/p' "$tx" | head -1)
  [ -n "$parent" ] && parent="\"$(json_str "$parent")\"" || parent="null"
  themes="${themes:+$themes,}{\"area\":\"$area\",\"name\":\"$vendor/$theme\",\"path\":\"$(json_str "$dir")\",\"parent\":$parent}"
done

# --- hyva ---
hyva=false
if { [ -f composer.lock ] && grep -q '"name": *"hyva-themes/' composer.lock; } || [ -d app/code/Hyva ]; then hyva=true; fi

# --- dev environment ---
env="native"
if [ -d .warden ]; then env="warden"
elif [ -d .ddev ]; then env="ddev"
else
  for f in docker-compose*.yml compose*.yml compose*.yaml docker-compose*.yaml; do
    [ -f "$f" ] && env="docker" && break
  done
fi

# --- tooling ---
phpcs=false; phpstan=false; phpunit=false
for f in phpcs.xml phpcs.xml.dist; do [ -f "$f" ] && phpcs=true; done
for f in phpstan.neon phpstan.neon.dist; do [ -f "$f" ] && phpstan=true; done
for f in dev/tests/unit/phpunit.xml dev/tests/unit/phpunit.xml.dist; do [ -f "$f" ] && phpunit=true; done

# --- mode ---
mode="null"
if [ -r app/etc/env.php ]; then
  m=$(sed -n "s/.*'MAGE_MODE' *=> *'\([a-z]*\)'.*/\1/p" app/etc/env.php | head -1)
  [ -n "$m" ] && mode="\"$m\""
fi

printf '{"root":"%s","magento":{"edition":"%s","version":%s},"php":%s,"modules":[%s],"themes":[%s],"hyva":%s,"env":"%s","tooling":{"phpcs":%s,"phpstan":%s,"phpunit":%s},"mode":%s}\n' \
  "$(json_str "$root")" "$edition" "$version" "$php" "$modules" "$themes" "$hyva" "$env" "$phpcs" "$phpstan" "$phpunit" "$mode"
