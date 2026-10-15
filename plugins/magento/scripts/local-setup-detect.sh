#!/usr/bin/env bash
# Prints one JSON object describing the host for /magekwik-magento:local-setup. No jq dependency.
# Usage: local-setup-detect.sh [dir]    (dir defaults to .)  Always exits 0 unless dir is unreadable.
# Keys:
#   os            macos | linux | wsl2 | windows | unknown
#   arch          x86_64 | arm64 | …
#   shell         bash version
#   tools{}       docker, docker_compose, docker_running, warden, ddev, valet, php, composer, mysql, git, mkcert, brew
#                 → each is the version string, or null when absent (docker_running is true/false)
#   php_version   host php -r PHP_VERSION or null
#   dir{}         path, exists, empty, is_git, git_remote, magento_root (bin/magento present), has_env_file
#                 (app/etc/env.php), setup_file (.magento-local.env present), existing_env (warden|ddev|docker-magento|docker|null)
#   ports{}       80, 443, 3306, 9200 → "free" | "busy" | "unknown"
#   recommend     warden | ddev | docker-magento | valet  — best fit for this host (see rules at bottom)
set -uo pipefail

dir="${1:-.}"
json_str() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'; }
jq_or_null() { if [ -n "${1:-}" ]; then printf '"%s"' "$(json_str "$1")"; else printf 'null'; fi; }

# --- os ---
os="unknown"
case "$(uname -s 2>/dev/null)" in
  Darwin) os="macos" ;;
  Linux)
    if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then os="wsl2"; else os="linux"; fi ;;
  MINGW*|MSYS*|CYGWIN*) os="windows" ;;
esac
arch="$(uname -m 2>/dev/null || echo unknown)"

# --- tools ---
ver() { # ver <cmd> <args…> → first line of output, trimmed, or empty
  local c="$1"; shift
  command -v "$c" >/dev/null 2>&1 || { printf ''; return; }
  "$c" "$@" 2>/dev/null | head -1 | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
t_docker="$(ver docker --version)"
t_compose="$(ver docker compose version)"
docker_running=false
if [ -n "$t_docker" ] && docker info >/dev/null 2>&1; then docker_running=true; fi
t_warden="$(ver warden --version)"
t_ddev="$(ver ddev --version)"
t_valet="$(ver valet --version)"
t_php="$(ver php --version)"
php_version=""
if command -v php >/dev/null 2>&1; then php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"; fi
t_composer="$(ver composer --version)"
t_mysql="$(ver mysql --version)"
t_git="$(ver git --version)"
t_mkcert="$(ver mkcert --version)"
t_brew="$(ver brew --version)"

# --- dir ---
d_exists=false; d_empty=true; d_git=false; d_remote=""; d_magento=false; d_envphp=false; d_setup=false; d_existing_env=""
if [ -d "$dir" ]; then
  d_exists=true
  if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then d_empty=false; fi
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    d_git=true
    d_remote="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  fi
  [ -f "$dir/bin/magento" ] || [ -f "$dir/src/bin/magento" ] && d_magento=true
  [ -f "$dir/app/etc/env.php" ] || [ -f "$dir/src/app/etc/env.php" ] && d_envphp=true
  [ -f "$dir/.magento-local.env" ] && d_setup=true
  if [ -d "$dir/.warden" ] || grep -qs '^WARDEN_ENV_TYPE=' "$dir/.env" 2>/dev/null; then d_existing_env="warden"
  elif [ -f "$dir/.ddev/config.yaml" ]; then d_existing_env="ddev"
  elif [ -f "$dir/bin/clinotty" ] && { [ -f "$dir/compose.yaml" ] || [ -f "$dir/docker-compose.yml" ]; }; then d_existing_env="docker-magento"
  elif ls "$dir"/docker-compose*.y*ml "$dir"/compose.y*ml >/dev/null 2>&1; then d_existing_env="docker"
  fi
fi
abs_dir="$(cd "$dir" 2>/dev/null && pwd || printf '%s' "$dir")"

# --- ports ---
port_state() { # busy | free | unknown
  local p="$1"
  if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then echo busy; else echo free; fi
  elif command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p\$"; then echo busy; else echo free; fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -an 2>/dev/null | grep -E 'LISTEN' | grep -qE "[:.]${p}[[:space:]]"; then echo busy; else echo free; fi
  else echo unknown; fi
}
p80="$(port_state 80)"; p443="$(port_state 443)"; p3306="$(port_state 3306)"; p9200="$(port_state 9200)"

# --- recommendation ---
# 1. an environment already present in dir wins (resume what the repo uses)
# 2. an installed tool wins: warden > ddev > valet (macOS only, and only when php+composer+mysql present) > docker-magento
# 3. nothing installed: macos → warden (brew install wardenenv/warden/warden), linux/wsl2 → ddev
#    (single curl installer, no root beyond Docker), windows (non-WSL) → ddev (Docker Desktop + WSL2 required).
rec="ddev"
if [ -n "$d_existing_env" ] && [ "$d_existing_env" != "docker" ]; then rec="$d_existing_env"
elif [ -n "$t_warden" ]; then rec="warden"
elif [ -n "$t_ddev" ]; then rec="ddev"
elif [ "$os" = "macos" ] && [ -n "$t_valet" ] && [ -n "$t_php" ] && [ -n "$t_composer" ] && [ -n "$t_mysql" ]; then rec="valet"
elif [ -n "$t_docker" ] && [ "$docker_running" = true ] && [ "$os" = "macos" ]; then rec="warden"
elif [ "$os" = "macos" ]; then rec="warden"
else rec="ddev"; fi

cat <<EOF
{
  "os": "$os",
  "arch": "$(json_str "$arch")",
  "shell": "$(json_str "${BASH_VERSION:-unknown}")",
  "tools": {
    "docker": $(jq_or_null "$t_docker"),
    "docker_compose": $(jq_or_null "$t_compose"),
    "docker_running": $docker_running,
    "warden": $(jq_or_null "$t_warden"),
    "ddev": $(jq_or_null "$t_ddev"),
    "valet": $(jq_or_null "$t_valet"),
    "php": $(jq_or_null "$t_php"),
    "composer": $(jq_or_null "$t_composer"),
    "mysql": $(jq_or_null "$t_mysql"),
    "git": $(jq_or_null "$t_git"),
    "mkcert": $(jq_or_null "$t_mkcert"),
    "brew": $(jq_or_null "$t_brew")
  },
  "php_version": $(jq_or_null "$php_version"),
  "dir": {
    "path": "$(json_str "$abs_dir")",
    "exists": $d_exists,
    "empty": $d_empty,
    "is_git": $d_git,
    "git_remote": $(jq_or_null "$d_remote"),
    "magento_root": $d_magento,
    "has_env_php": $d_envphp,
    "setup_file": $d_setup,
    "existing_env": $(jq_or_null "$d_existing_env")
  },
  "ports": { "80": "$p80", "443": "$p443", "3306": "$p3306", "9200": "$p9200" },
  "recommend": "$rec"
}
EOF
