---
name: cc-supervisor
description: "MANDATORY: Use this skill when human asks to run/supervise/monitor Claude Code, or when you receive ANY message starting with [cc-supervisor]. This skill enables autonomous multi-turn supervision of Claude Code via Hook-driven notifications. DO NOT attempt to supervise Claude Code without this skill — you will fail."
version: 0.7.6
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

**When you receive `[cc-supervisor]` message:** IMMEDIATELY invoke this skill, parse event type, follow Phase 5 rules

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

### Phase 0 — Gather inputs and environment

**Human provides:** Project directory (absolute path) | Task description | Mode: `relay` or `autonomous` (default: `relay`)

**OpenClaw obtains (DO NOT ask human):**

```bash
# CRITICAL: Verify OPENCLAW_SESSION_ID is set and has correct UUID format
# Session ID MUST be UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# NOT routing format like: agent:ruyi:discord:channel:1466784529527214122
# The routing format is a session key, not a session ID

eval "$($CC_SUPERVISOR_HOME/scripts/get-session-id.sh)"
$CC_SUPERVISOR_HOME/scripts/verify-session-id.sh "$OPENCLAW_SESSION_ID"

echo "✓ Session: $OPENCLAW_SESSION_ID | Project: <dir> | Mode: <mode>"
```

**If verification fails:**
- If `OPENCLAW_SESSION_ID` not set: This skill must run from within OpenClaw agent session. Escalate to human.
- If format invalid (not UUID): Session ID has wrong format. This may indicate a bug where session ID was incorrectly set to a routing key. Escalate to human with error details.

---

### Phase 1 — Verify Shell Setup

```bash
command -v cc-supervise && command -v cc-send && command -v cc-install-hooks && echo "OK"
```

If fails, message human to add aliases from **One-Time Machine Setup** section to `~/.zshrc` and run `source ~/.zshrc`. Wait for confirmation.

---

### Phase 2 — Register Hooks

```bash
cc-install-hooks <project-dir>
cat <project-dir>/.claude/settings.local.json | jq '.hooks | keys'
# Expected: ["Notification", "PostToolUse", "SessionEnd", "Stop"]
```

---

### Phase 3 — Start Session

Use `$OPENCLAW_SESSION_ID` variable, not `<session-id>` placeholder.

```bash
OPENCLAW_SESSION_ID=$OPENCLAW_SESSION_ID cc-supervise <project-dir>  # relay (default)
OPENCLAW_SESSION_ID=$OPENCLAW_SESSION_ID CC_MODE=autonomous cc-supervise <project-dir>  # autonomous
```

**⚠ Human action:** When Claude Code asks to trust directory, message human to run `tmux attach -t cc-supervise`, type `y`, Enter, then Ctrl-B D.

---

### Phase 3.5 — Verify Hook Notification

**CRITICAL:** After Claude Code starts, verify Hook notifications work before sending the real task.

```bash
# Verify session ID one more time before testing
echo "Current session ID: $OPENCLAW_SESSION_ID"
echo "This message should route back to session: $OPENCLAW_SESSION_ID"

# Wait 3 seconds for Claude Code to fully start
sleep 3

# Send test message
cc-send "Please respond with 'Hook test successful' and nothing else."
```

**Wait for `[cc-supervisor]` notification (timeout: 30 seconds):**
- **If notification received:** Verify the message prefix contains your session ID, then proceed to Phase 4
- **If no notification after 30 seconds:** Hook routing failed → troubleshoot:
  1. **Re-verify session ID:** Run `echo $OPENCLAW_SESSION_ID` and confirm it matches the current OpenClaw session
  2. **Check if message went to wrong session:** Look for the test message in other OpenClaw sessions or default channel
  3. Check `cat logs/events.ndjson | tail -5` to see if Hook fired
  4. Check `cat logs/notification.queue` for queued messages
  5. Run `cc-flush-queue` to retry
  6. Verify Hook installation: `cat <project-dir>/.claude/settings.local.json | jq .hooks`
  7. **If session ID is wrong:** Stop, fix session ID in Phase 0, restart from Phase 3
  8. Escalate to human with diagnostic info
  2. Check `cat logs/events.ndjson | tail -5` to see if Hook fired
  3. Check `cat logs/notification.queue` for queued messages
  4. Run `cc-flush-queue` to retry
  5. If still failing, verify Hook installation: `cat <project-dir>/.claude/settings.local.json | jq .hooks`
  6. Escalate to human with diagnostic info

**After receiving test notification:** Send `cc-send "Thank you, proceeding with the actual task."` then continue to Phase 4.

---

### Phase 4 — Send Initial Task

```bash
cc-send "<task description from Phase 0>"
```

### Phase 5 — Notification Loop

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

**Human reply → Action:** Task complete → Phase 6 | "y"/"n" → `cc-send --key y/n` | Number → `cc-send --key <N>` | Text → `cc-send "<text>"` | "continue" → `cc-send "Please continue."`

---

#### autonomous mode

OpenClaw handles all Stop types independently. Fully autonomous — all programming operations auto-approved.

**Core:** Check human interruption (`STOP`, `PAUSE`, `WAIT`, `HOLD`) → Read output → Parse format → Send "continue" option → Auto-approve programming ops → Escalate only when stuck

**Quick reference:**

| Stop type | Action | Escalate if |
|-----------|--------|-------------|
| Complete | Notify → Phase 6 | — |
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

### Phase 6 — Verify and Report

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
```

Then: `source ~/.zshrc`

---

## End-to-End Test

Test guide: `~/.openclaw/skills/cc-supervisor/example-project/E2E_TEST.md`
