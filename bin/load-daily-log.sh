#!/bin/zsh
# claude-code-daily-log: SessionStart loader
# Outputs a JSON hook payload that injects four sections of cross-session context:
#   1. Recent days from the daily log
#   2. Historical entries for the current project (if any)
#   3. Today so far (raw extract from today's session JSONLs)
#   4. Open threads (the ↪ Next: lines tracked across days)

set -euo pipefail

CONFIG="${CCDL_CONFIG:-$HOME/.config/claude-code-daily-log/config.sh}"
[ -f "$CONFIG" ] && source "$CONFIG"

LOG_FILE="${CCDL_LOG_FILE:-}"
THREADS_FILE="${CCDL_THREADS_FILE:-}"
PROJECTS_DIR="${CCDL_PROJECTS_DIR:-$HOME/.claude/projects}"
JQ="${CCDL_JQ_BIN:-/usr/bin/jq}"
MAX_DAYS="${CCDL_MAX_DAYS:-14}"
MAX_LOG_BYTES="${CCDL_MAX_LOG_BYTES:-30000}"
MAX_TODAY_BYTES="${CCDL_MAX_TODAY_BYTES:-10000}"
MAX_PROJECT_BYTES="${CCDL_MAX_PROJECT_BYTES:-15000}"

DATE_TODAY=$(date +%Y-%m-%d)

if [ -z "$THREADS_FILE" ] && [ -n "$LOG_FILE" ]; then
  THREADS_FILE="$(dirname "$LOG_FILE")/Claude Code Open Threads.md"
fi

# --- Section 1: Recent days from the daily log ---
LOG_SECTION=""
if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
  HEADERS=$(grep -n '^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$' "$LOG_FILE" 2>/dev/null | cut -d: -f1 || true)
  COUNT=$(printf '%s\n' "$HEADERS" | grep -c . || true)

  if [ "${COUNT:-0}" -le "$MAX_DAYS" ]; then
    LOG_CONTENT=$(cat "$LOG_FILE")
  else
    START=$(printf '%s\n' "$HEADERS" | tail -n "$MAX_DAYS" | head -n 1)
    LOG_CONTENT=$(tail -n +"$START" "$LOG_FILE")
  fi
  LOG_CONTENT=$(printf '%s' "$LOG_CONTENT" | head -c "$MAX_LOG_BYTES")

  if [ -n "$LOG_CONTENT" ]; then
    LOG_SECTION="## Recent days (from the daily log)

${LOG_CONTENT}"
  fi
fi

# --- Section 2: Historical entries for current project ---
PROJECT_SECTION=""
CURRENT_PROJECT=$(basename "$PWD" 2>/dev/null || echo "")
if [ -n "$CURRENT_PROJECT" ] && [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
  PROJECT_HISTORY=$(awk -v target="$CURRENT_PROJECT" '
    BEGIN { in_proj = 0; current_date = ""; printed_date = "" }
    /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ {
      current_date = $0
      in_proj = 0
      next
    }
    /^### / {
      proj = substr($0, 5)
      sub(/[[:space:]]+$/, "", proj)
      if (proj == target) {
        in_proj = 1
        if (current_date != printed_date) {
          if (printed_date != "") print ""
          print current_date
          print ""
          printed_date = current_date
        }
        print $0
        next
      } else {
        in_proj = 0
      }
    }
    /^## / { in_proj = 0 }
    in_proj { print }
  ' "$LOG_FILE")

  if [ -n "$PROJECT_HISTORY" ]; then
    PROJECT_HISTORY=$(printf '%s' "$PROJECT_HISTORY" | head -c "$MAX_PROJECT_BYTES")
    PROJECT_SECTION="## All historical entries for this project (\"${CURRENT_PROJECT}\")
${PROJECT_HISTORY}"
  fi
fi

# --- Section 3: Today so far (raw extract from today's session JSONLs) ---
TODAY_SECTION=""
if [ -d "$PROJECTS_DIR" ]; then
  TODAY_FILES=$(find "$PROJECTS_DIR" -name "*.jsonl" -type f -newermt "today 00:00" ! -newermt "tomorrow 00:00" 2>/dev/null | sort || true)

  if [ -n "$TODAY_FILES" ]; then
    TODAY_TMP=$(mktemp -t ccdl-today)
    trap 'rm -f "$TODAY_TMP"' EXIT

    current_project=""
    while IFS= read -r session_file; do
      [ -z "$session_file" ] && continue

      extracted=$("$JQ" -r --arg today "$DATE_TODAY" '
        select((.type == "user" or .type == "assistant") and ((.timestamp // "") | startswith($today))) |
        if .type == "user" then
          (.message.content
            | if type == "string" then .
              elif type == "array" then (map(.text? // empty) | join(" "))
              else "" end
            | gsub("\\s+"; " ")
          ) as $text |
          if ($text | length) == 0 or ($text | length) > 800 then empty
          else "• " + ($text | .[0:240])
          end
        else
          (.message.content // []
            | map(select(.type == "tool_use") | .name)
            | unique
            | join(", ")
          ) as $tools |
          if ($tools | length) == 0 then empty else "  ↳ " + $tools end
        end
      ' "$session_file" 2>/dev/null || true)

      if [ -n "$extracted" ]; then
        project_name=$(basename "$(dirname "$session_file")")
        if [ "$project_name" != "$current_project" ]; then
          printf '\n### %s\n' "$project_name" >> "$TODAY_TMP"
          current_project="$project_name"
        fi
        printf '%s\n' "$extracted" >> "$TODAY_TMP"
      fi
    done <<< "$TODAY_FILES"

    if [ -s "$TODAY_TMP" ]; then
      TODAY_CONTENT=$(head -c "$MAX_TODAY_BYTES" "$TODAY_TMP")
      TODAY_SECTION="## Today so far (live extract from today's sessions, not yet in the daily log)
Project dirs are encoded paths — slashes become dashes (e.g. '-Users-name-myproject' = /Users/name/myproject).
${TODAY_CONTENT}"
    fi
  fi
fi

# --- Section 4: Open threads ---
THREADS_SECTION=""
if [ -n "$THREADS_FILE" ] && [ -f "$THREADS_FILE" ]; then
  OPEN_LIST=$(awk '/^- \[ \] /' "$THREADS_FILE" || true)
  if [ -n "$OPEN_LIST" ]; then
    OPEN_COUNT=$(printf '%s\n' "$OPEN_LIST" | grep -c . || echo 0)
    THREADS_SECTION="## Open threads (${OPEN_COUNT} total — auto-tracked from past ↪ Next: lines, oldest first)
${OPEN_LIST}"
  fi
fi

# --- Combine and emit ---
if [ -z "$LOG_SECTION" ] && [ -z "$PROJECT_SECTION" ] && [ -z "$TODAY_SECTION" ] && [ -z "$THREADS_SECTION" ]; then
  exit 0
fi

CTX="Cross-session memory from your Claude Code work history."
[ -n "$PROJECT_SECTION" ] && CTX="${CTX}

${PROJECT_SECTION}"
[ -n "$LOG_SECTION" ] && CTX="${CTX}

${LOG_SECTION}"
[ -n "$TODAY_SECTION" ] && CTX="${CTX}

${TODAY_SECTION}"
[ -n "$THREADS_SECTION" ] && CTX="${CTX}

${THREADS_SECTION}"

"$JQ" -n --arg ctx "$CTX" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
