# Phase 3 — Notification Loop

**Purpose:** Handle notifications from Claude Code and drive the task to completion.

---

## Critical Rules

**NEVER poll or sleep.** Wait passively for `[cc-supervisor]` messages. Zero tokens while waiting.

**Safety net:** Watchdog daemon auto-flushes pending notifications every 30s. No manual intervention needed.

---

## Notification Types

### 1. Stop Event

Claude Code completed a response and is waiting.

**Before handling, read the mode-specific guide:**
- **relay mode:** Read `docs/relay-mode.md`
- **auto mode:** Read `docs/auto-mode.md`

When the human replies, parse the raw message first:

```bash
"$CC_SUPERVISOR_HOME/scripts/handle-human-reply.sh" \
  --mode "$CC_MODE" \
  --message "$HUMAN_MESSAGE"
```

Interpret the JSON result:
- `executed==true` → the fixed action already ran
- `action=="send_key"` → a simple reply such as `y` / `n` / `1` / `2` was already forwarded as `cc-send --key`
- `action=="meta"` → adjust supervision behavior only
- `action=="status"` → use `snapshot` to report current state
- `next_phase=="phase_4"` → proceed to Phase 4

Hook notifications should also remind the human of the reply contract:
- `cc <内容>` → forward to Claude
- `y / n / 1 / 2 / Enter` → direct key reply
- `cmd继续 / cmd停止 / cmd检查 / cmd退出` → fixed supervisor commands
- any other message → supervisor-side only

### 2. Stop Event Classification

Stop notifications include last ~10 lines. Use targeted capture if needed:
- `cc-capture --tail 20 --grep "error|fail"` — errors
- `cc-capture --tail 20 --grep "y/n|1\\)|2\\)"` — prompts

Read Claude's output format and use `cc-send --key <char>` with exact format.

**Common keys:** `y` `n` `1` `2` `Escape` `Enter`

**Full list:** `Escape` `Enter` `Tab` `Space` `BSpace` `Up` `Down` `Left` `Right` `Home` `End` `PageUp` `PageDown` `DC`

### 3. PostToolUse: Tool Error

**relay mode:** Notify human
**auto mode:** Self-correct only for documented low-risk prompts; otherwise escalate on recurrence

### 4. Notification: <msg>

**relay mode:** Notify human
**auto mode:** Handle if routine and deterministic, escalate if judgment needed

### 5. SessionEnd

1. Notify human: `[cc-supervisor] Session ended (session_id=...)`
2. Check if task was complete (review last Stop event content)
3. If task incomplete → escalate: "Session ended unexpectedly. Last output: <cc-capture --tail 20>"
4. If task complete → proceed to Phase 4

### 6. ⏰ Watchdog

**relay mode:** Forward to human

**auto mode:**
- 1st alert: `cc-send "Please continue."` + record alert count internally
- 2nd+ alert: STOP sending continue, escalate

---

## Poll Behavior (Smart Detection)

Poll daemon analyzes Claude Code output region and only notifies when intervention needed:

- Contains `…` (ellipsis) → Claude is working, **stays silent**
- Error signals (`error`, `denied`, `failed`) → notifies "Tool error detected"
- Choice prompts (arrow + number) → notifies "Choice pending"
- Question prompts (`?` + question words) → notifies "Question pending"
- Unknown state → notifies "Unknown status — verify manually"

**IMPORTANT:** When you receive a poll notification, NEVER act immediately. Always run `cc-capture --tail 10` first to verify current state, then decide whether to intervene.

---

## Task Completion Detection

Task is a **completion candidate** when you receive a Stop event AND:
- Output contains terminal language: "Task complete" / "Done" / "Finished" / "已完成"
- No pending questions or confirmations
- When uncertain → forward to human (relay) or continue monitoring / escalate (auto)

**Never report complete without passing Phase 4 verification.**

---

## Loop Until Complete

Continue handling notifications until task completion is confirmed.

Then proceed to **Phase 4**.

---

## Next Step

Once task is confirmed complete, proceed to **Phase 4**.

**Read:** `docs/phase-4.md`
