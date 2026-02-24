---
name: cc-supervisor
description: Supervise Claude Code in a tmux session via Hook-driven notifications. Use when asked to run, monitor, or drive Claude Code through a multi-turn task in any local project directory.
version: 0.6.7
metadata:
  openclaw:
    emoji: 🦾
    requires:
      bins: [tmux, jq, claude]
    install:
      - kind: brew
        formula: jq
        bins: [jq]
      - kind: brew
        formula: tmux
        bins: [tmux]
    os: [macos]
---

# CC Supervisor

Supervise Claude Code through multi-turn tasks without polling. Claude Code runs in a tmux session; Hook callbacks notify OpenClaw on every state change. OpenClaw waits for notifications — zero tokens consumed while idle.

```
Human ──(task + mode)──→ OpenClaw ── cc-send ──→ Claude Code (tmux: cc-supervise)
                             ↑                           │
                             │                    Hook fires on event
                             │         (Stop / PostToolUse / Notification / SessionEnd)
                             │                           │
                             └── openclaw message send ←─┘
                                          │
                               logs/events.ndjson
```

---

## When to Use This Skill

Use this skill when the human asks to:
- Run Claude Code on a task in a local project directory
- Supervise or monitor a Claude Code session
- Drive Claude Code through a multi-turn task autonomously
- Set up Hook-based event notifications for a project

---

## Roles

| Actor | Responsibilities |
|-------|-----------------|
| **Human** | Provide project directory, task description, and supervision mode; confirm directory trust prompt; make judgment calls on errors and blockers |
| **OpenClaw** | Execute all phases below; escalate to human when judgment is required |
| **Claude Code** | Execute the task inside tmux; fires Hooks on each state change |

---

## Supervision Modes

Choose the mode based on how much control the human wants to retain.

| `CC_MODE` | Who decides next step | When to use |
|---|---|---|
| `relay` (default) | Human — OpenClaw forwards every notification and waits | Sensitive tasks, human wants full control |
| `autonomous` | OpenClaw — self-drives until done or stuck | Long tasks, human delegates to OpenClaw |

In both modes: PostToolUse errors and watchdog timeouts always escalate to the human.

---

## Workflow

### Phase 0 — Human provides inputs

Before OpenClaw starts, the human must provide:
1. **Project directory** — absolute path to the local project
2. **Task description** — what Claude Code should do
3. **Mode** — `relay` or `autonomous` (default: `relay`)

OpenClaw does not proceed until all three are provided.

Before continuing, OpenClaw must also confirm it has values for:
- `OPENCLAW_CHANNEL` — the notification channel (e.g. `discord`)
- `OPENCLAW_ACCOUNT` — the name of the agent sending notifications (i.e. your own agent name, e.g. `main`)
- `OPENCLAW_TARGET` — the recipient/channel ID

These are properties of OpenClaw's own configuration. If any are unknown, check OpenClaw's channel settings before proceeding.

---

### Phase 1 — Verify Shell Setup (once per machine)

*OpenClaw runs this check every time the skill is invoked.*

```bash
command -v cc-supervise && command -v cc-send && command -v cc-install-hooks && echo "OK"
```

If the check fails, message the human:

> "Shell aliases for cc-supervisor are not configured. Please add the following to your `~/.zshrc` or `~/.bashrc` and run `source ~/.zshrc`:"

Then paste the full alias block from the **One-Time Machine Setup** section below. Wait for the human to confirm before continuing.

---

### Phase 2 — Register Hooks (once per project)

*OpenClaw runs this. Safe to repeat.*

```bash
cc-install-hooks <project-dir>
```

Verify:

```bash
cat <project-dir>/.claude/settings.local.json | jq '.hooks | keys'
# Expected: ["Notification", "PostToolUse", "SessionEnd", "Stop"]
```

---

### Phase 3 — Start Session

*OpenClaw runs this.*

