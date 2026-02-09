#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FlashASR"
VERSION="${VERSION:-5.1.0}"
DIST="$ROOT/dist"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION-macos.zip"
DMG="$DIST/$APP_NAME-$VERSION-macos.dmg"

mkdir -p "$DIST"

"$ROOT/scripts/build_app.sh"

rm -f "$ZIP" "$DMG"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

echo "Package created:"
echo "  $ZIP"
echo "  $DMG"
