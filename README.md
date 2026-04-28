# claude-code-daily-log

A cross-project, time-ordered memory layer for [Claude Code](https://claude.ai/code).

Claude Code already has per-project auto-memory, but it's siloed: notes from one working directory aren't visible in another. This adds the missing piece — a **single chronological log** that any session in any project can read at startup.

## What it does

Two pieces, both local, no cloud:

1. **Nightly digest** — a launchd job runs once a day, extracts your Claude Code session transcripts (using `jq`, no LLM in the cron), pipes them to `claude -p` for summarization, and appends a high-level dated entry to a markdown file (e.g. a note in your Obsidian vault).

2. **Session-start loader** — a `SessionStart` hook injects the recent ~14 days from the log, plus a raw extract of "today so far" from any sessions earlier today, as additional context whenever you open Claude Code in any directory.

The output looks like:

```markdown
## 2026-04-28

**TL;DR:** Set up an automated nightly digest that summarizes each day's Claude Code work into a daily log.

### home
Built a local launchd job that runs every evening, extracts the day's transcripts,
and appends a high-level digest to a markdown file — turning ephemeral session
history into durable cross-session memory.
↪ Next: consider adding a global keyword index once the log spans a few months.
```

The `↪ Next:` line only appears when there's a genuine open thread.

## Why "cron-safe"?

Most published Claude Code memory tools either run an autonomous Claude agent in cron (requiring `--dangerously-skip-permissions`) or call out to a hosted service. This project deliberately uses `jq` for the deterministic data extraction step, then sends the cleaned text to a single non-tool-using `claude -p` call. No flag risk, no network dependency beyond Claude itself, no agent loops on a timer.

## Install

Requires macOS (launchd), [Claude Code](https://claude.ai/code), and `jq` (`brew install jq`).

```bash
git clone https://github.com/YOUR_USER/claude-code-daily-log.git
cd claude-code-daily-log
./install.sh
```

You'll be prompted for:
- **Log file path** — where to append entries (typically a note in your Obsidian vault)
- **Hour** — what time of day to run the digest (24h local time, default 21)

The installer writes config to `~/.config/claude-code-daily-log/config.sh`, generates and loads a launchd plist, and prints a snippet to paste into `~/.claude/settings.json` for the SessionStart hook.

## Configuration

All settings live in `~/.config/claude-code-daily-log/config.sh`. Override any of:

| Var | Default | Purpose |
|---|---|---|
| `CCDL_LOG_FILE` | (required) | Path to the markdown file to append to |
| `CCDL_PROJECTS_DIR` | `~/.claude/projects` | Where Claude Code stores transcripts |
| `CCDL_CLAUDE_BIN` | `claude` (on PATH) | Path to the Claude Code binary |
| `CCDL_JQ_BIN` | `/usr/bin/jq` | Path to jq |
| `CCDL_MAX_DAYS` | `14` | Days of history loaded at session start |
| `CCDL_MAX_LOG_BYTES` | `30000` | Cap on log content injected per session |
| `CCDL_MAX_TODAY_BYTES` | `10000` | Cap on "today so far" content injected per session |
| `CCDL_DIGEST_BYTES` | `500000` | Cap on digest material sent to `claude -p` nightly |

See `config.example.sh` for a copy-pasteable template.

## How it works

```
┌─────────────────────────────────┐         ┌──────────────────────────┐
│  Claude Code sessions           │         │  Your Obsidian vault     │
│  (~/.claude/projects/*.jsonl)   │         │  (or any markdown file)  │
└──────────────┬──────────────────┘         └────────────▲─────────────┘
               │                                          │
               │ jq extracts user prompts +               │ append
               │ tool actions per session                 │
               ▼                                          │
       ┌──────────────────┐         ┌──────────────────┐  │
       │  daily-log.sh    │────────▶│  claude -p       │──┘
       │  (launchd, 9pm)  │ digest  │  summarizes      │
       └──────────────────┘         └──────────────────┘

       ┌────────────────────────┐
       │  load-daily-log.sh     │  ──── injects via hookSpecificOutput
       │  (SessionStart hook)   │       at the start of every session
       └────────────────────────┘
```

The cron-safe split: deterministic extraction in shell, summarization in `claude -p` with `--allowed-tools ""` so the model can't call tools (and therefore can't hang on a permission prompt).

## Manual usage

Run the daily writer on demand:
```bash
~/claude-code-daily-log/bin/daily-log.sh
```

Test what the loader injects:
```bash
~/claude-code-daily-log/bin/load-daily-log.sh | jq -r '.hookSpecificOutput.additionalContext'
```

## Uninstall

```bash
./uninstall.sh
```

Then remove the SessionStart hook from `~/.claude/settings.json` and (optionally) delete the log file.

## Linux

The installer is macOS-only because it generates a launchd plist. The scripts themselves work fine under bash/zsh on Linux. To run on Linux:

1. Manually source `bin/daily-log.sh` from cron or a systemd timer at your preferred hour.
2. Manually add the SessionStart hook block to `~/.claude/settings.json`.

PRs welcome for a Linux installer path.

## License

MIT
