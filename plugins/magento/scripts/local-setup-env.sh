#!/usr/bin/env bash
# Manages .magento-local.env — the single file that holds BOTH the step ledger and every local
# credential for /magekwik-magento:local-setup. It is created pre-filled, read by every step,
# updated as steps complete, and shown (secrets masked) at the end. It is never committed: `init` adds it to
# .git/info/exclude (repo-local, works in any clone) and to .gitignore when one exists.
#
# Usage:
#   local-setup-env.sh init  <dir> KEY=VALUE…   create the file (no-op if present) with defaults + overrides, then ignore it
#   local-setup-env.sh get   <dir> KEY           print the value ("" if unset)
#   local-setup-env.sh set   <dir> KEY VALUE     set or add a key (in place)
#   local-setup-env.sh set   <dir> KEY=VALUE…    same, for one or more pairs
#   local-setup-env.sh step  <dir> N STATE [NOTE]  record step N (1-9) as pending|done|blocked with an optional note
#   local-setup-env.sh next  <dir>               print the first step number that is not done (10 = all done)
#   local-setup-env.sh status <dir>              print the ledger as a table
#   local-setup-env.sh show  <dir>               print the file with every secret (passwords, CRYPT_KEY) masked
#   local-setup-env.sh ignore <dir>              (re)apply the git ignore rules only
#   local-setup-env.sh write-env <dir> <file> NAME=VALUE|NAME=@KEY…
#                                                set NAME in a KEY=VALUE file (Warden .env, docker-magento env/*.env);
#                                                @KEY copies the ledger's KEY, so secrets never pass through the chat.
#                                                <file> is relative to <dir> unless absolute. Prints the names only.
set -euo pipefail

FILE=".magento-local.env"
cmd="${1:-}"; dir="${2:-.}"; shift 2 2>/dev/null || true
path="$dir/$FILE"

rand() { # rand <len> — URL-safe random string, works without openssl
  local n="$1"
  if command -v openssl >/dev/null 2>&1; then openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$n"
  else LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$n"; fi
}
# Magento admin passwords need letters AND digits, ≥7 chars.
admin_pw() { printf '%s%s%s' "$(rand 8)" "$(( RANDOM % 90 + 10 ))" "$(rand 4)"; }

