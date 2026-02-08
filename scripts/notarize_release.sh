#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FlashASR"
VERSION="${VERSION:-1.0.0}"
DIST="$ROOT/dist"
ZIP="$DIST/$APP_NAME-$VERSION-macos.zip"
PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$PROFILE" ]]; then
  echo "Set NOTARY_PROFILE (xcrun notarytool keychain profile name)." >&2
  exit 1
fi

if [[ ! -f "$ZIP" ]]; then
  echo "Zip not found: $ZIP" >&2
  exit 1
fi

xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$ROOT/build/$APP_NAME.app"

echo "Notarization complete and stapled: $ROOT/build/$APP_NAME.app"
