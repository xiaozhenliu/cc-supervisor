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

### Command Execution Context (Important)

When this skill runs inside OpenClaw, non-interactive shell aliases/functions (for example `cc-start`, `cc-send`, `cc-capture`) may not be loaded.

Always use script absolute paths:

```bash
CC_SUPERVISOR_HOME="${CC_SUPERVISOR_HOME:-$HOME/.openclaw/skills/cc-supervisor}"
"$CC_SUPERVISOR_HOME/scripts/<script>.sh" ...
```

Do NOT assume `~/.zshrc` one-time setup is loaded in skill runtime.

### Phase 0 — Gather inputs

**Human provides:** Project directory (absolute path) | Task description | Mode: `relay` or `auto` (default: `relay`)

**That's it.** No manual checks needed. Phase 1 handles everything.

---

### Phase 1 — Start (automated)

Run one command. It handles all checks, hook install, tmux startup, and verification automatically.

```bash
CC_SUPERVISOR_HOME="${CC_SUPERVISOR_HOME:-$HOME/.openclaw/skills/cc-supervisor}"
"$CC_SUPERVISOR_HOME/scripts/cc-start.sh" <project-dir> [relay|auto]
```

**What cc-start does internally:**
- Validates required commands (openclaw, tmux, jq, uuidgen)
- Validates or auto-generates OPENCLAW_SESSION_ID
- Installs hooks
- Starts tmux session
- Verifies routing

**Read the output carefully:**
- `=== cc-start complete ===` → proceed to Phase 2
- `ERROR: Missing required commands: ...` → install missing commands, retry
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

OpenClaw notifies human of every Stop event. Never acts on its own. Human makes all decisions.

**Workflow:**
1. Receive Stop event → Notify human with output
2. Wait for human reply
3. Classify human reply
4. Execute based on classification

**Stop is Task Complete when ALL of:**
- Output contains terminal language: "Task complete" / "Done" / "Finished" / "已完成"
- No pending questions or confirmations
- When uncertain → forward to human. Never assume complete.

**Notification format:** `[cc-supervisor][relay] Stop (<type>): <output>`

**Human reply classification:**

| Reply Type | Examples | Action |
|------------|----------|--------|
| **Task complete** | "done" / "完成" / "好的" | Proceed to Phase 4 |
| **Simple answer** | "y" / "n" / "1" / "2" | `cc-send --key <answer>` |
| **Continue** | "continue" / "继续" | `cc-send "Please continue."` |
| **Meta-instruction** | "不要审核" / "跳过确认" / "直接推进" | Adjust YOUR behavior, do NOT forward |
| **Task content** | "实现登录" / "修复这个bug" / file paths | `cc-send "<text>"` |
| **Control** | "stop" / "pause" / "暂停" / "停" | Execute control action |
| **Ambiguous** | Could be either | Ask: "This is for me (adjust behavior) or for Claude Code (forward)?" |

**Classification rules:**

1. **Meta-instruction signals** (adjust YOUR behavior, do NOT forward):
   - References agent behavior: "不要…" / "只做…" / "跳过…" / "直接…" / "你应该…"
   - English: "don't review" / "just confirm" / "skip X" / "be more aggressive"
   - Workflow adjustments: "不要问我" / "持续推进" / "自动处理"

2. **Task content signals** (forward via cc-send):
   - Technical instructions: code changes, feature requests, bug descriptions
   - File paths, function names, specific implementations
   - Answers to Claude's technical questions

3. **When uncertain**: Ask human explicitly

**CRITICAL:** If human says "不要审核代码，只做确认，推进任务直到完成", this adjusts YOUR supervision strategy — it is NOT a prompt for Claude Code.

---

#### auto mode

OpenClaw is a **state machine**, not a decision-maker. Classify Claude's state → route to the correct chain → execute fixed template. Never generate project-specific content.

**Core principle:** Human messages are meta-instructions by default. OpenClaw never rewrites tasks or suggests technical solutions.

**Human message handling:**

| Message Type | Detection | Action |
|--------------|-----------|--------|
| **Control command** | "stop" / "pause" / "暂停" / "停" | Interrupt Claude, wait for human instruction |
| **Meta-instruction** (default) | Any message without `[toclaude]` prefix | Internalize. Adjust YOUR behavior. Do NOT forward. |
| **Task content** | Message starts with `[toclaude]` | Strip prefix, forward via `cc-send` (L1) |

**Human intervention — interrupt and resume:**

| Human says | Action |
|------------|--------|
| "stop" / "pause" / "暂停" / "停" | Send `cc-send --key Escape` repeatedly until Claude output shows "interrupted". Then wait. |
| "continue" / "继续" (after pause) | `cc-send "Please continue."` |
| `[toclaude] <message>` | Strip prefix, forward to Claude via `cc-send` |
| Any other message | Meta-instruction — adjust OpenClaw behavior only, do NOT forward |

**CRITICAL:** `Ctrl+c` fully exits the Claude session. Only use `Escape` to interrupt. To resume after interrupt, send "continue".

**Action chains:**

