#!/bin/zsh
# claude-code-daily-log: installer
# - Writes a config file from a vault path you provide
# - Generates and loads a launchd job for the nightly digest
# - Prints the SessionStart hook snippet to add to ~/.claude/settings.json

set -euo pipefail

REPO_DIR="${0:A:h}"
CONFIG_DIR="$HOME/.config/claude-code-daily-log"
CONFIG_FILE="$CONFIG_DIR/config.sh"
PLIST_LABEL="dev.local.claude-code-daily-log"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

if [ "$(uname)" != "Darwin" ]; then
  echo "⚠️  This installer is macOS-only (uses launchd). For Linux, use cron or systemd:"
  echo "   - Run $REPO_DIR/bin/daily-log.sh once a day from cron/systemd"
  echo "   - Add the SessionStart hook to ~/.claude/settings.json manually"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "✗ \`claude\` not found on PATH. Install Claude Code first: https://claude.ai/code"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1 && [ ! -x /usr/bin/jq ]; then
  echo "✗ \`jq\` not found. Install with: brew install jq"
  exit 1
fi

# --- Prompt for config ---
echo "claude-code-daily-log setup"
echo

DEFAULT_LOG="$HOME/Documents/Obsidian Vault/Claude Code Daily Log.md"
echo "Path to the markdown file to append daily entries to."
echo "Default: $DEFAULT_LOG"
read -r "log_file?Log file path: "
LOG_FILE="${log_file:-$DEFAULT_LOG}"

DEFAULT_HOUR=21
echo
echo "Hour (24h, local time) to run the nightly digest."
echo "Default: $DEFAULT_HOUR (9pm)"
read -r "hour?Hour: "
HOUR="${hour:-$DEFAULT_HOUR}"

if ! [[ "$HOUR" =~ ^[0-9]+$ ]] || [ "$HOUR" -lt 0 ] || [ "$HOUR" -gt 23 ]; then
  echo "✗ Hour must be 0-23. Got: $HOUR"
  exit 1
fi

CLAUDE_BIN=$(command -v claude)
JQ_BIN=$(command -v jq 2>/dev/null || echo /usr/bin/jq)

# --- Write config ---
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<EOF
# claude-code-daily-log config — generated $(date)
CCDL_LOG_FILE="$LOG_FILE"
CCDL_CLAUDE_BIN="$CLAUDE_BIN"
CCDL_JQ_BIN="$JQ_BIN"
EOF
echo "✓ Wrote $CONFIG_FILE"

# --- Make scripts executable ---
chmod +x "$REPO_DIR/bin/daily-log.sh" "$REPO_DIR/bin/load-daily-log.sh"

# --- Generate and load launchd plist ---
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>${REPO_DIR}/bin/daily-log.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${HOUR}</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/.claude/claude-code-daily-log.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.claude/claude-code-daily-log.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname "$CLAUDE_BIN"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
</dict>
</plist>
EOF
echo "✓ Wrote $PLIST_PATH"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
echo "✓ Loaded launchd job (will run daily at ${HOUR}:00 local time)"

# --- Print hook snippet ---
HOOK_CMD="$REPO_DIR/bin/load-daily-log.sh"
echo
echo "──────────────────────────────────────────────────────────────"
echo "FINAL STEP — add this to ~/.claude/settings.json:"
echo "──────────────────────────────────────────────────────────────"
cat <<EOF

  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD",
            "timeout": 10
          }
        ]
      }
    ]
  }
EOF
echo
echo "(If you already have a 'hooks' object, merge the SessionStart entry."
echo " If you already have a SessionStart hook, add this object alongside it.)"
echo
echo "Done. Test the loader anytime with:"
echo "  $HOOK_CMD | jq ."
echo
echo "Test the daily writer anytime with:"
echo "  $REPO_DIR/bin/daily-log.sh"
