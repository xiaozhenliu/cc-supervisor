---
name: cc-supervisor
description: "MANDATORY: Use this skill when human asks to run/supervise/monitor Claude Code, or when you receive ANY message starting with [cc-supervisor]. This skill enables autonomous multi-turn supervision of Claude Code via Hook-driven notifications. DO NOT attempt to supervise Claude Code without this skill — you will fail."
version: 0.7.2
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

**MANDATORY — You MUST use this skill when:**

1. **Human explicitly asks to use Claude Code:**
   - "Run Claude Code on this project"
   - "Use Claude Code to implement X"
   - "Let Claude Code handle this task"
   - "Supervise Claude Code while it works on Y"

2. **Human asks for autonomous/supervised task execution:**
   - "Autonomously implement X" (implies Claude Code supervision)
   - "Monitor and drive the implementation of Y"
   - "Keep working on Z until it's done"

3. **You receive a message starting with `[cc-supervisor]`:**
   - These are Hook event notifications from an active supervision session
   - You MUST invoke this skill immediately to handle the event
   - Do NOT attempt to handle these messages without loading this skill

**DO NOT attempt to:**
- Supervise Claude Code manually without this skill
- Handle `[cc-supervisor]` messages without loading this skill
- Implement multi-turn autonomous tasks without this skill

**If you're unsure:** When human asks for any form of autonomous or supervised code execution, use this skill.

## Trigger Rules

**CRITICAL — These rules override all other behaviors:**

1. **When you receive ANY message starting with `[cc-supervisor]`:**
   - IMMEDIATELY invoke this skill (do not respond first)
   - Read the full SKILL.md to get current context
   - Parse the event type from the message
   - Follow Phase 5 handling rules for the current mode

2. **When human asks to run/supervise/monitor Claude Code:**
   - IMMEDIATELY invoke this skill (do not ask for clarification first)
   - Start from Phase 0 to gather required inputs
   - Do not attempt manual supervision

3. **Priority:** This skill takes precedence over default agent behavior when supervising Claude Code

---

## Roles

| Actor | Responsibilities |
|-------|-----------------|
| **Human** | Provide project directory, task description, and supervision mode; confirm directory trust prompt; make judgment calls on errors and blockers |
| **OpenClaw** | Execute all phases below; escalate to human when judgment is required |
| **Claude Code** | Execute the task inside tmux; fires Hooks on each state change |

## OpenClaw Behavior Rules

- **Act first, explain later.** Run commands immediately. Do not narrate what you are about to do.
- **No confirmations.** Never ask "Should I proceed?" or "Is this correct?" before running a phase step. Just run it.
- **Minimal messages to human.** When notifying the human, include only: Stop type, Claude Code's output, and what is needed from them. No preamble, no summary of what you did.
- **No status updates.** Do not send messages like "Running Phase 2..." or "Hooks registered successfully." Only contact the human when their input is required or the task is complete.
- **Terse escalations.** When escalating, state the problem in one sentence and ask one specific question.

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
- `OPENCLAW_SESSION_ID` — the current session ID; this is how Hook callbacks route notifications back to this exact conversation

Optionally, for reply delivery back to a specific chat target:
- `OPENCLAW_CHANNEL` — the channel for reply delivery (e.g. `discord`)
- `OPENCLAW_TARGET` — the channel target ID (e.g. a Discord channel ID)

`OPENCLAW_SESSION_ID` is required. OpenClaw knows it — do not ask the human.

Optionally, for proactive terminal polling between Hook events:
- `CC_POLL_INTERVAL` — minutes between poll snapshots (default: `15`, range: `3`–`1440`; set to `0` to disable)
- `CC_POLL_LINES` — terminal lines to capture per poll (default: `40`)

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
# relay mode (default) — OPENCLAW_SESSION_ID is required
OPENCLAW_SESSION_ID=<session-id> \
  cc-supervise <project-dir>

