#!/bin/sh
# Builds release/PhyzanCapital-<version>.zip with only the files players need.
# Usage: sh tools/build_release.sh [outdir]   (run from anywhere; default outdir /workspace/release)
set -eu
SRC=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-/workspace/release}
VER=$(sed -n 's/^## Version: *//p' "$SRC/PhyzanCapital.toc" | tr -d '\r')
CORE=$(sed -n 's/^ns.VERSION = "\(.*\)".*/\1/p' "$SRC/Core.lua")
[ "$VER" = "$CORE" ] || { echo "toc version $VER != Core.lua $CORE"; exit 1; }
grep -q "^## $VER\$" "$SRC/CHANGELOG.md" || { echo "CHANGELOG.md has no ## $VER"; exit 1; }
STAGE=$(mktemp -d); DST="$STAGE/PhyzanCapital"; mkdir -p "$DST/Data"
cp "$SRC/PhyzanCapital.toc" "$SRC/LICENSE" "$SRC/CHANGELOG.md" "$SRC/README.md" "$SRC/THIRD_PARTY_NOTICES.md" "$DST/"
# every file the toc loads (backslash paths), nothing else
grep -v '^#' "$SRC/PhyzanCapital.toc" | tr -d '\r' | sed '/^ *$/d' | tr '\\' '/' | while read -r f; do
  [ -f "$SRC/$f" ] || { echo "missing $f"; exit 1; }
  cp "$SRC/$f" "$DST/$f"
done
ZIP="$OUT/PhyzanCapital-$VER.zip"
mkdir -p "$OUT"; rm -f "$ZIP"
(cd "$STAGE" && zip -qrX "$ZIP" PhyzanCapital)
rm -rf "$STAGE"
# checks
BAD=$(unzip -Z1 "$ZIP" | grep -Ei '(^|/)(tools/|\.luacheckrc|DEVELOPMENT\.md|.*backup.*|.*\.zip$|.*\.py$|test)' || true)
[ -z "$BAD" ] || { echo "dev files in release: $BAD"; exit 1; }
TOP=$(unzip -Z1 "$ZIP" | cut -d/ -f1 | sort -u)
[ "$TOP" = "PhyzanCapital" ] || { echo "top-level folders: $TOP"; exit 1; }
echo "built $ZIP ($(unzip -Z1 "$ZIP" | grep -vc '/$') files, $(wc -c < "$ZIP") bytes)"
