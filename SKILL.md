---
name: cc-supervisor
description: "Use when human asks to run, supervise, or monitor Claude Code, OR when you receive any message starting with [cc-supervisor]. Required for all Claude Code supervision — relay mode (human-in-loop) or auto mode (self-driving). Do NOT supervise Claude Code without this skill."
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
2. Human asks for auto/supervised task execution
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
| **OpenClaw** | Execute phases; send messages to Claude on human's behalf; escalate when judgment required |
| **Claude Code** | Execute task in tmux; fire Hooks on state changes |

**CRITICAL — Who is talking to Claude:**
Claude Code's conversation partner is **OpenClaw (agent)**, not the human directly. OpenClaw relays human intent but is not human. Claude should never assume a human is manually typing responses.

## OpenClaw Behavior Rules

- Act first, explain later. Run commands immediately.
- No confirmations. Never ask "Should I proceed?"
- Use `$OPENCLAW_SESSION_ID` variable, not `<session-id>` placeholder.
- NEVER poll or sleep. Wait passively for `[cc-supervisor]` messages.
- Minimal messages. Only contact human when input required or task complete.
- Terse escalations. One sentence problem + one specific question.
- Human reply gate is explicit:
  - Only messages starting with `cc` may be forwarded to Claude Code
  - All other messages are for OpenClaw itself and must NOT be forwarded
  - Before acting on any human reply during supervision, run `scripts/handle-human-reply.sh`

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
| `auto` | OpenClaw | Long tasks, delegate to agent |

**Note:** The deprecated mode name `autonomous` is automatically mapped to `auto` for backward compatibility.

PostToolUse errors and watchdog timeouts always escalate to human.

---

## Quick Reference

| Phase | Trigger | Key Action | Done When |
|-------|---------|-----------|-----------|
| 0 | Human request | Collect project-dir, task, mode | All 3 inputs confirmed |
| 1 | Phase 0 complete | `cc-start <dir> [mode]` | `=== cc-start complete ===` |
| 2 | Phase 1 complete | `cc-send "<task>"` | Message sent |
| 3 | `[cc-supervisor]` message | Parse event → act per mode | Task complete signal |
| 4 | Task complete | `cc-capture --grep` → verify | Non-empty output confirmed |

---

## Workflow

### Role Check (CRITICAL — Run First)

Check if already supervising to prevent recursion:

```bash
if [[ "${CC_SUPERVISOR_ROLE:-}" == "supervisor" ]]; then
  echo "ERROR: cc-supervisor skill cannot be invoked recursively"
  exit 1
fi
export CC_SUPERVISOR_ROLE=supervisor
```

### Command Execution Context

Use absolute paths (shell aliases may not be loaded):
```bash
CC_SUPERVISOR_HOME="${CC_SUPERVISOR_HOME:-$HOME/.openclaw/skills/cc-supervisor}"
"$CC_SUPERVISOR_HOME/scripts/<script>.sh" ...
```

### Phase 0 — Gather inputs

**Human provides:** Project directory | Task description | Mode (`relay` or `auto`)

**Read details:** `docs/phase-0.md`

---

### Phase 1 — Start (automated)

Run `cc-start.sh <project-dir> [mode]`. Handles session ID, checks, hooks, tmux startup, and verification.

**Exit codes:** `0` = success → Phase 2 | `1` = fatal error | `2` = timeout → retry once

**Read details:** `docs/phase-1.md`

---

### Phase 2 — Send Initial Task

```bash
cc-send "<task description from Phase 0>"
```

Then wait passively for `[cc-supervisor]` messages. Do NOT poll.

**Read details:** `docs/phase-2.md`

---

### Phase 3 — Notification Loop

Handle `[cc-supervisor]` messages until task complete.

**Notification types:** Stop | PostToolUse | Notification | SessionEnd | Watchdog

**Mode-specific handling:**
- **relay mode:** Read `docs/relay-mode.md`
- **auto mode:** Read `docs/auto-mode.md`

**Human replies during supervision (MANDATORY):**
1. Run `"$CC_SUPERVISOR_HOME/scripts/handle-human-reply.sh" --mode "$CC_MODE" --message "$HUMAN_MESSAGE"`
2. Read the JSON result
3. `forward` / `continue` / `pause` are already executed by the script when `executed==true`
4. `meta` means adjust OpenClaw behavior only; do NOT forward
5. `status` returns `snapshot`; use it to reply to human
6. `exit` returns `next_phase=="phase_4"`; then proceed to Phase 4

**Read details:** `docs/phase-3.md`

---

### Phase 4 — Verify and Report

1. Run `cc-capture --tail 20 --grep "complete|done|error"`
2. Confirm substantive content (not empty, not pure errors)
3. Report: `Task complete. Mode: <mode> | Rounds: <N> | Summary: <what was built>`

**Read details:** `docs/phase-4.md`

---

## Execution Model and Bootstrap Fallback Lifecycle

Plain-language sequence:

1. The actor that **executes this skill** (typically the subagent running `cc-start`) initializes OpenClaw context (`OPENCLAW_SESSION_ID`, `OPENCLAW_CHANNEL`, `OPENCLAW_TARGET`, `OPENCLAW_AGENT_ID`).
2. Startup writes `logs/hook.env` as a **transient bootstrap fallback** bridge for hook callbacks.
3. Hook callback (`on-cc-event.sh`) first uses inherited runtime env.
4. Only if required values are missing, hook callback loads `logs/hook.env`.
5. After successful fallback load (required keys present), hook callback immediately deletes `logs/hook.env`.
6. Notifications are sent with OpenClaw session context (`--session-id "$OPENCLAW_SESSION_ID"`), not Claude internal session IDs from hook JSON.

Important ownership rule:
- Initialization belongs to the process that executes this skill.
- Parent/other agents may not share the same initialized env and must not be assumed to have it.

Troubleshooting notes:
- First hook event after startup may use transient fallback if env inheritance is missing.
- If fallback validation fails, notifications queue with explicit missing-key logs.
- Consume-and-delete behavior prevents stale fallback values from polluting later sessions.

---

## Notification Routing

**Strategy:** Session-based routing ensures notifications return to correct channel.

1. Query session metadata from OpenClaw session store
2. Extract routing info: `deliveryContext.to` → `lastTo` → `origin.to`
3. Infer channel from target format (e.g., `channel:123` → discord)
4. Fallback to env vars if session not found

**Command format:**
```bash
openclaw agent \
  --session-id "$OPENCLAW_SESSION_ID" \
  --message "[cc-supervisor] <event>" \
  --deliver \
  --reply-channel <channel> \
  --reply-to <target>
```

**Fallback:** If `openclaw` not in PATH → queue to `logs/notification.queue`, retry with `cc-flush-queue`

---

## Troubleshooting

**No notifications:**
- Check: `echo $OPENCLAW_SESSION_ID`
- Check queue: `cat "$CC_SUPERVISOR_HOME/logs/notification.queue"`
- Flush: `cc-flush-queue`

**Session exists:** Reattaches automatically. Force fresh: `tmux kill-session -t cc-supervise && cc-start <dir>`

**For detailed troubleshooting:** See `docs/TROUBLESHOOTING.md`

---

## Installation Reference

For one-time machine setup, see `README.md` or run:
```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/cc-supervisor/main/install.sh | bash
```