# autonomous mode
OPENCLAW_SESSION_ID=<session-id> \
  CC_MODE=autonomous cc-supervise <project-dir>

# Disable proactive polling
OPENCLAW_SESSION_ID=<session-id> \
  CC_POLL_INTERVAL=0 cc-supervise <project-dir>
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

#### Stop event classification

When a Stop notification arrives, OpenClaw must first classify Claude Code's output before acting. Do not treat all Stop events as identical.

| Type | How to identify | cc-send method |
|------|----------------|----------------|
| **Task complete** | Output states all work is done, no remaining items | — (no send) |
| **Yes/No confirmation** | Output ends with a yes/no or binary choice question | `cc-send --key y` or `cc-send --key n` |
| **Multiple choice** | Output lists numbered options to choose from | `cc-send --key 1` / `cc-send --key 2` / etc. |
| **Cursor navigation** | Output shows a menu/list where selection requires moving cursor | `cc-send --key Up` / `cc-send --key Down` then `cc-send --key Enter` |
| **Open question** | Output asks for specific information (a value, a path, a decision) | `cc-send "<answer text>"` |
| **Blocked** | Output reports an error, missing permission, or inability to continue | `cc-send "<instruction text>"` |
| **In progress** | Output describes work still underway, no input needed | `cc-send "Please continue."` |

**cc-send reference:**
```bash
cc-send "text"       # type text and press Enter — for open questions and instructions
cc-send --key y      # single character key — for yes/no
cc-send --key 1      # single character key — for numbered choices
cc-send --key Up     # directional key — for cursor navigation
cc-send --key Down
cc-send --key Enter  # confirm after navigation
```

---

#### relay mode

OpenClaw notifies the human of every Stop event, including the classification and Claude Code's actual output. OpenClaw never acts on its own — it always waits for the human's reply first.

**For every Stop type, send the human:**
```
[cc-supervisor][relay] Stop (<type>):
<Claude Code's actual output>
```

**Human reply → OpenClaw action:**

| Stop type | Human reply | OpenClaw action |
|-----------|-------------|-----------------|
| Task complete | any | Proceed to Phase 6 |
| Yes/No confirmation | "y" or "n" | `cc-send --key y` or `cc-send --key n` |
| Multiple choice | a number | `cc-send --key <number>` |
| Cursor navigation | "up"/"down" + confirm | `cc-send --key Up/Down` then `cc-send --key Enter` |
| Open question | human's answer | `cc-send "<answer>"` |
| Blocked | human's instruction | `cc-send "<instruction>"` |
| In progress | human's instruction (or "continue") | `cc-send "Please continue."` |

If the human's reply is ambiguous, ask for clarification before sending any `cc-send`. Do not guess.

**OpenClaw never sends a follow-up prompt on its own in relay mode.**

---

#### autonomous mode

OpenClaw handles all Stop types independently using the decision rules defined in `docs/AUTONOMOUS_DECISION_RULES.md`. It operates in **fully autonomous mode** — all programming-related decisions are made automatically. It only contacts the human when truly stuck (missing external info, repeated failures, system errors).

**Core principles:**
1. **Fully autonomous** — all programming operations are auto-approved, no confirmations
2. **Default to `y`** — answer yes to all questions except "abort task"
3. **Trust Claude Code** — operations proposed by Claude Code are for task completion, approve them
4. **Failures are recoverable** — wrong decisions can be fixed later, no need for pre-approval
5. **Escalate only when stuck** — only escalate when truly cannot proceed

**Security note:** Safety is ensured by sandboxing, backups, and version control — not by interactive confirmations. In autonomous mode, the human has chosen to fully trust the agent.

**Quick reference:**

