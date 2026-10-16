#!/usr/bin/env bash
# Prepares the optional media archive for /magekwik-magento:local-setup step 7. The user places it
# under <dir>/.magento-local/ and names it in MEDIA_ARCHIVE in .magento-local.env — nothing is ever
# fetched from a live store. Accepts .tar.gz/.tgz/.tar/.zip or a folder, whose contents are pub/media
# itself or wrapped in one media/ or pub/media/ folder.
# Usage:
#   local-setup-media.sh <dir> --check          validate only; print "media: <n> files"
#   local-setup-media.sh <dir> --stream         write a normalised tar of pub/media to stdout, for
#                                               `… | <tool> exec -T <php> tar -xf - -C pub/media`
#   local-setup-media.sh <dir> --into <path>    copy into <path> on the host (Valet: <code>/pub/media)
# Refuses absolute paths, `..` entries, links, and archives outside <dir>/.magento-local/. Exit 1 on refusal.
set -euo pipefail

dir="${1:?usage: local-setup-media.sh <dir> --check|--stream|--into <path>}"; mode="${2:-}"; into="${3:-}"
die() { echo "media: $*" >&2; exit 1; }
case "$mode" in --check|--stream) ;; --into) [ -n "$into" ] || die "--into needs a path" ;; *) die "unknown mode: $mode" ;; esac

ledger="$dir/.magento-local.env"
[ -f "$ledger" ] || die "no ledger at $ledger"
rel="$(sed -n 's/^MEDIA_ARCHIVE=//p' "$ledger" | head -1)"
[ -n "$rel" ] || die "MEDIA_ARCHIVE is empty in the ledger"

base="$(cd "$dir" && pwd)/.magento-local"
case "$rel" in /*) src="$rel" ;; *) src="$(cd "$dir" && pwd)/$rel" ;; esac
[ -e "$src" ] || die "not found: $src"
# Resolve symlinks/.. in the path itself, then require it to sit inside .magento-local/.
src_real="$(cd "$(dirname "$src")" && pwd -P)/$(basename "$src")"
base_real="$(cd "$base" 2>/dev/null && pwd -P)" || die "no .magento-local/ folder in $dir"
case "$src_real" in "$base_real"/*) ;; *) die "MEDIA_ARCHIVE must be inside $base/ (got $src)" ;; esac

unsafe() { grep -E '(^/|(^|/)\.\.(/|$))' >/dev/null; }

tmp="$(mktemp -d "$base_real/.media.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
if [ -d "$src_real" ]; then
  cp -R "$src_real/." "$tmp/"
else
  case "$src_real" in
    *.tar.gz|*.tgz|*.tar)
      if tar -tf "$src_real" | unsafe; then die "archive has absolute or .. paths: $src_real"; fi
      tar -xf "$src_real" -C "$tmp" ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || die "unzip is not installed"
      if unzip -Z1 "$src_real" | unsafe; then die "archive has absolute or .. paths: $src_real"; fi
      unzip -q "$src_real" -d "$tmp" ;;
    *) die "unsupported type (use .tar.gz, .tgz, .tar, .zip or a folder): $src_real" ;;
  esac
fi
[ -z "$(find "$tmp" -type l -print -quit)" ] || die "archive contains links; refusing"

# Unwrap one media/ or pub/media/ folder when it is the only thing at the top.
root="$tmp"
only="$(ls -A "$root")"
if [ "$only" = "pub" ] && [ -d "$root/pub/media" ] && [ "$(ls -A "$root/pub")" = "media" ]; then root="$root/pub/media"
elif [ "$only" = "media" ] && [ -d "$root/media" ]; then root="$root/media"; fi

n="$(find "$root" -type f | wc -l | tr -d ' ')"
[ "$n" -gt 0 ] || die "no files in $src_real"

case "$mode" in
  --check)  echo "media: $n files" ;;
  --stream) COPYFILE_DISABLE=1 tar -C "$root" -cf - . ;;   # no macOS ._* metadata files
  --into)   mkdir -p "$into"; cp -R "$root/." "$into/"; echo "media: $n files copied to $into" ;;
esac
