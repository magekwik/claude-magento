#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/plugins/magento/scripts/local-setup-media.sh"
E="$ROOT/plugins/magento/scripts/local-setup-env.sh"
tmp=$(mktemp -d)

shells="bash"
[ -x /bin/bash ] && shells="bash /bin/bash"

# A target with a ledger, and a media tree: catalog/product/a.jpg + wysiwyg/b.png
mkmedia() { mkdir -p "$1/catalog/product" "$1/wysiwyg"; printf 'jpg' > "$1/catalog/product/a.jpg"; printf 'png' > "$1/wysiwyg/b.png"; }

for sh in $shells; do
  t="$tmp/$(echo "$sh" | tr -c 'a-z0-9' '_')"
  mkdir -p "$t/d/.magento-local" "$t/src"
  bash "$E" init "$t/d" > /dev/null
  mkmedia "$t/src/plain"
  mkmedia "$t/src/wrapped/media"
  mkmedia "$t/src/pubwrapped/pub/media"
  L="$t/d/.magento-local"

  # A. plain .tar.gz → check counts, --into copies, --stream round-trips
  (cd "$t/src/plain" && COPYFILE_DISABLE=1 tar -czf "$L/m.tar.gz" .)
  bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/m.tar.gz
  assert_eq "$($sh "$S" "$t/d" --check)" "media: 2 files" "$sh A check counts files"
  $sh "$S" "$t/d" --into "$t/out-a" > /dev/null
  assert_eq "$(cat "$t/out-a/catalog/product/a.jpg")" "jpg" "$sh A --into copies"
  mkdir "$t/out-s" && $sh "$S" "$t/d" --stream | tar -xf - -C "$t/out-s"
  assert_eq "$(cat "$t/out-s/wysiwyg/b.png")" "png" "$sh A --stream round-trips"
  assert_eq "$(find "$t/out-s" -name '._*' | wc -l | tr -d ' ')" "0" "$sh A no macOS metadata files"
  assert_eq "$(find "$L" -name '.media.*' | wc -l | tr -d ' ')" "0" "$sh A temp dir cleaned"

  # B. wrapped in media/ and in pub/media/ → unwrapped
  (cd "$t/src/wrapped" && tar -cf "$L/w.tar" media)
  bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/w.tar
  $sh "$S" "$t/d" --into "$t/out-b" > /dev/null
  assert_eq "$([ -f "$t/out-b/catalog/product/a.jpg" ] && echo yes || echo no)" "yes" "$sh B media/ unwrapped"
  (cd "$t/src/pubwrapped" && tar -czf "$L/p.tgz" pub)
  bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/p.tgz
  $sh "$S" "$t/d" --into "$t/out-p" > /dev/null
  assert_eq "$([ -f "$t/out-p/wysiwyg/b.png" ] && echo yes || echo no)" "yes" "$sh B pub/media/ unwrapped"

  # C. .zip and a folder
  if command -v zip >/dev/null 2>&1; then
    (cd "$t/src/plain" && zip -qr "$L/z.zip" .)
    bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/z.zip
    assert_eq "$($sh "$S" "$t/d" --check)" "media: 2 files" "$sh C zip"
  fi
  cp -R "$t/src/wrapped" "$L/folder"
  bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/folder
  assert_eq "$($sh "$S" "$t/d" --check)" "media: 2 files" "$sh C folder"

  # D. refusals: outside .magento-local, .. entries, absolute entries, links, empty, missing, bad type
  (cd "$t/src/plain" && tar -czf "$t/outside.tar.gz" .)
  bash "$E" set "$t/d" MEDIA_ARCHIVE "$t/outside.tar.gz"
  $sh "$S" "$t/d" --check > /dev/null 2>&1; assert_eq "$?" "1" "$sh D outside .magento-local refused"
  bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/../../outside.tar.gz
  $sh "$S" "$t/d" --check > /dev/null 2>&1; assert_eq "$?" "1" "$sh D .. in MEDIA_ARCHIVE refused"
  python3 - "$L/dots.tar" "$L/abs.tar" <<'PY'
import io, sys, tarfile
for path, name in ((sys.argv[1], "../escape.txt"), (sys.argv[2], "/tmp/abs.txt")):
    with tarfile.open(path, "w") as t:
        i = tarfile.TarInfo(name); i.size = 1; t.addfile(i, io.BytesIO(b"x"))
PY
  bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/dots.tar
  $sh "$S" "$t/d" --check > "$t/dots.out" 2>&1; assert_eq "$?" "1" "$sh D .. entry refused"
  assert_contains "$t/dots.out" "absolute or \.\. paths" "$sh D .. entry message"
  assert_eq "$([ -e "$t/escape.txt" ] || [ -e "$t/d/escape.txt" ] && echo yes || echo no)" "no" "$sh D nothing escaped"
  bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/abs.tar
  $sh "$S" "$t/d" --check > /dev/null 2>&1; assert_eq "$?" "1" "$sh D absolute entry refused"
  mkdir -p "$t/src/link" && ln -s /etc/hosts "$t/src/link/hosts" && (cd "$t/src/link" && tar -cf "$L/link.tar" .)
  bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/link.tar
  $sh "$S" "$t/d" --check > "$t/link.out" 2>&1; assert_eq "$?" "1" "$sh D link refused"
  assert_contains "$t/link.out" "contains links" "$sh D link message"
  mkdir -p "$L/empty"; bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/empty
  $sh "$S" "$t/d" --check > /dev/null 2>&1; assert_eq "$?" "1" "$sh D empty refused"
  bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/nope.tar.gz
  $sh "$S" "$t/d" --check > /dev/null 2>&1; assert_eq "$?" "1" "$sh D missing refused"
  printf 'x' > "$L/m.rar"; bash "$E" set "$t/d" MEDIA_ARCHIVE .magento-local/m.rar
  $sh "$S" "$t/d" --check > /dev/null 2>&1; assert_eq "$?" "1" "$sh D unsupported type refused"
  bash "$E" set "$t/d" MEDIA_ARCHIVE ""
  $sh "$S" "$t/d" --check > /dev/null 2>&1; assert_eq "$?" "1" "$sh D unset MEDIA_ARCHIVE refused"
done

rm -rf "$tmp"
report