| Chain | Trigger | Action |
|-------|---------|--------|
| **L1** Send new task | Human provides task via `[toclaude]` | `cc-send "<task>"` (verbatim) |
| **L2** Confirm continue | Claude asks whether to continue (y/n, proceed?) | `cc-send --key y` |
| **L3** Confirm option | Claude presents options with a recommended one | `cc-send --key <recommended option>` |
| **L4** Trigger automated tests | Claude reports task complete | `cc-send "Please run the tests."` |
| **L5** Trigger commit | Claude reports automated tests passed | `cc-send "Please commit the current changes."` |
| **L6** Report success | Claude reports commit complete | Notify human, wait for new task |
| **L7** Escalate | Blocked / needs real-environment testing / automated tests failed | Notify human, wait for instruction |

**Flow:** L1 → L2/L3 (loop) → L4 → L5 → L6; L7 at any stage when blocked.

**L7 escalate when:**
- API keys/credentials/URLs needed
- Real-environment testing required (real devices, real users, external services) — Claude cannot do this
- Automated tests failed and Claude cannot self-recover
- Same error 3 times (stuck in loop)
- System failures (Claude crashed, hooks broken)

**Two types of testing — never confuse:**
- **Automated tests** (`npm test`, `pytest`, etc.) → Claude runs these → L4 triggers this
- **Real-environment tests** (manual QA, real device, live API) → human must do these → L7 escalates

**Do NOT escalate:**
- File/dependency/config/git operations → auto-approve
- Technical decisions → Claude decides
- Simple y/n → L2
- Multiple choice with recommended option → L3

**Limits:**

| Limit | Threshold | Action |
|-------|-----------|--------|
| Total rounds | 30 | STOP. L7: "Reached 30-round limit." |
| Consecutive L2 | 8 | STOP. L7 with last output. |
| Same error | 3 | STOP. L7 with error details. |
| Watchdog alerts | 2 | STOP. L7. No more auto-recovery. |

**Escalation format (L7):**

```
[cc-supervisor][auto] Escalation: <reason>

Type: <stop-type>
Rounds: <N>
Blocker: <issue-description>
Output: <last-10-lines>

Action needed: <what-human-should-do>

To reply to Claude, use: [toclaude] <your-message>
To adjust my behavior, reply without prefix.
```

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

**Routing Strategy (Reliable):**

The system uses a **session-based routing** approach to ensure notifications return to the correct channel:

1. **Query session metadata** (primary): Extract routing info from OpenClaw session store
   - `deliveryContext.to` → `lastTo` → `origin.to`
   - Automatically infers channel from target format (e.g., `channel:123` → discord)
2. **Fallback to environment variables**: If session not found, use `OPENCLAW_CHANNEL` and `OPENCLAW_TARGET`
3. **Explicit routing**: Always uses `--deliver` and `--reply-channel` for reliable delivery

**Command format:**
```bash
openclaw agent \
  --session-id "$OPENCLAW_SESSION_ID" \
  --message "[cc-supervisor] <event>" \
  --deliver \
  --reply-channel <channel> \
  --reply-to <target>
```

**Environment variables:**
- `OPENCLAW_SESSION_ID` (required): Current session identifier
- `OPENCLAW_CHANNEL` (optional): Fallback channel if session query fails
- `OPENCLAW_TARGET` (optional): Fallback target if session query fails
- `OPENCLAW_AGENT_ID` (optional): Agent ID for session lookup (default: main)

**Session ID validation:** The system validates `OPENCLAW_SESSION_ID` **before** starting the tmux session (via `ensure-session-id.sh`). This ensures notifications will work from the start.

**Fallback behavior:**
- Session ID not set → fail-fast (no tmux session created)
- Session not found in store → use environment variables
- `openclaw` not in PATH → queue to `logs/notification.queue`
- Retry queued notifications: `cc-flush-queue`

**Why session-based routing is reliable:**
- Uses actual session source, not guessed environment variables
- Automatically adapts to different channels (discord/telegram/webchat)
- Prevents messages from going to wrong channel due to stale env vars

---

## Troubleshooting

**No notifications:**
- Check session ID: `echo $OPENCLAW_SESSION_ID`
- Check queue: `cat "$CC_SUPERVISOR_HOME/logs/notification.queue"`
- Flush queue: `cc-flush-queue`
- Verify session ID format: `bash "$CC_SUPERVISOR_HOME/scripts/ensure-session-id.sh"`

**Session ID validation fails:**
- `ERROR: OPENCLAW_SESSION_ID not set` → Must be set by OpenClaw agent environment
- For manual testing: `export OPENCLAW_SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')`
- Verify format: lowercase UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)

**Test notification routing:**
- Diagnose routing: `$CC_SUPERVISOR_HOME/scripts/diagnose-routing.sh`
- Test session routing: `$CC_SUPERVISOR_HOME/scripts/test-session-routing.sh`
- Send test notification: `$CC_SUPERVISOR_HOME/scripts/send-test-notification.sh`
- Test messages include timestamp, session ID, channel, and target for easy verification
- Check if message arrives in correct channel (discord/telegram) vs webchat

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