```bash
# relay mode (default)
OPENCLAW_CHANNEL=<channel> OPENCLAW_ACCOUNT=<account> OPENCLAW_TARGET=<target-id> \
  cc-supervise <project-dir>

# autonomous mode
OPENCLAW_CHANNEL=<channel> OPENCLAW_ACCOUNT=<account> OPENCLAW_TARGET=<target-id> \
  CC_MODE=autonomous cc-supervise <project-dir>
```

**⚠ Human action — directory trust prompt:**
When Claude Code opens a directory for the first time, it shows a trust confirmation in the terminal. OpenClaw must message the human:

> "Claude Code is asking to trust `<project-dir>`. Please run `tmux attach -t cc-supervise`, type `y` and press Enter, then detach with Ctrl-B D."

OpenClaw waits for the human to confirm before continuing.

---

### Phase 4 — Send Initial Task

*OpenClaw runs this.*

```bash
cc-send "<task description from Phase 0>"
```

---

### Phase 5 — Notification Loop

*OpenClaw waits for Hook notifications. No polling.*

Every 30 minutes without a notification, run `cc-flush-queue` to retry any queued messages.

#### relay mode

OpenClaw forwards every Stop notification to the human and waits for their reply before acting.

**Stop notification format** (sent by cc-supervisor):
```
[cc-supervisor][relay] Stop:
<Claude Code's actual output>

Reply with your next instruction for Claude Code.
```

**Human reply → OpenClaw action:**

The human's reply is sent verbatim as the next `cc-send` instruction. OpenClaw does not interpret or modify it.

If the human's reply is ambiguous or unclear, OpenClaw must ask for clarification before sending any `cc-send`. Do not guess intent.

If the human replies that the task is done or they want to stop, proceed to Phase 6 instead of sending a cc-send.

**Other notification types:**

| Notification received | OpenClaw action |
|---|---|
| `[cc-supervisor][relay] PostToolUse: Tool error — <tool>: <msg>` | Forward to human → wait for reply → `cc-send "<reply>"` |
| `[cc-supervisor][relay] Notification: <msg>` | Forward to human → wait for reply → `cc-send "<reply>"` |
| `[cc-supervisor][relay] SessionEnd: ...` | Notify human: "Session ended — task may be complete or crashed." |
| `⏰ watchdog: no activity for Xs` | Run `cc-capture --tail 60` → forward output to human → wait for reply |

**OpenClaw never sends a follow-up prompt on its own in relay mode.**

#### autonomous mode

OpenClaw self-drives. It only escalates to the human when it cannot proceed.

| Notification received | OpenClaw action |
|---|---|
| `[cc-supervisor][autonomous] Stop: <summary> \| ACTION_REQUIRED: decide_and_continue` | Apply decision logic below |
| `[cc-supervisor][autonomous] PostToolUse: Tool error — <tool>: <msg>` | Send one self-correction via `cc-send`; if same error recurs → escalate to human |
| `[cc-supervisor][autonomous] Notification: <msg>` | Respond autonomously if routine; escalate if judgment is required |
| `[cc-supervisor][autonomous] SessionEnd: ...` | Proceed to Phase 6 |
| `⏰ watchdog: no activity for Xs` | Run `cc-capture --tail 60` → send `cc-send "Please continue"` → if timeout fires again → escalate to human |

**Stop decision logic (autonomous):**

```
if summary shows task is NOT complete (still planning / files not yet created):
    cc-send "Please continue and complete all remaining files."

elif summary shows an error or blocker:
    cc-send "There is an error: <description>. Please fix it and continue."
    # if same error recurs → escalate to human

elif summary shows task is complete:
    → proceed to Phase 6
```

**Escalate to human when:**
- Same error appears twice in a row
- Claude Code asks something requiring human judgment (credentials, destructive ops, ambiguous requirements)
- Watchdog fires twice without recovery
- More than 10 rounds pass without completion

---

