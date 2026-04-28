# claude-code-daily-log

A cross-project, time-ordered memory layer for [Claude Code](https://claude.ai/code).

Claude Code already has per-project auto-memory, but it's siloed: notes from one working directory aren't visible in another. This adds the missing piece — a **single chronological log** that any session in any project can read at startup.

## Why this exists

Claude Code (the CLI) doesn't currently link your sessions across projects the way Claude.ai does in the browser. Each working directory gets its own per-project memory, but that memory is "who you are and how you work in this codebase" — not "what you actually did and when."

So if you spent the morning in `project-a/` working on a bug fix, then opened a session in `project-b/` in the afternoon, the second session has no idea the first one happened. You're constantly re-explaining context Claude already knew an hour ago.

This tool fills that gap with a deliberately simple model: **one chronological log file, summarized once a day, auto-loaded into every new session.** No cloud, no embeddings, no separate database — just a markdown file and two shell scripts.

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

## What you can do once it's installed

Concrete things this enables that aren't possible with vanilla Claude Code:

- **Cross-project continuity.** Work on Project A in the morning, switch to Project B in the afternoon — Claude in B already knows what happened in A.
- **Pickup-where-you-left-off, even days later.** Open a new session a week after touching a project and Claude has the recent context immediately, without you re-briefing.
- **Ask Claude about your own history.** "When did we last touch the chess game?", "What did I ship in April?", "What's still open on the auth refactor?" — Claude can answer from your log.
- **Spot patterns over time.** Recurring blockers, projects that keep stalling, areas that consume most of your time become visible at a glance.
- **Daily/weekly self-review.** Read the log directly to remember what you accomplished. No more "what did I even do this week?"
- **Standup / handoff prep.** A glanceable record of what you've been working on, ready to share with a teammate or paste into a status update.
- **Carry context across machines.** If your log lives in Obsidian (or any synced markdown), open Claude Code on your laptop and your desktop both see the same history.

The `↪ Next:` line is the highest-signal bit for cross-session work — it captures "the one open thread you'd want future-you to remember" — and it's only added when there's actually one to flag.

## Works great with Obsidian (but doesn't require it)

The log is just a markdown file at any path you choose. **Obsidian is recommended but optional** — the scripts don't depend on it.

Why Obsidian works well here:
- The single-file format lines up perfectly with Obsidian's markdown-first model
- Obsidian's full-text search across the vault makes the log instantly browsable
- You can [[link]] log entries to other notes (project pages, journals, etc.)
- Daily-notes plugin users can cross-reference the log with their own journaling
- Vault sync gets you cross-machine context for free

If you don't use Obsidian, point `CCDL_LOG_FILE` at any markdown file you'd browse with another editor — VS Code, Bear, Notion (via export), or just `cat`/`less`. Everything still works.

## Why "cron-safe"?

Most published Claude Code memory tools either run an autonomous Claude agent in cron (requiring `--dangerously-skip-permissions`) or call out to a hosted service. This project deliberately uses `jq` for the deterministic data extraction step, then sends the cleaned text to a single non-tool-using `claude -p` call. No flag risk, no network dependency beyond Claude itself, no agent loops on a timer.

## Install

Requires macOS (launchd), [Claude Code](https://claude.ai/code), and `jq` (`brew install jq`).

```bash
git clone https://github.com/racecollins/claude-code-daily-log.git
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
