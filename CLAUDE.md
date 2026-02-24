# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Critical Rules
- Always reply the user in Simplified Chinese.
- Any explaination or comments in code scripts should be in English.
- Default document language is Simplified Chinese. English version documents should have filenames ending with "_en".

## Project Overview

**cc-supervisor** enables OpenClaw Agent to supervise Claude Code through multi-turn interactive sessions with Hook-based event notification — replacing manual polling.

Architecture:
```
OpenClaw ── cc_send.sh (tmux send-keys) ──→ Claude Code (interactive, in tmux)
    ↑                                             │
    └───── openclaw send ←── on-cc-event.sh ←── Hooks (Stop/PostToolUse/Notification)

Human ── tmux attach -t cc-supervise ──→ observe/intervene anytime
```

See `PRD.md` for product goals, `EXECUTION_PLAN.md` for phased implementation.

## Directory Structure

```
cc-supervisor/
├── scripts/       # supervisor_run, cc_send, on-cc-event, install-hooks, cc-watchdog, cc_capture
├── config/        # claude-hooks.json template
├── logs/          # Runtime data (gitignored)
│   └── events.ndjson   # Append-only Hook event log
└── ref/           # Reference materials (gitignored)
```

## Key Scripts

| Script | Purpose |
|---|---|
| `scripts/supervisor_run.sh` | Creates/reuses tmux session `cc-supervise`, starts Claude Code in interactive mode |
| `scripts/cc_send.sh` | Sends text to Claude Code via `tmux send-keys` (text + Enter separated) |
| `scripts/cc_capture.sh` | Snapshots tmux pane recent output for diagnostics |
| `scripts/on-cc-event.sh` | Unified Hook callback: appends to `events.ndjson`, calls `openclaw send` for key events |
| `scripts/install-hooks.sh` | Merges Hook config into `~/.claude/settings.json` via `jq` deep merge |
| `scripts/cc-watchdog.sh` | Monitors `events.ndjson` freshness, sends timeout alert if no activity |

## Hook Event Types

| Event | Notification Strategy |
|---|---|
| `Stop` | **Notify** OpenClaw with response summary (Claude finished a response turn) |
| `PostToolUse` | Log only; **notify on error** |
| `Notification` | **Notify** OpenClaw |
| `SessionEnd` | **Notify** OpenClaw |

## tmux Conventions

- Session name: `cc-supervise`
- Human observes: `tmux attach -t cc-supervise`
- Scripts send commands: `tmux send-keys -t cc-supervise`

## Environment Variables

- `CC_PROJECT_DIR`: Absolute path to this project root. Set by `supervisor_run.sh`, inherited by Claude Code process, inherited by Hook callbacks. All scripts use this for absolute path resolution.

## Development Workflow

Phases: tmux + Send → Hook Pipeline → Robustness + Skill → Delivery.

Quick smoke test:
```bash
./scripts/install-hooks.sh
./scripts/supervisor_run.sh
./scripts/cc_send.sh "列出当前目录下的文件"
# Wait for response, then check:
cat logs/events.ndjson
```
