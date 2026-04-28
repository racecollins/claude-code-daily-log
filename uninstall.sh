#!/bin/zsh
# claude-code-daily-log: uninstaller
set -euo pipefail

PLIST_LABEL="dev.local.claude-code-daily-log"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
CONFIG_DIR="$HOME/.config/claude-code-daily-log"

if [ "$(uname)" = "Darwin" ] && [ -f "$PLIST_PATH" ]; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  echo "✓ Removed launchd job"
fi

read -r "confirm?Also delete config at $CONFIG_DIR? [y/N]: "
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  rm -rf "$CONFIG_DIR"
  echo "✓ Removed config"
fi

echo
echo "MANUAL: remove the SessionStart hook from ~/.claude/settings.json if present."
echo "MANUAL: delete the daily log file itself if you no longer want it."
