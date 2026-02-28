---
name: cc-supervisor
description: "Use when human asks to run, supervise, or monitor Claude Code, OR when you receive any message starting with [cc-supervisor]. Required for all Claude Code supervision — relay mode (human-in-loop) or autonomous mode (self-driving). Do NOT supervise Claude Code without this skill."
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

## Red Flags — STOP and Re-read This Skill

If you catch yourself thinking any of these, STOP immediately:

| Rationalization | Reality |
|----------------|---------|
| "I'll just reply to this [cc-supervisor] message directly" | MUST invoke skill first. Every time. |
| "The task seems done, I'll skip Phase 4 verification" | Phase 4 is mandatory. No exceptions. |
| "I'll poll cc-capture every few seconds to check progress" | NEVER poll. Wait passively for notifications. |
| "This error is minor, I'll handle it without escalating" | Check Limits table. 3x same error = escalate. |
| "I already know the session ID, no need to validate" | Always use `$OPENCLAW_SESSION_ID` variable. |
| "cc-start timed out but the session looks fine" | Run `cc-flush-queue`, retry once. Then escalate. |

---

## Supervision Modes

| `CC_MODE` | Who decides | When to use |
|---|---|---|
| `relay` (default) | Human | Sensitive tasks, full control |
| `autonomous` | OpenClaw | Long tasks, delegate to agent |

PostToolUse errors and watchdog timeouts always escalate to human.

---

## Quick Reference

| Phase | Trigger | Key Action | Done When |
|-------|---------|-----------|-----------|
| 0 | Human request | Collect project-dir, task, mode | All 3 inputs confirmed |
| 1 | Phase 0 complete | `cc-start <dir> [mode]` | `=== cc-start complete ===` |
| 2 | Phase 1 complete | `cc-send "<task>"` | Message sent |
| 3 | `[cc-supervisor]` message | Parse event → act per mode | Task complete signal |
| 4 | Task complete | `cc-capture --tail 40` → verify | Non-empty output confirmed |

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
- `ERROR: OPENCLAW_SESSION_ID not set` → cannot auto-fix, escalate to human
- `ERROR: OPENCLAW_TARGET not set` → cannot auto-fix, escalate to human
- `ERROR: Missing scripts` → CC_PROJECT_DIR misconfigured, escalate to human
- `ERROR: Hook '...' not found after install` → run `cat <project>/.claude/settings.local.json | jq .hooks` to diagnose, escalate to human
- `TIMEOUT: ...` → run `cc-flush-queue`, re-run `cc-start`
  - If 2nd attempt also TIMEOUT → escalate to human with `cc-capture --tail 30` output
  - Do NOT retry indefinitely

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

**Stop is Task Complete when ALL of:**
- Output contains terminal language: "Task complete" / "Done" / "Finished" / "已完成"
- No pending questions or confirmations
- When uncertain → forward to human. Never assume complete.

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
| Blocked | `cc-send "Please try a different approach: <describe blocker>"` | 3x same error |
| Progress | `cc-send "Please continue."` | Never |

**Blocked self-recovery strategy:**
1. 1st time: `cc-send "Please try a different approach to resolve: <error>"`
2. 2nd time: `cc-send "The previous approach failed. Try: <alternative suggestion>"`
3. 3rd time: escalate to human

**Escalate:** Production API keys/URLs | 3x same error | System failures

**Do NOT escalate:** File/dependency/config/git ops | Technical decisions | Recoverable errors | Dev configs

**Limits and actions when exceeded:**

| Limit | Threshold | Action when exceeded |
|-------|-----------|---------------------|
| Total rounds | 30 | STOP. Escalate: "Reached 30-round limit. Task may be too complex." |
| Consecutive "continue" | 8 | STOP sending continue. Escalate with last output. |
| Same error repeated | 3 | STOP self-correcting. Escalate with error details. |
| Watchdog alerts | 2 | STOP sending continue. Escalate. No more auto-recovery. |

**Escalation:** `[cc-supervisor][autonomous] Escalation: Type: <type> | Reason: <why> | Rounds: <N> | Blocker: <issue> | Output: <output> | Need: <info>`

**Full rules:** `~/.openclaw/skills/cc-supervisor/docs/AUTONOMOUS_DECISION_RULES.md`

---

#### Other notification types

- `PostToolUse: Tool error` → relay: notify; autonomous: self-correct once, escalate on recurrence
- `Notification: <msg>` → relay: notify; autonomous: handle if routine, escalate if judgment needed
- `SessionEnd` →
  1. Notify human: "[cc-supervisor] Session ended (session_id=...)"
  2. Check if task was complete (review last Stop event content)
  3. If task incomplete → escalate: "Session ended unexpectedly. Last output: <cc-capture --tail 20>"
  4. If task complete → proceed to Phase 4
- `⏰ watchdog` → `cc-capture --tail 60`; relay: forward to human; autonomous:
  - 1st alert: `cc-send "Please continue."` + record alert count internally
  - 2nd alert: STOP sending continue. Escalate: `[cc-supervisor][autonomous] Escalation: Type: watchdog | Reason: 2nd inactivity timeout | Rounds: <N> | Blocker: no activity for <Xs> | Output: <cc-capture --tail 20> | Need: human check`
  - 3rd+ alert: escalate only, no continue
- `[poll] snapshot` → If stuck → `cc-send "Please continue."`; if working → no action

---

### Phase 4 — Verify and Report

1. Run `cc-capture --tail 40` to get final output
2. Confirm output has substantive content (not empty, not pure errors)
3. If output is empty or errors only → do NOT report complete. Escalate:
   `[cc-supervisor] Phase 4 verification failed: <reason> | Mode: <mode> | Rounds: <N> | Last output: <cc-capture --tail 10 output>`
4. Report format: `Task complete. Mode: <mode> | Rounds: <N> | Summary: <what was built>`

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
