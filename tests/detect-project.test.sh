#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/plugins/magento/scripts/detect-project.sh"
tmp=$(mktemp -d)

# 1. not a magento root
mkdir -p "$tmp/empty"
bash "$S" "$tmp/empty" > "$tmp/empty.out" 2> "$tmp/empty.err"; rc=$?
assert_eq "$rc" "2" "non-root exit code"
assert_eq "$(cat "$tmp/empty.out")" "" "non-root prints nothing on stdout"
assert_contains "$tmp/empty.err" "not a Magento root" "non-root message"

# 2. luma fixture
bash "$S" "$ROOT/evals/fixtures/luma-skeleton" > "$tmp/luma.json"; rc=$?
assert_eq "$rc" "0" "luma exit code"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp/luma.json" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "  FAIL: luma output is not valid JSON"; }
assert_eq "$(json_get "$tmp/luma.json" magento.edition)" "open-source" "luma edition"
assert_eq "$(json_get "$tmp/luma.json" magento.version)" "2.4.9" "luma version"
assert_eq "$(json_get "$tmp/luma.json" hyva)" "false" "luma hyva"
assert_eq "$(json_get "$tmp/luma.json" env)" "native" "luma env"
assert_eq "$(json_get "$tmp/luma.json" mode)" "developer" "luma mode"
assert_eq "$(json_get "$tmp/luma.json" modules.0.name)" "Acme_Catalog" "luma module name"
assert_eq "$(json_get "$tmp/luma.json" modules.0.path)" "app/code/Acme/Catalog" "luma module path"
assert_eq "$(json_get "$tmp/luma.json" themes.0.area)" "frontend" "luma theme area"
assert_eq "$(json_get "$tmp/luma.json" themes.0.name)" "Acme/default" "luma theme name"
assert_eq "$(json_get "$tmp/luma.json" themes.0.parent)" "Magento/luma" "luma theme parent"
assert_eq "$(json_get "$tmp/luma.json" tooling.phpcs)" "true" "luma phpcs"
assert_eq "$(json_get "$tmp/luma.json" tooling.phpstan)" "false" "luma phpstan"
php_v="$(json_get "$tmp/luma.json" php)"
if [ "$php_v" = "null" ] || [[ "$php_v" =~ ^[0-9]+\.[0-9]+ ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: php version '$php_v'"; fi

# 3. hyva fixture
bash "$S" "$ROOT/evals/fixtures/hyva-skeleton" > "$tmp/hyva.json"
assert_eq "$(json_get "$tmp/hyva.json" hyva)" "true" "hyva flag"
assert_eq "$(json_get "$tmp/hyva.json" env)" "ddev" "hyva env"
assert_eq "$(json_get "$tmp/hyva.json" mode)" "production" "hyva mode"
assert_eq "$(json_get "$tmp/hyva.json" themes.0.parent)" "Hyva/default" "hyva parent"
assert_eq "$(json_get "$tmp/hyva.json" tooling.phpcs)" "false" "hyva phpcs"

# 3b. vendor/bin/phpcs installed but no config -> tooling.phpcs true
cp -R "$ROOT/evals/fixtures/hyva-skeleton" "$tmp/vendor-phpcs"
mkdir -p "$tmp/vendor-phpcs/vendor/bin"
printf '#!/usr/bin/env php\n<?php // stand-in for squizlabs/php_codesniffer bin/phpcs\n' > "$tmp/vendor-phpcs/vendor/bin/phpcs"
chmod +x "$tmp/vendor-phpcs/vendor/bin/phpcs"
bash "$S" "$tmp/vendor-phpcs" > "$tmp/vendor-phpcs.json"
assert_eq "$(json_get "$tmp/vendor-phpcs.json" tooling.phpcs)" "true" "vendor/bin/phpcs with no config -> phpcs true"

# 4. env markers and unreadable env.php
cp -R "$ROOT/evals/fixtures/luma-skeleton" "$tmp/warden"; mkdir "$tmp/warden/.warden"
assert_eq "$(bash "$S" "$tmp/warden" | python3 -c 'import json,sys;print(json.load(sys.stdin)["env"])')" "warden" "warden env"
cp -R "$ROOT/evals/fixtures/luma-skeleton" "$tmp/docker"; touch "$tmp/docker/docker-compose.yml"
assert_eq "$(bash "$S" "$tmp/docker" | python3 -c 'import json,sys;print(json.load(sys.stdin)["env"])')" "docker" "docker env"
cp -R "$ROOT/evals/fixtures/luma-skeleton" "$tmp/warden-env"; printf 'WARDEN_ENV_NAME=acme\nWARDEN_ENV_TYPE=magento2\n' > "$tmp/warden-env/.env"
assert_eq "$(bash "$S" "$tmp/warden-env" | python3 -c 'import json,sys;print(json.load(sys.stdin)["env"])')" "warden" "warden env from .env only"
cp -R "$ROOT/evals/fixtures/luma-skeleton" "$tmp/docker-magento"; touch "$tmp/docker-magento/compose.yaml"
printf '#!/usr/bin/env bash\nexec docker compose exec -T phpfpm "$@"\n' > "$tmp/docker-magento/bin/clinotty"; chmod +x "$tmp/docker-magento/bin/clinotty"
assert_eq "$(bash "$S" "$tmp/docker-magento" | python3 -c 'import json,sys;print(json.load(sys.stdin)["env"])')" "docker-magento" "docker-magento env (compose.yaml + bin/clinotty)"
cp -R "$ROOT/evals/fixtures/luma-skeleton" "$tmp/noenv"; rm "$tmp/noenv/app/etc/env.php"
assert_eq "$(bash "$S" "$tmp/noenv" | python3 -c 'import json,sys;print(json.load(sys.stdin)["mode"])')" "None" "missing env.php -> null mode"

# 5. commerce edition + composer.json-only root (no bin/magento)
mkdir -p "$tmp/commerce"; printf '{"require":{"magento/product-enterprise-edition":"2.4.7"}}' > "$tmp/commerce/composer.json"
printf '{"packages":[{"name":"magento/product-enterprise-edition","version":"2.4.7"}]}' > "$tmp/commerce/composer.lock"
assert_eq "$(bash "$S" "$tmp/commerce" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["magento"]["edition"],d["magento"]["version"])')" "commerce 2.4.7" "commerce edition"

# 6. module registered with double-quoted name (no grep/tr crash under set -e pipefail)
cp -R "$ROOT/evals/fixtures/luma-skeleton" "$tmp/dquote-module"
mkdir -p "$tmp/dquote-module/app/code/Acme/Other"
cat > "$tmp/dquote-module/app/code/Acme/Other/registration.php" <<'PHP'
<?php
use Magento\Framework\Component\ComponentRegistrar;
ComponentRegistrar::register(ComponentRegistrar::MODULE, "Acme_Other", __DIR__);
PHP
bash "$S" "$tmp/dquote-module" > "$tmp/dquote-module.json"; rc=$?
assert_eq "$rc" "0" "double-quoted module exit code"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp/dquote-module.json" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "  FAIL: double-quoted module output is not valid JSON"; }
assert_eq "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sys.argv[2] in [m["name"] for m in d["modules"]])' "$tmp/dquote-module.json" "Acme_Other")" "True" "double-quoted module name detected"

# 7. theme vendor/name containing a double quote (must still produce valid, escaped JSON)
cp -R "$ROOT/evals/fixtures/luma-skeleton" "$tmp/dquote-theme"
theme_vendor='Ac"me'
mkdir -p "$tmp/dquote-theme/app/design/frontend/$theme_vendor/default"
cat > "$tmp/dquote-theme/app/design/frontend/$theme_vendor/default/theme.xml" <<'XML'
<?xml version="1.0"?>
<theme xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Config/etc/theme.xsd">
    <title>Quoted Vendor Theme</title>
    <parent>Magento/luma</parent>
</theme>
XML
bash "$S" "$tmp/dquote-theme" > "$tmp/dquote-theme.json"; rc=$?
assert_eq "$rc" "0" "quoted theme exit code"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp/dquote-theme.json" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "  FAIL: quoted theme output is not valid JSON"; }
assert_eq "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(any(t["name"]==sys.argv[2] for t in d["themes"]))' "$tmp/dquote-theme.json" 'Ac"me/default')" "True" "quoted theme name detected"

report
