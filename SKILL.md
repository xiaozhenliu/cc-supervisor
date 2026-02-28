---
name: cc-supervisor
description: "MANDATORY: Use this skill when human asks to run/supervise/monitor Claude Code, or when you receive ANY message starting with [cc-supervisor]. This skill enables autonomous multi-turn supervision of Claude Code via Hook-driven notifications. DO NOT attempt to supervise Claude Code without this skill — you will fail."
version: 1.2.0
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

**MANDATORY — Use when:**
1. Human asks to use Claude Code
2. Human asks for autonomous/supervised task execution
3. You receive `[cc-supervisor]` message (Hook event)

**DO NOT:** Supervise Claude Code manually without this skill

## Trigger Rules

**When you receive `[cc-supervisor]` message:** IMMEDIATELY invoke this skill, parse event type, follow Phase 3 rules

**When human asks to run Claude Code:** IMMEDIATELY invoke this skill, start from Phase 0

---

## Roles

| Actor | Responsibilities |
|-------|-----------------|
| **Human** | Provide project dir, task, mode; confirm trust prompt; make judgment calls |
| **OpenClaw** | Execute phases; escalate when judgment required |
| **Claude Code** | Execute task in tmux; fire Hooks on state changes |

## OpenClaw Behavior Rules

- Act first, explain later. Run commands immediately.
- No confirmations. Never ask "Should I proceed?"
- Obtain `OPENCLAW_SESSION_ID` yourself. Never ask human.
- Use `$OPENCLAW_SESSION_ID` variable, not `<session-id>` placeholder.
- NEVER poll or sleep. Wait passively for `[cc-supervisor]` messages.
- Minimal messages. Only contact human when input required or task complete.
- Terse escalations. One sentence problem + one specific question.

---

## Supervision Modes

| `CC_MODE` | Who decides | When to use |
|---|---|---|
| `relay` (default) | Human | Sensitive tasks, full control |
| `autonomous` | OpenClaw | Long tasks, delegate to agent |

PostToolUse errors and watchdog timeouts always escalate to human.

---

## Workflow

### Phase 0 — Gather inputs

**Human provides:** Project directory (absolute path) | Task description | Mode: `relay` or `autonomous` (default: `relay`)

---

### Phase 1 — Start (automated)

Run one command. It handles session ID validation, hook install, tmux startup, and hook verification automatically.

```bash
cc-start <project-dir> [relay|autonomous]
```

**Read the output carefully:**
- `=== cc-start complete ===` → proceed to Phase 2
- `ERROR: ...` → fix the stated problem, re-run
- `TIMEOUT: ...` → hook routing failed; follow the printed diagnostics, then run `cc-flush-queue` and re-run

**⚠ Human action required:** If Claude Code shows a directory trust prompt, message human to run `tmux attach -t cc-supervise`, type `y`, Enter, then Ctrl-B D. Then re-run `cc-start`.

---

### Phase 2 — Send Initial Task

```bash
cc-send "<task description from Phase 0>"
```

### Phase 3 — Notification Loop

**CRITICAL:** Do NOT poll/sleep/check logs. Wait passively for `[cc-supervisor]` messages. Zero tokens while waiting.

**Exception:** Every 30 minutes, run `cc-flush-queue`.

#### Stop event classification

Read Claude Code's output to see format (y/n, 1/2, a/b). Use that exact format.

**Examples:** `"(y/n)"` → `cc-send --key y` | `"1) Continue 2) Abort"` → `cc-send --key 1` | `"a) Yes b) No"` → `cc-send --key a`

**cc-send:** `cc-send "text"` (full text) | `cc-send --key y` (single char) | `cc-send --key Up` (directional) | `cc-send --key Enter` (confirm)

---

#### relay mode

OpenClaw notifies human of every Stop event. Never acts on its own.

**Format:** `[cc-supervisor][relay] Stop (<type>): <output>`

**Human reply → Action:** Task complete → Phase 4 | "y"/"n" → `cc-send --key y/n` | Number → `cc-send --key <N>` | Text → `cc-send "<text>"` | "continue" → `cc-send "Please continue."`

---

#### autonomous mode

OpenClaw handles all Stop types independently. Fully autonomous — all programming operations auto-approved.

**Core:** Check human interruption (`STOP`, `PAUSE`, `WAIT`, `HOLD`) → Read output → Parse format → Send "continue" option → Auto-approve programming ops → Escalate only when stuck

**Quick reference:**

| Stop type | Action | Escalate if |
|-----------|--------|-------------|
| Complete | Notify → Phase 4 | — |
| Yes/No | Send "yes/continue" | Never |
| Choice | Select recommended | Never |
| Question | Use defaults | Real external info |
| Blocked | Fix | 3x same error |
| Progress | `cc-send "Please continue."` | Never |

**Escalate:** Production API keys/URLs | 3x same error | System failures

**Do NOT escalate:** File/dependency/config/git ops | Technical decisions | Recoverable errors | Dev configs

**Limits:** Total: 30 | Consecutive "continue": 8 | Same error: 3 | Watchdog: 3

**Escalation:** `[cc-supervisor][autonomous] Escalation: Type: <type> | Reason: <why> | Rounds: <N> | Blocker: <issue> | Output: <output> | Need: <info>`

**Full rules:** `~/.openclaw/skills/cc-supervisor/docs/AUTONOMOUS_DECISION_RULES.md`

---

#### Other notification types

- `PostToolUse: Tool error` → relay: notify; autonomous: self-correct once, escalate on recurrence
- `Notification: <msg>` → relay: notify; autonomous: handle if routine, escalate if judgment needed
- `SessionEnd` → Notify: "Session ended"
- `⏰ watchdog` → `cc-capture --tail 60`; relay: forward; autonomous: `cc-send "Please continue"`, escalate if fires again
- `[poll] snapshot` → If stuck → `cc-send "Please continue."`; if working → no action

---

### Phase 4 — Verify and Report

Check output exists, then message: `Task complete. Mode: <mode> | Rounds: <N> | Summary: <what was built>`

---

## Notification Routing

Triggers: `openclaw agent --session-id <id> --message <content>`

Vars: `OPENCLAW_SESSION_ID` (required) | `OPENCLAW_CHANNEL` (optional) | `OPENCLAW_TARGET` (optional)

Fallback: Session ID not set → skip | `openclaw` not in PATH → queue to `logs/notification.queue` | Retry: `cc-flush-queue`

---

## Troubleshooting

**No notifications:** `echo $OPENCLAW_SESSION_ID` | `cat "$CC_SUPERVISOR_HOME/logs/notification.queue"` | `cc-flush-queue`

**Session exists:** Reattaches. Force fresh: `tmux kill-session -t cc-supervise && cc-supervise <dir>`

---

## One-Time Machine Setup

Add to `~/.zshrc` or `~/.bashrc`:

```bash
export CC_SUPERVISOR_HOME=~/.openclaw/skills/cc-supervisor
export OPENCLAW_CHANNEL=discord  # optional
export OPENCLAW_TARGET=<your-channel-id>  # optional

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
cc-start()       { CC_PROJECT_DIR="$CC_SUPERVISOR_HOME" "$CC_SUPERVISOR_HOME/scripts/cc-start.sh" "$@"; }
```

Then: `source ~/.zshrc`

---

## End-to-End Test

Test guide: `~/.openclaw/skills/cc-supervisor/example-project/E2E_TEST.md`
