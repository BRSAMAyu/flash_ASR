#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FlashASR"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"

"$ROOT/scripts/build_app.sh"

TARGET_APP="/Applications/$APP_NAME.app"
if mkdir -p /Applications >/dev/null 2>&1; then
  rm -rf "$TARGET_APP"
fi

if ! mkdir -p /Applications >/dev/null 2>&1 || ! cp -R "$APP_BUNDLE" "$TARGET_APP" 2>/dev/null; then
  mkdir -p "$HOME/Applications"
  TARGET_APP="$HOME/Applications/$APP_NAME.app"
  rm -rf "$TARGET_APP"
  cp -R "$APP_BUNDLE" "$TARGET_APP"
fi

# Remove old LaunchAgent if it exists (v1 used LaunchAgent, v2 uses SMAppService)
AGENT_ID="com.flashasr.agent"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_ID.plist"
if [[ -f "$AGENT_PLIST" ]]; then
  launchctl bootout "gui/$UID/$AGENT_ID" >/dev/null 2>&1 || true
  rm -f "$AGENT_PLIST"
  echo "Removed old LaunchAgent (v2 uses Settings > Launch at Login instead)"
fi

echo "Installed app: $TARGET_APP"
echo "Launch FlashASR from Applications or enable 'Launch at Login' in Settings."

# Open the app
open "$TARGET_APP"
