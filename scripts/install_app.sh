#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FlashASR"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"
AGENT_ID="com.flashasr.agent"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/$AGENT_ID.plist"

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

mkdir -p "$AGENT_DIR"
cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$AGENT_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>$TARGET_APP/Contents/MacOS/$APP_NAME</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/$APP_NAME.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/$APP_NAME.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID/$AGENT_ID" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$AGENT_PLIST"
launchctl kickstart -k "gui/$UID/$AGENT_ID" >/dev/null 2>&1 || true

echo "Installed app: $TARGET_APP"
echo "LaunchAgent: $AGENT_PLIST"
echo "Log file: $HOME/Library/Logs/$APP_NAME.log"