ignore_file() {
  # The ledger and its folder, Magento's own secrets once the code lands (CODE = DIR for every tool
  # but docker-magento, whose upstream .gitignore already ignores src/), and Warden's .env, which step 5
  # fills with the generated database passwords. Ignoring never untracks a file git already tracks.
  local lines=".magento-local.env .magento-local/ /auth.json /app/etc/env.php /.env" targets=() t l
  if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    # --git-path is relative to $dir (not our cwd) and follows worktrees to the shared exclude file.
    ex="$(git -C "$dir" rev-parse --git-path info/exclude)"
    case "$ex" in /*) ;; *) ex="$(cd "$dir" && pwd)/$ex" ;; esac
    mkdir -p "$(dirname "$ex")"
    targets+=("$ex")
  fi
  # Outside a repo, .gitignore instead (created if needed), so a later `git init && git add -A` cannot
  # commit the credentials. Inside one, the exclude file is enough: a committed .gitignore stays untouched.
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then targets+=("$dir/.gitignore"); fi
  for t in ${targets[@]+"${targets[@]}"}; do
    if ! grep -qxF "$FILE" "$t" 2>/dev/null; then
      if [ -s "$t" ] && [ -n "$(tail -c1 "$t")" ]; then echo >> "$t"; fi
      printf '# local setup ledger + credentials (/magekwik-magento:local-setup)\n' >> "$t"
    fi
    for l in $lines; do grep -qxF "$l" "$t" 2>/dev/null || printf '%s\n' "$l" >> "$t"; done
  done
}

get() { sed -n "s/^$1=//p" "$path" 2>/dev/null | head -1; }
set_kv() {
  local k="$1" v="$2"
  v="${v//\\/\\\\}"; v="${v//&/\\&}"; v="${v//|/\\|}"
  if grep -q "^$k=" "$path"; then sed -i.bak "s|^$k=.*|$k=$v|" "$path" && rm -f "$path.bak"
  else printf '%s=%s\n' "$k" "$2" >> "$path"; fi
}

case "$cmd" in
  init)
    mkdir -p "$dir"
    if [ -f "$path" ]; then ignore_file; echo "exists: $path"; exit 0; fi
    # defaults — every one overridable via KEY=VALUE args. Stored as D_<KEY> variables rather than an
    # associative array: macOS ships bash 3.2, which has no `declare -A`.
    dset() { printf -v "D_$1" '%s' "$2"; }
    dget() { local n="D_$1"; printf '%s' "${!n-}"; }
    while read -r k v; do dset "$k" "$v"; done <<EOF
SETUP_VERSION 1
SETUP_ENV
SETUP_OS
SETUP_DIR $(cd "$dir" && pwd)
SETUP_SOURCE new
SETUP_GIT_URL
SETUP_GIT_BRANCH
SETUP_DISTRO magento
SETUP_MAGENTO_VERSION latest
SETUP_CODE_DIR .
PROJECT_NAME magento
DOMAIN
BASE_URL
HTTP_PORT 80
HTTPS_PORT 443
ADMIN_URI admin
ADMIN_USER admin
ADMIN_PASSWORD $(admin_pw)
ADMIN_EMAIL admin@example.com
ADMIN_FIRSTNAME Local
ADMIN_LASTNAME Admin
DB_HOST db
DB_NAME magento
DB_USER magento
DB_PASSWORD $(rand 20)
DB_ROOT_PASSWORD $(rand 20)
DB_DUMP
MEDIA_ARCHIVE
SEARCH_ENGINE opensearch
SEARCH_HOST opensearch
SEARCH_PORT 9200
REDIS_HOST redis
RABBITMQ_HOST
PHP_VERSION 8.4
DB_DISTRIBUTION mariadb
DB_DISTRIBUTION_VERSION 10.6
INSTALL_SAMPLE_DATA no
MAGE_MODE developer
CRYPT_KEY $(rand 32)
LOCALE en_GB
CURRENCY GBP
TIMEZONE Europe/London
EOF
    for kv in "$@"; do
      k="${kv%%=*}"
      case "$k" in ''|[0-9]*|*[!A-Za-z0-9_]*) echo "invalid key: $k" >&2; exit 1 ;; esac
      dset "$k" "${kv#*=}"
    done
    [ -n "$(dget DOMAIN)" ] || dset DOMAIN "$(dget PROJECT_NAME).test"
    [ -n "$(dget BASE_URL)" ] || dset BASE_URL "https://$(dget DOMAIN)/"
    {
      echo "# .magento-local.env — generated by /magekwik-magento:local-setup on $(date -u +%Y-%m-%dT%H:%MZ)"
      echo "# This file is your step ledger AND your local credentials. It is git-ignored (.git/info/exclude in a repo, .gitignore outside one)."
      echo "# Edit any value BEFORE the step that uses it runs, then re-run /magekwik-magento:local-setup to continue."
      echo "# Every credential here is local-only and randomly generated — nothing was read from any live system."
      echo
      echo "## Target"
      for k in SETUP_VERSION SETUP_ENV SETUP_OS SETUP_DIR SETUP_SOURCE SETUP_GIT_URL SETUP_GIT_BRANCH SETUP_DISTRO SETUP_MAGENTO_VERSION SETUP_CODE_DIR PROJECT_NAME DOMAIN BASE_URL HTTP_PORT HTTPS_PORT; do echo "$k=$(dget "$k")"; done
      echo
      echo "## Admin (use these to log in)"
      for k in ADMIN_URI ADMIN_USER ADMIN_PASSWORD ADMIN_EMAIL ADMIN_FIRSTNAME ADMIN_LASTNAME; do echo "$k=$(dget "$k")"; done
      echo
      echo "## Database (hostnames are service names inside the environment)"
      for k in DB_HOST DB_NAME DB_USER DB_PASSWORD DB_ROOT_PASSWORD DB_DISTRIBUTION DB_DISTRIBUTION_VERSION DB_DUMP MEDIA_ARCHIVE; do echo "$k=$(dget "$k")"; done
      echo "# DB_DUMP: optional. Put a sanitised dump at .magento-local/db.sql(.gz) and set DB_DUMP to that path to import it instead of a fresh install."
      echo "# MEDIA_ARCHIVE: optional. Put pub/media as .magento-local/media.tar.gz (.tgz, .tar, .zip or a folder) and set MEDIA_ARCHIVE to that path; step 7 copies it in."
      echo
      echo "## Services"
      for k in SEARCH_ENGINE SEARCH_HOST SEARCH_PORT REDIS_HOST RABBITMQ_HOST PHP_VERSION MAGE_MODE INSTALL_SAMPLE_DATA CRYPT_KEY LOCALE CURRENCY TIMEZONE; do echo "$k=$(dget "$k")"; done
      echo
      echo "## Step ledger (pending | done | blocked) — the command resumes at the first step that is not done"
      echo "STEP_1_TARGET=pending"
      echo "STEP_2_SOURCE=pending"
      echo "STEP_3_ENVIRONMENT=pending"
      echo "STEP_4_PREREQUISITES=pending"
      echo "STEP_5_SCAFFOLD=pending"
      echo "STEP_6_CODE=pending"
      echo "STEP_7_DATABASE=pending"
      echo "STEP_8_CONFIGURE=pending"
      echo "STEP_9_VERIFY=pending"
      echo "LAST_NOTE="
    } > "$path"
    chmod 600 "$path" 2>/dev/null || true
    ignore_file
    echo "created: $path"
    ;;
  get)   get "$1" ;;
  set)
    case "${1:-}" in
      *=*) # KEY=VALUE… pairs; a key never contains "=", so the first "=" splits key from value
        for kv in "$@"; do
          k="${kv%%=*}"
          case "$kv" in *=*) ;; *) echo "expected KEY=VALUE, got: $kv" >&2; exit 1 ;; esac
          case "$k" in ''|[0-9]*|*[!A-Za-z0-9_]*) echo "invalid key: $k" >&2; exit 1 ;; esac
          set_kv "$k" "${kv#*=}"
        done ;;
      *) [ $# -eq 2 ] || { echo "usage: set <dir> KEY VALUE | set <dir> KEY=VALUE…" >&2; exit 1; }
         case "$1" in ''|[0-9]*|*[!A-Za-z0-9_]*) echo "invalid key: $1" >&2; exit 1 ;; esac
         set_kv "$1" "$2" ;;
    esac
    ;;
  step)
    n="$1"; state="$2"; note="${3:-}"
    key="$(grep -o "^STEP_${n}_[A-Z]*" "$path" | head -1)"
    [ -n "$key" ] || { echo "no step $n" >&2; exit 1; }
    set_kv "$key" "$state"
    if [ -n "$note" ]; then set_kv "LAST_NOTE" "[step $n $state] $note"; fi
    ;;
  next)
    for n in 1 2 3 4 5 6 7 8 9; do
      s="$(grep "^STEP_${n}_" "$path" | cut -d= -f2)"
      [ "$s" = "done" ] || { echo "$n"; exit 0; }
    done
    echo 10
    ;;
  status)
    printf '%-24s %s\n' "STEP" "STATE"
    grep '^STEP_' "$path" | sed 's/=/ /' | awk '{printf "%-24s %s\n", $1, $2}'
    n="$(get LAST_NOTE)"; if [ -n "$n" ]; then echo "note: $n"; fi
    ;;
  show)
    [ -f "$path" ] || { echo "missing: $path" >&2; exit 1; }
    # Secrets stay in the file: the output lands in the chat transcript.
    sed -E 's/^([A-Z_]*(PASSWORD|CRYPT_KEY))=.+$/\1=******** (in this file)/' "$path"
    ;;
  ignore) ignore_file; echo "ignored: $FILE" ;;
  write-env)
    f="${1:-}"; [ -n "$f" ] && [ $# -ge 2 ] || { echo "usage: write-env <dir> <file> NAME=VALUE|NAME=@KEY…" >&2; exit 1; }
    shift
    case "$f" in /*) ;; *) f="$dir/$f" ;; esac
    [ -f "$path" ] || { echo "missing: $path" >&2; exit 1; }
    touch "$f"; names=""
    for kv in "$@"; do
      case "$kv" in *=*) ;; *) echo "expected NAME=VALUE, got: $kv" >&2; exit 1 ;; esac
      k="${kv%%=*}"; v="${kv#*=}"
      case "$k" in ''|[0-9]*|*[!A-Za-z0-9_]*) echo "invalid name: $k" >&2; exit 1 ;; esac
      case "$v" in
        @*) src="${v#@}"
            case "$src" in ''|[0-9]*|*[!A-Za-z0-9_]*) echo "invalid ledger key: $src" >&2; exit 1 ;; esac
            grep -q "^$src=" "$path" || { echo "no ledger key: $src" >&2; exit 1; }
            v="$(get "$src")" ;;
      esac
      if grep -q "^$k=" "$f"; then
        tmp="$f.tmp.$$"
        while IFS= read -r line || [ -n "$line" ]; do
          case "$line" in "$k="*) printf '%s=%s\n' "$k" "$v" ;; *) printf '%s\n' "$line" ;; esac
        done < "$f" > "$tmp"
        cat "$tmp" > "$f"; rm -f "$tmp"   # rewrite in place: keeps the file's mode and any bind mount
      else
        if [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ]; then echo >> "$f"; fi
        printf '%s=%s\n' "$k" "$v" >> "$f"
      fi
      names="$names $k"
    done
    echo "wrote:$names → $f"
    ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
