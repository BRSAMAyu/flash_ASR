#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FlashASR"
AGENT_ID="com.flashasr.agent"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_ID.plist"

launchctl bootout "gui/$UID/$AGENT_ID" >/dev/null 2>&1 || true
rm -f "$AGENT_PLIST"
rm -rf "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"

echo "Uninstalled $APP_NAME and disabled auto-start agent."
