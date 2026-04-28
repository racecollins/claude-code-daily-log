# claude-code-daily-log configuration
# Copied to ~/.config/claude-code-daily-log/config.sh by install.sh.
# All values are optional except CCDL_LOG_FILE.

# REQUIRED: full path to the markdown file to append daily entries to.
# Common choice: a note in your Obsidian vault.
# CCDL_LOG_FILE="$HOME/Documents/Obsidian Vault/MyVault/Claude Code Daily Log.md"

# Optional: path to the open-threads file (auto-tracked from ↪ Next: lines).
# Defaults to "Claude Code Open Threads.md" next to CCDL_LOG_FILE.
# CCDL_THREADS_FILE="$HOME/Documents/Obsidian Vault/MyVault/Claude Code Open Threads.md"

# Where Claude Code stores session transcripts (rarely needs changing).
# CCDL_PROJECTS_DIR="$HOME/.claude/projects"

# Path to the claude binary. Leave unset to find on PATH.
# CCDL_CLAUDE_BIN="claude"

# Path to jq. macOS default works out of the box.
# CCDL_JQ_BIN="/usr/bin/jq"

# How many recent days the SessionStart loader injects (default 14).
# CCDL_MAX_DAYS=14

# Hard cap on bytes injected from the daily log (default 30000).
# CCDL_MAX_LOG_BYTES=30000

# Hard cap on bytes injected from today-so-far raw extract (default 10000).
# CCDL_MAX_TODAY_BYTES=10000

# Hard cap on bytes injected from per-project history section (default 15000).
# CCDL_MAX_PROJECT_BYTES=15000

# Hard cap on bytes of digest material sent to claude -p in the nightly job
# (default 500000 — 500KB. Most days are well under this).
# CCDL_DIGEST_BYTES=500000
