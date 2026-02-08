#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/assets/app_icon_source.png}"
OUT_ICNS="${2:-$ROOT/assets/AppIcon.icns}"
WORK="$ROOT/build/icon"
ICONSET="$WORK/AppIcon.iconset"

if [[ ! -f "$SRC" ]]; then
  echo "Icon source not found: $SRC" >&2
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$ICONSET"

make_size() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
}

make_size 16 icon_16x16.png
make_size 32 icon_16x16@2x.png
make_size 32 icon_32x32.png
make_size 64 icon_32x32@2x.png
make_size 128 icon_128x128.png
make_size 256 icon_128x128@2x.png
make_size 256 icon_256x256.png
make_size 512 icon_256x256@2x.png
make_size 512 icon_512x512.png
make_size 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
echo "Generated icon: $OUT_ICNS"
