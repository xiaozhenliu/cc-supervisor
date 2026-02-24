# cc-supervisor

[![version](https://img.shields.io/badge/version-0.6.0-blue)](CHANGELOG.md)

**Hook-driven, zero-polling multi-turn supervision of Claude Code across any local project**

cc-supervisor is a **ClawHub Skill** — install once, then use the `@cc-supervisor` skill
to drive Claude Code through multi-turn tasks with zero tokens consumed while waiting.

---

## Quick Start

```bash
# ── Step 1: Install the skill (once per machine) ─────────────
# ClawHub install (available after publishing — not yet available):
# clawhub install cc-supervisor
# For now, install manually:
git clone <repo-url> ~/.openclaw/skills/cc-supervisor

# ── Step 2: Register hooks in the target project (once per project) ─
cc-install-hooks ~/Projects/my-app

# ── Step 3: Start supervision ────────────────────────────────
cc-supervise ~/Projects/my-app

# Send a task
cc-send "implement the login API"
```

> After Step 1, set up [Shell Aliases](#shell-aliases) so all commands simplify to the short forms shown above.
>
> Use `@cc-supervisor` in OpenClaw to drive the full supervision loop automatically.

---

## Architecture

```
OpenClaw ── cc_send.sh (tmux send-keys) ──→ Claude Code (tmux: cc-supervise)
    ↑                                               │
    │                                      Hook fires on event
    │                          (Stop / PostToolUse / Notification / SessionEnd)
    │                                               │
    └─── openclaw message send ←── on-cc-event.sh ──────────┘
                                  │
                     logs/events.ndjson  (append-only NDJSON)

Human ── tmux attach -t cc-supervise ──→ observe / intervene at any time
```

Key advantage: while waiting for Claude Code, OpenClaw consumes **zero tokens**
(event-driven, no polling).

### Two Supervision Modes

| Mode | Initiated by | Notification routing |
|------|-------------|---------------------|
| **Agent automatic** | OpenClaw Agent | Auto-injects `OPENCLAW_CHANNEL` / `OPENCLAW_TARGET` |
| **Human manual** | Human in terminal | `export OPENCLAW_CHANNEL=discord OPENCLAW_TARGET=<id>` |

---

## Prerequisites

| Tool | Install |
|------|---------|
| `tmux` | `brew install tmux` |
| `jq` | `brew install jq` |
| `claude` | Anthropic docs |
| `openclaw` | OpenClaw docs |

---

## One-Time Setup

### Install the Skill

**Current method (manual install):**

```bash
git clone <repo-url> ~/.openclaw/skills/cc-supervisor
```

> `clawhub install cc-supervisor` will be available after the skill is published to
> ClawHub — not yet available.

The skill lives at `~/.openclaw/skills/cc-supervisor/`. All scripts and config are under this directory.

### Shell Aliases

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# cc-supervisor install directory (change only this if you install elsewhere)
export CC_SUPERVISOR_HOME=~/.openclaw/skills/cc-supervisor

cc-supervise() {
  local target="${1:?Usage: cc-supervise <project-dir>}"
  CC_PROJECT_DIR="$CC_SUPERVISOR_HOME" \
  CLAUDE_WORKDIR="$target" \
    "$CC_SUPERVISOR_HOME/scripts/supervisor_run.sh"
}

cc-install-hooks() {
  local target="${1:?Usage: cc-install-hooks <project-dir>}"
  CC_PROJECT_DIR="$CC_SUPERVISOR_HOME" \
  CLAUDE_WORKDIR="$target" \
    "$CC_SUPERVISOR_HOME/scripts/install-hooks.sh"
}

cc-send() {
  "$CC_SUPERVISOR_HOME/scripts/cc_send.sh" "$@"
}

cc-capture() {
  "$CC_SUPERVISOR_HOME/scripts/cc_capture.sh" "$@"
}

cc-flush-queue() {
  "$CC_SUPERVISOR_HOME/scripts/flush-queue.sh"
}
```

Then reload: `source ~/.zshrc`

All examples below use these aliases.

> **Tip:** If you install to a non-standard path, only `CC_SUPERVISOR_HOME` needs updating.

---

## Registering Hooks in a Project

Run once for each project you want to supervise:

```bash
cc-install-hooks ~/Projects/my-app
```

Verify:

```bash
cat ~/Projects/my-app/.claude/settings.local.json | jq .hooks
```

> Hooks are written to the target project's `.claude/settings.local.json` (project-local,
> globally gitignored — not committed, does not affect other contributors).

---

## Usage

### Option A — Via OpenClaw Skill (recommended)

With the skill installed, OpenClaw drives everything automatically:

```
@cc-supervisor supervise ~/Projects/my-app: "implement the login API"
```

OpenClaw handles everything: start session → send prompt → wait for Hook notification →
multi-turn execution until complete.

### Option B — Manual Control

**Step 1 — Start the supervised session**

```bash
cc-supervise ~/Projects/my-app
```

Creates (or reuses) tmux session `cc-supervise`, starts Claude Code inside
`~/Projects/my-app`, and launches the watchdog daemon (default timeout: 30 minutes).

**Step 2 — Send a task prompt**

```bash
cc-send "implement the login API"
```

**Step 3 — Wait for Hook notification**

When Claude Code finishes a turn, `on-cc-event.sh` calls `openclaw message send` with a summary:

- **Task not done** → send the next prompt
- **Task complete** → end the loop
- **Error occurred** → analyze and send a correction prompt

**Observe / intervene at any time**

```bash
tmux attach -t cc-supervise
# Detach without closing: Ctrl-B, D
```

---

## Hook Events

| Event | Meaning | Notification strategy |
|-------|---------|----------------------|
| `Stop` | Claude Code finished a response turn | **Notify** OpenClaw with pane snapshot summary |
| `PostToolUse` | A tool call completed | Log only; **notify on error** (`toolResult.isError`) |
| `Notification` | Claude Code is waiting for input | **Notify** OpenClaw |
| `SessionEnd` | Session closed | **Notify** OpenClaw |

Watchdog alert: if no new event arrives within `CC_TIMEOUT` seconds (default 1800),
the watchdog sends `openclaw message send "⏰ watchdog: no activity..."` via the same
routing as Hook notifications.
---

## Common Commands

```bash
# Snapshot the last 50 lines of pane output (diagnostics)
cc-capture --tail 50

# Browse the event log
cat "$CC_SUPERVISOR_HOME/logs/events.ndjson" | jq .

# Tail the structured run log live
tail -f "$CC_SUPERVISOR_HOME/logs/supervisor.log" | jq .

# Test watchdog with a 1-minute timeout
CC_TIMEOUT=60 cc-supervise ~/Projects/my-app

# Run the full end-to-end demo (no real Claude Code needed)
"$CC_SUPERVISOR_HOME/scripts/demo.sh"
```

---

## Directory Structure

```
~/.openclaw/skills/cc-supervisor/   (skill install root)
├── SKILL.md                # ClawHub skill definition (frontmatter + workflow guide)
├── scripts/
│   ├── supervisor_run.sh   # create/reuse tmux session, launch Claude Code and watchdog
│   ├── cc_send.sh          # send text prompts or special keys to Claude Code (--key mode)
│   ├── cc_capture.sh       # snapshot recent tmux pane output
│   ├── on-cc-event.sh      # unified Hook callback: log + notify OpenClaw
│   ├── install-hooks.sh    # merge hook config into target project's .claude/settings.local.json
│   ├── cc-watchdog.sh      # inactivity watchdog daemon
│   ├── flush-queue.sh      # retry queued notifications
│   ├── demo.sh             # end-to-end demo script (no network required)
│   └── lib/log.sh          # shared structured JSON logging
├── config/
│   └── claude-hooks.json   # hook registration template (with placeholder)
└── logs/                   # runtime data (gitignored)
    ├── events.ndjson       # Hook event append log
    ├── supervisor.log      # structured JSON run log
    ├── notification.queue  # failed notifications pending retry (optional)
    └── watchdog.pid        # watchdog process PID
```

---

## Troubleshooting

**No notifications received:**
1. Confirm env vars are set: `echo $OPENCLAW_CHANNEL $OPENCLAW_TARGET`
2. Check the queue: `cat "$CC_SUPERVISOR_HOME/logs/notification.queue"`
3. Retry manually: `cc-flush-queue`
4. Check event log: `cat "$CC_SUPERVISOR_HOME/logs/events.ndjson" | jq .`
5. Check run log: `cat "$CC_SUPERVISOR_HOME/logs/supervisor.log" | jq .`

**Session already exists:**
`cc-supervise` reattaches to the existing session (idempotent). To force a fresh session:
```bash
tmux kill-session -t cc-supervise && cc-supervise ~/Projects/my-app
```

**`openclaw` not in PATH:**
Notifications are queued to `logs/notification.queue`. Once `openclaw` is available,
run `cc-flush-queue` to retry.

---

## Uninstalling

**Remove hooks from a project:**

```bash
jq 'del(.hooks)' ~/Projects/my-app/.claude/settings.local.json \
  > /tmp/settings.tmp && mv /tmp/settings.tmp \
  ~/Projects/my-app/.claude/settings.local.json
```

**Uninstall the skill:**

```bash
rm -rf ~/.openclaw/skills/cc-supervisor
# After ClawHub publishing: clawhub uninstall cc-supervisor
```

---

## Documentation

| File | Description |
|------|-------------|
| [README.md](README.md) | 中文 README |
| [SKILL.md](SKILL.md) | ClawHub skill definition |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, data flow, environment variables |
| [docs/SCRIPTS.md](docs/SCRIPTS.md) | Per-script interface reference |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [PRD.md](PRD.md) | Product goals and scope |
