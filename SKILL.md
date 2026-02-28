---
name: cc-supervisor
description: "MANDATORY: Use when human asks to run/supervise Claude Code, or when you receive [cc-supervisor] messages. Event-driven supervision via Hooks. DO NOT supervise Claude Code without this skill."
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

Event-driven supervision of Claude Code. Zero tokens while waiting.

```
Human → OpenClaw ── cc-send ──→ Claude Code (tmux)
            ↑                         │
            └── Hook notification ←───┘
```

---

## Trigger Rules

**MANDATORY:**
1. Receive `[cc-supervisor]` message → invoke this skill immediately
2. Human asks to run/supervise Claude Code → invoke this skill immediately

---

## Core Rules

1. **Act, don't narrate** — run commands immediately
2. **No confirmations** — never ask "should I proceed?"
3. **Get env vars yourself** — run commands to get `OPENCLAW_SESSION_ID`, don't ask human
4. **NEVER poll/sleep** — wait passively for `[cc-supervisor]` messages (Hooks push to you)
5. **Minimal output** — only contact human when needed

---

## Workflow

### Phase 0 — Gather Inputs

**Ask human:**
- Project directory (absolute path)
- Task description
- Mode: `relay` (default) or `autonomous`

**Get automatically (run these commands):**
```bash
# Get or create session ID
export OPENCLAW_SESSION_ID=${OPENCLAW_SESSION_ID:-$(uuidgen | tr '[:upper:]' '[:lower:]')}
echo "Session: $OPENCLAW_SESSION_ID"
```

---

### Phase 1 — Verify Setup

```bash
command -v cc-supervise && command -v cc-send && echo "OK"
```

If fails, tell human to add aliases (see One-Time Setup section below).

---

### Phase 2 — Register Hooks

```bash
cc-install-hooks <project-dir>
```

---

### Phase 3 — Start Session

```bash
# Use the variable you set in Phase 0
OPENCLAW_SESSION_ID=$OPENCLAW_SESSION_ID CC_MODE=<relay|autonomous> cc-supervise <project-dir>
```

If Claude Code shows directory trust prompt, tell human to:
1. Run `tmux attach -t cc-supervise`
2. Type `y` and press Enter
3. Detach with Ctrl-B D

---

### Phase 4 — Send Task

```bash
cc-send "<task description>"
```

---

### Phase 5 — Wait for Notifications

**CRITICAL:** Do NOT poll/sleep/check logs. Wait passively for `[cc-supervisor]` messages.

When you receive `[cc-supervisor]` message:
1. Read Claude Code's output
2. Classify the Stop type
3. Respond according to mode (relay or autonomous)

**Stop types:**
- **Task complete** → notify human, proceed to Phase 6
- **Yes/No** → read format (y/n? 1/2? a/b?), send correct option
- **Multiple choice** → select recommended/continue option
- **Open question** → answer with defaults or escalate if needs external info
- **Blocked** → attempt fix, escalate if same error 3x
- **In progress** → send "Please continue."

---

### Phase 6 — Report

Check output exists, then message human:
```
Task complete.
Mode: <relay|autonomous>
Project: <dir>
Summary: <what was done>
```

---

## Modes

### relay (default)
- Forward every notification to human
- Wait for human's reply before sending cc-send
- Human controls every step

### autonomous
- Handle all decisions automatically
- Only escalate when truly stuck:
  - Missing external info (production API keys)
  - Same error 3 times
  - System errors

**Autonomous decision flow:**
1. Check for human interruption (if human sent message with STOP/PAUSE, pause immediately)
2. Read Claude Code's actual output
3. Parse format (y/n, 1/2, a/b, yes/no, etc.)
4. Select "continue" option
5. Send cc-send command
6. Wait for next notification

**Full decision rules:** See `docs/AUTONOMOUS_DECISION_RULES.md`

---

## One-Time Setup

Add to `~/.zshrc`:

```bash
export CC_SUPERVISOR_HOME=~/.openclaw/skills/cc-supervisor

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

cc-send() { "$CC_SUPERVISOR_HOME/scripts/cc_send.sh" "$@"; }
```

Then: `source ~/.zshrc`

---

## Troubleshooting

**No notifications?**
1. Check: `echo $OPENCLAW_SESSION_ID`
2. Check queue: `cat "$CC_SUPERVISOR_HOME/logs/notification.queue"`
3. Retry: `cc-flush-queue`

**Agent polling/sleeping?**
- You're doing it wrong. Wait passively for `[cc-supervisor]` messages.
- Hooks push notifications to you automatically.
- Zero tokens while waiting.