| Stop type | OpenClaw action | Escalate if |
|-----------|----------------|-------------|
| Task complete | Notify human → proceed to Phase 6 | — |
| Yes/No confirmation | Always `y` (approve all: create, delete, install, commit, push, permissions, API calls) | Never (except if question is "abort task?") |
| Multiple choice | Choose recommended/default/first option | Never |
| Cursor navigation | Navigate to target using Up/Down + Enter | Never |
| Open question | Answer using task context, project conventions, or reasonable defaults (ports, names, configs) | Only if requires real external info (production API keys, real service URLs) |
| Blocked | Attempt fix; if same error 3 times → escalate | Third occurrence of same error |
| In progress | `cc-send "Please continue."` | Never |

**Must escalate when (rare):**
- Missing critical external info: production API keys, real service credentials, real external URLs
- Repeated failure: same error 3 times, all fix attempts failed
- System-level issues: hardware failure, OS errors, external services completely down
- Unclear task goal: task description too vague to infer intent

**Do NOT escalate for (most cases):**
- Any file operations: create, modify, delete
- Any dependency operations: install, uninstall, upgrade
- Any config changes: modify settings, permissions, environment
- Any git operations: commit, push, merge, rebase
- Any technical decisions: tech stack, architecture, algorithms, code structure
- Any recoverable errors: syntax, types, configs, dependencies
- Any dev environment configs: ports, database names, test data, mocks

**Round limits:**
- Total rounds: 30 → escalate with progress report
- Consecutive "Please continue": 8 → escalate, likely stuck
- Consecutive self-corrections: 3 (same error) → escalate, strategy ineffective
- Watchdog triggers: 3 → escalate, task may be impossible

**Escalation message format:**
```
[cc-supervisor][autonomous] Escalation required:

Type: <Stop type>
Reason: <why escalation needed>
Rounds: <completed rounds>
Progress: <work completed>
Remaining: <remaining work>
Blocker: <specific blocking issue>

Claude Code output:
<actual output>

What I need:
<specific info needed from human>
```

**Full decision rules:** See `~/.openclaw/skills/cc-supervisor/docs/AUTONOMOUS_DECISION_RULES.md` for detailed decision trees, examples, and default values for all question types.

---

#### Other notification types

| Notification received | OpenClaw action |
|---|---|
| `PostToolUse: Tool error — <tool>: <msg>` | relay: notify human → wait for reply; autonomous: self-correct once, escalate on recurrence |
| `Notification: <msg>` | relay: notify human → wait for reply; autonomous: handle if routine, escalate if judgment needed |
| `SessionEnd` | Notify human: "Session ended — task may be complete or crashed." |
| `⏰ watchdog: no activity for Xs` | Run `cc-capture --tail 60` → relay: forward to human; autonomous: `cc-send "Please continue"`, escalate if fires again |
| `[cc-supervisor][poll] Terminal snapshot: ...` | Review terminal state; if stuck/idle → `cc-send "Please continue."`; if working normally → no action |

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

cc-supervisor triggers the OpenClaw agent via `openclaw agent --session-id <id> --message <content>`. The `--session-id` ensures Hook callbacks land in the same agent session that started the supervision, preserving full conversation context. Do not use `--agent` together with `--session-id` as they conflict.

| Variable | Example | Required | Description |
|----------|---------|----------|-------------|
| `OPENCLAW_SESSION_ID` | `7f79453c-...` | **Yes** | The session ID of the conversation that started supervision |
| `OPENCLAW_CHANNEL` | `discord` | No | If set, agent reply is delivered back to this channel |
| `OPENCLAW_TARGET` | `1466784529527214122` | No | Channel target ID for `--deliver` reply routing |

**Fallback behavior:**
- `OPENCLAW_SESSION_ID` not set → notification skipped, event still logged
- `openclaw` not in PATH → written to `logs/notification.queue`
- Agent trigger fails → written to `logs/notification.queue`

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
1. Check env vars: `echo $OPENCLAW_SESSION_ID`
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

# OPENCLAW_SESSION_ID is set automatically by the agent at runtime — do not hardcode
# Optional: deliver agent replies back to a specific channel target
export OPENCLAW_CHANNEL=discord
export OPENCLAW_TARGET=<your-channel-id>

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
