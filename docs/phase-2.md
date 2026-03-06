# Phase 2 — Send Initial Task

**Purpose:** Send the task description to Claude Code to begin execution.

---

## Command

```bash
cc-send "<task description from Phase 0>"
```

**Example:**
```bash
cc-send "Implement user login API with JWT authentication"
```

---

## What Happens

1. The task is sent to Claude Code running in the tmux session
2. Claude Code begins processing the task
3. Hooks will fire as Claude works (Stop, PostToolUse, etc.)
4. You will receive notifications via `[cc-supervisor]` messages

---

## Important Notes

- Send the task **exactly as provided by human** in Phase 0
- Do NOT modify or rewrite the task description
- Do NOT add your own interpretation or suggestions
- The task is sent verbatim to Claude Code

---

## After Sending

**Do NOT poll or check logs.** Wait passively for `[cc-supervisor]` messages.

The system is event-driven:
- Claude Code fires hooks on state changes
- Hooks send notifications via `openclaw agent --session-id ... --deliver`
- You receive `[cc-supervisor]` messages
- **Zero tokens consumed while waiting**

---

## Next Step

Wait for `[cc-supervisor]` messages. When you receive one, proceed to **Phase 3**.

**Read:** `docs/phase-3.md`
