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
| `auto` | OpenClaw | Long tasks, delegate to agent |

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

### Phase 0 — Gather inputs

**Human provides:** Project directory (absolute path) | Task description | Mode: `relay` or `auto` (default: `relay`)

---

### Phase 1 — Start (automated)

Run one command. It handles session ID validation, hook install, tmux startup, and hook verification automatically.

```bash
cc-start <project-dir> [relay|auto]
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

**⚠ Auto mode safety gate:** `cc-start` in auto mode prompts human for explicit `yes` confirmation before proceeding (all permissions will be auto-approved via `--dangerously-skip-permissions`). Non-interactive callers skip this gate.

---

### Phase 2 — Send Initial Task

```bash
cc-send "<task description from Phase 0>"
```

### Phase 3 — Notification Loop

**CRITICAL:** Do NOT poll/sleep/check logs. Wait passively for `[cc-supervisor]` messages. Zero tokens while waiting.

**Safety net:** Watchdog daemon auto-flushes pending notifications every 30s. No manual `cc-flush-queue` needed.

**Poll behavior:** Poll daemon uses smart detection — it analyzes Claude Code output region (above tmux separators) and only notifies when intervention is clearly needed:

- Contains `…` (ellipsis) → Claude is working, **stays silent**
- Error signals (`error`, `denied`, `failed`) → notifies "Tool error detected"
- Choice prompts (arrow + number) → notifies "Choice pending"
- Question prompts (`?` + question words) → notifies "Question pending"
- Unknown state → notifies "Unknown status — verify manually"

**IMPORTANT:** When you receive a poll notification, NEVER act on it immediately. Always run `cc-capture --tail 10` first to verify the current state, then decide whether to intervene.

#### Human Message Classification

Before acting on ANY human message during Phase 3, classify it first:

| Category | Signals | Action |
|----------|---------|--------|
| **Meta-instruction** (行为调整) | References agent behavior: "不要…"/"只做…"/"跳过…"/"直接…"/"你应该…" / "don't review" / "just confirm" / "skip X" / "be more aggressive" | Internalize. Adjust YOUR behavior. Do NOT forward to CC. |
| **Task content** (转发内容) | Technical instructions for CC: code changes, feature requests, bug descriptions, file paths | Forward via `cc-send` |
| **Control command** | `STOP` / `PAUSE` / `WAIT` / `HOLD` | Execute control action |
| **Ambiguous** | Could be either meta-instruction or task content | Ask human: "This is for me (adjust behavior) or for Claude Code (forward)?" |

**Rule:** NEVER forward meta-instructions to Claude Code. If human says "不要审核代码，只做确认，推进任务直到完成", this adjusts YOUR supervision strategy — it is NOT a prompt for CC.

---

#### Stop event classification

Stop notifications include only the last ~10 lines of output. If insufficient to decide, use targeted capture instead of dumping everything:

- `cc-capture --tail 20 --grep "error|fail|denied"` — find errors
- `cc-capture --tail 20 --grep "y/n|yes/no|1\)|2\)|a\)|b\)"` — find prompts
- `cc-capture --tail 20 --grep "complete|done|finished|已完成"` — check completion
- `cc-capture --tail 30` — full dump only as last resort

Read Claude Code's output to see format (y/n, 1/2, a/b). Use that exact format.

**Examples:** `"(y/n)"` → `cc-send --key y` | `"1) Continue 2) Abort"` → `cc-send --key 1` | `"a) Yes b) No"` → `cc-send --key a`

**cc-send:** `cc-send "text"` (full text) | `cc-send --key y` (single char) | `cc-send --key Escape` (cancel) | `cc-send --key Ctrl+c` (interrupt) | `cc-send --key Up` (directional) | `cc-send --key Enter` (confirm)

**Supported key names:** `Escape` `Enter` `Tab` `Space` `BSpace` `Up` `Down` `Left` `Right` `Home` `End` `PageUp` `PageDown` `DC` (delete) — plus any single character. Modifier combos: `Ctrl+<key>` `Alt+<key>` `Ctrl+Shift+<key>` (auto-normalized to tmux `C-`/`M-`/`S-` syntax). Common aliases auto-normalized: `Esc`→`Escape`, `Return`→`Enter`, `Backspace`→`BSpace`, `Delete`→`DC`.

---

#### relay mode

OpenClaw notifies human of every Stop event. Never acts on its own.

**Stop is Task Complete when ALL of:**
- Output contains terminal language: "Task complete" / "Done" / "Finished" / "已完成"
- No pending questions or confirmations
- When uncertain → forward to human. Never assume complete.

**Format:** `[cc-supervisor][relay] Stop (<type>): <output>`

**Human reply → Action:** Task complete → Phase 4 | "y"/"n" → `cc-send --key y/n` | Number → `cc-send --key <N>` | "continue" → `cc-send "Please continue."` | **Classify first** (see Human Message Classification) → meta-instruction: adjust behavior | task content: `cc-send "<text>"`

---

#### auto mode

OpenClaw handles all Stop types independently. Fully auto — all programming operations auto-approved.

**Core:** Check human interruption (`STOP`, `PAUSE`, `WAIT`, `HOLD`) → **Classify human messages first** (see Human Message Classification; meta-instructions adjust behavior, only task content forwards) → Read output → Parse format → Send "continue" option → Auto-approve programming ops → Escalate only when stuck

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

**Escalation:** `[cc-supervisor][auto] Escalation: Type: <type> | Reason: <why> | Rounds: <N> | Blocker: <issue> | Output: <output> | Need: <info>`

**Full rules:** `~/.openclaw/skills/cc-supervisor/docs/AUTONOMOUS_DECISION_RULES.md`

---

#### Other notification types

- `PostToolUse: Tool error` → relay: notify; auto: self-correct once, escalate on recurrence
- `Notification: <msg>` → relay: notify; auto: handle if routine, escalate if judgment needed
- `SessionEnd` →
  1. Notify human: "[cc-supervisor] Session ended (session_id=...)"
  2. Check if task was complete (review last Stop event content)
  3. If task incomplete → escalate: "Session ended unexpectedly. Last output: <cc-capture --tail 20>"
  4. If task complete → proceed to Phase 4
- `⏰ watchdog` → `cc-capture --tail 20 --grep "error|waiting|blocked|y/n"`; relay: forward to human; auto:
  - 1st alert: `cc-send "Please continue."` + record alert count internally
  - 2nd alert: STOP sending continue. Escalate: `[cc-supervisor][auto] Escalation: Type: watchdog | Reason: 2nd inactivity timeout | Rounds: <N> | Blocker: no activity for <Xs> | Output: <cc-capture --tail 20> | Need: human check`
  - 3rd+ alert: escalate only, no continue

---

### Phase 4 — Verify and Report

1. Run `cc-capture --tail 20 --grep "complete|done|error|fail|summary"` to check final status
2. If unclear, run `cc-capture --tail 40` for full context
3. Confirm output has substantive content (not empty, not pure errors)
4. If output is empty or errors only → do NOT report complete. Escalate:
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