### Phase 6 — Verify and Report

*OpenClaw runs this, then reports to human.*

Check that expected output exists in `<project-dir>`, then message the human:

```
Task supervision complete.
Mode: <relay|autonomous>
Rounds: <N>
Project: <project-dir>
Summary: <what was built or what happened>
```

The human decides whether to accept the result, request changes, or start a new task.

---

## Notification Routing

cc-supervisor routes notifications via two environment variables that OpenClaw must set when starting the session (Phase 2).

| Variable | Example | Description |
|----------|---------|-------------|
| `OPENCLAW_CHANNEL` | `discord` | Notification channel |
| `OPENCLAW_ACCOUNT` | `main` | The sending agent's own name |
| `OPENCLAW_TARGET` | `1466784529527214122` | Channel target ID |

Ask the human for these values in Phase 0 if not already known.

**Fallback behavior:**
- Variables not set → notification skipped, event still logged
- `openclaw` not in PATH → written to `logs/notification.queue`
- Send fails → written to `logs/notification.queue`

Run `cc-flush-queue` to retry queued notifications.

---

## Event Log Format

Each line in `logs/events.ndjson`:

```json
{"ts":"2026-01-01T12:00:00Z","event_type":"Stop","session_id":"abc123","event_id":"evt456","summary":"...","tool_name":null}
{"ts":"2026-01-01T12:00:01Z","event_type":"PostToolUse","session_id":"abc123","event_id":"evt457","summary":"Tool: Bash","tool_name":"Bash"}
```

---

## Troubleshooting

**No notifications received:**
1. Check env vars: `echo $OPENCLAW_CHANNEL $OPENCLAW_TARGET`
2. Check queue: `cat "$CC_SUPERVISOR_HOME/logs/notification.queue"`
3. Retry: `cc-flush-queue`
4. Check event log: `cat "$CC_SUPERVISOR_HOME/logs/events.ndjson" | jq .`

**`openclaw` not in PATH:**
Notifications queue to `logs/notification.queue`. Run `cc-flush-queue` once available.

**Session already exists:**
`cc-supervise` reattaches (idempotent). To force a fresh session:
```bash
tmux kill-session -t cc-supervise && cc-supervise <project-dir>
```

---

## One-Time Machine Setup

*Human runs this once after installing the skill.*

Add to `~/.zshrc` or `~/.bashrc`:

```bash
export CC_SUPERVISOR_HOME=~/.openclaw/skills/cc-supervisor

# Notification routing — set to this agent's own channel configuration
export OPENCLAW_CHANNEL=discord        # notification channel
export OPENCLAW_ACCOUNT=main           # this agent's name
export OPENCLAW_TARGET=<your-target-id> # recipient/channel ID

cc-supervise() {
  local target="${1:?Usage: cc-supervise <project-dir>}"
  CC_PROJECT_DIR="$CC_SUPERVISOR_HOME" CLAUDE_WORKDIR="$target" \
    "$CC_SUPERVISOR_HOME/scripts/supervisor_run.sh"
}

cc-install-hooks() {
  local target="${1:?Usage: cc-install-hooks <project-dir>}"
  CC_PROJECT_DIR="$CC_SUPERVISOR_HOME" CLAUDE_WORKDIR="$target" \
    "$CC_SUPERVISOR_HOME/scripts/install-hooks.sh"
}

cc-send()        { "$CC_SUPERVISOR_HOME/scripts/cc_send.sh" "$@"; }
cc-capture()     { "$CC_SUPERVISOR_HOME/scripts/cc_capture.sh" "$@"; }
cc-flush-queue() { "$CC_SUPERVISOR_HOME/scripts/flush-queue.sh"; }
```

Then reload: `source ~/.zshrc`

---

## End-to-End Test

Full test guide (both relay and autonomous modes):

```
~/.openclaw/skills/cc-supervisor/example-project/E2E_TEST.md
```
