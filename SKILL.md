---
name: cc-supervisor
description: Supervise Claude Code via event-driven Hooks. OpenClaw drives multi-turn tasks with zero polling — waits for Hook notifications instead of checking repeatedly, consuming zero tokens while idle.
version: 0.6.0
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

Teach OpenClaw to supervise Claude Code through multi-turn tasks without polling.

```
OpenClaw ── cc_send.sh (tmux send-keys) ──→ Claude Code (tmux, interactive)
    ↑                                               │
    │                                      Hook fires on event
    │                          (Stop / PostToolUse / Notification / SessionEnd)
    │                                               │
    └─── openclaw message send ←── on-cc-event.sh ──────────┘
                                  │
                     ~/.openclaw/skills/cc-supervisor/logs/events.ndjson
```

Key advantage: while waiting for Claude Code, OpenClaw consumes **zero tokens** (event-driven, not polling).

Human can observe at any time: `tmux attach -t cc-supervise`

---

## Installation

**Current method (manual install):**

```bash
git clone <repo-url> ~/.openclaw/skills/cc-supervisor
```

> `clawhub install cc-supervisor` will be available after publishing — not yet available.

---

## One-Time Setup (per machine)

### Step 1 — Install shell aliases

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# cc-supervisor install directory — change only this if you install elsewhere
export CC_SUPERVISOR_HOME=~/.openclaw/skills/cc-supervisor

cc-supervise() {
  local target="${1:?Usage: cc-supervise <project-dir>}"
  CC_PROJECT_DIR="$CC_SUPERVISOR_HOME" \
  CLAUDE_WORKDIR="$target" \
    "$CC_SUPERVISOR_HOME/scripts/supervisor_run.sh"
}

cc-install-hooks() {
  local target="${1:?Usage: cc-install-hooks <project-dir>}"
  CC_PROJECT_DIR="$CC_SUPERVISOR_HOME" \
  CLAUDE_WORKDIR="$target" \
    "$CC_SUPERVISOR_HOME/scripts/install-hooks.sh"
}

cc-send() {
  "$CC_SUPERVISOR_HOME/scripts/cc_send.sh" "$@"
}

cc-capture() {
  "$CC_SUPERVISOR_HOME/scripts/cc_capture.sh" "$@"
}

cc-flush-queue() {
  "$CC_SUPERVISOR_HOME/scripts/flush-queue.sh"
}
```

Then reload: `source ~/.zshrc`

---

## 通知配置

cc-supervisor 通过环境变量获取通知目标，无需配置文件。

### Agent 模式（OpenClaw 自动注入）

OpenClaw 在调用 skill 时自动注入以下变量：

| 变量 | 示例值 | 说明 |
|------|--------|------|
| `OPENCLAW_CHANNEL` | `discord` | 目标渠道 |
| `OPENCLAW_TARGET` | `1466784529527214122` | Discord 频道 ID |

### 人类手动模式

```bash
export OPENCLAW_CHANNEL=discord
export OPENCLAW_TARGET=1466784529527214122
cc-supervise ~/Projects/my-app
```

### 降级行为

- 变量未设置 → 跳过发送，仅记录日志
- `openclaw` 不在 PATH → 写入 `logs/notification.queue`
- 发送失败 → 写入 `logs/notification.queue`

调用 `cc-flush-queue` 重试积压通知。

---

## Per-Project Setup (once per project)

Register Hooks in the target project:

```bash
cc-install-hooks ~/Projects/my-app
```

Verify:

```bash
cat ~/Projects/my-app/.claude/settings.local.json | jq .hooks
```

Hooks are written to the target project's `.claude/settings.local.json` (project-local, gitignored).

---

## Supervision Modes

cc-supervisor supports two modes, controlled by the `CC_MODE` environment variable:

| `CC_MODE` | OpenClaw Behavior | Use Case |
|---|---|---|
| `relay` (default) | Notify on every key event; OpenClaw relays to human for each decision | Human-in-the-loop: human decides what to do next |
| `autonomous` | Stop events carry `ACTION_REQUIRED: decide_and_continue`; OpenClaw decides autonomously | Human delegates; OpenClaw drives the task to completion |

In both modes:
- **PostToolUse errors** always trigger notification (human or OpenClaw must be alerted)
- **Watchdog timeouts** always notify (inactivity could mean crash or deadlock)

### relay mode (default)

No extra configuration needed. OpenClaw calls `cc_send.sh` with human-provided instruction after each Stop notification.

```bash
cc-supervise ~/Projects/my-app
```

### autonomous mode

Set `CC_MODE=autonomous` before starting the session:

```bash
CC_MODE=autonomous cc-supervise ~/Projects/my-app
```

When Claude Code finishes a turn, the Stop notification includes an action marker:

```
[cc-supervisor][autonomous] Stop: <summary> | ACTION_REQUIRED: decide_and_continue
```

OpenClaw should interpret `ACTION_REQUIRED: decide_and_continue` as a signal to evaluate the summary and decide autonomously whether to continue, send a follow-up instruction, or escalate to the human.

---

## Supervision Workflow

The overall process is a **human-initiated, agent-executed** loop. The human defines the goal and makes judgment calls; OpenClaw handles the mechanical supervision.

### Roles

| Actor | Responsibilities |
|-------|-----------------|
| **Human** | Define task goal, choose supervision mode, confirm directory trust, make judgment calls on errors/blockers, decide when task is done |
| **OpenClaw Agent** | Start session, send prompts, wait for Hook notifications, route decisions per mode, escalate to human when needed |
| **Claude Code** | Execute the task inside tmux; fires Hooks on each state change |

---

### Phase 0 — Human: Initiate

The human tells OpenClaw:
- Which project directory to supervise (`<project-dir>`)
- What task Claude Code should perform
- Which mode to use: `relay` (human decides each step) or `autonomous` (OpenClaw drives to completion)

OpenClaw does not start until the human provides these three inputs.

---

### Phase 1 — Agent: One-Time Setup (per project)

If hooks are not yet registered in the target project, OpenClaw runs:

```bash
cc-install-hooks <project-dir>
```

This is idempotent — safe to run again if unsure.

---

### Phase 2 — Agent: Start Session

```bash
cc-supervise <project-dir>          # relay mode (default)
CC_MODE=autonomous cc-supervise <project-dir>   # autonomous mode
```

**⚠ Human action required — directory trust prompt:**
When Claude Code starts in a new directory for the first time, it displays a trust confirmation prompt in the terminal. OpenClaw must notify the human:

> "Claude Code is asking to trust `<project-dir>`. Please run `tmux attach -t cc-supervise`, confirm with `y`, then detach with Ctrl-B D."

OpenClaw waits until the human confirms before proceeding.

---

### Phase 3 — Agent: Send Initial Task

Once the session is running, OpenClaw sends the task the human provided in Phase 0:

```bash
cc-send "<task from human>"
```

---

### Phase 4 — Wait and Respond to Hook Notifications

OpenClaw waits for `openclaw message send` notifications. **No polling.**

Every 30 minutes with no notification, run `cc-flush-queue` to retry any queued messages.

#### relay mode — every notification goes to the human

| Notification | OpenClaw action |
|---|---|
| `[cc-supervisor][relay] Stop: <summary>` | Forward summary to human; wait for human's next instruction; send it with `cc-send` |
| `[cc-supervisor][relay] PostToolUse: Tool error — <tool>: <msg>` | Forward error to human; wait for instruction |
| `[cc-supervisor][relay] Notification: <msg>` | Forward to human; wait for instruction |
| `[cc-supervisor][relay] SessionEnd: ...` | Notify human: "Session ended. Task may be complete or crashed." |
| `⏰ watchdog: no activity for Xs` | Run `cc-capture --tail 60`; forward output to human; wait for instruction |

In relay mode, **OpenClaw never sends a follow-up prompt on its own**. Every `cc-send` call is driven by a human instruction.

#### autonomous mode — OpenClaw decides, escalates only when stuck

| Notification | OpenClaw action |
|---|---|
| `[cc-supervisor][autonomous] Stop: <summary> \| ACTION_REQUIRED: decide_and_continue` | Evaluate summary (see decision logic below); send next prompt or declare done |
| `[cc-supervisor][autonomous] PostToolUse: Tool error — <tool>: <msg>` | Attempt one self-correction via `cc-send`; if same error recurs, escalate to human |
| `[cc-supervisor][autonomous] Notification: <msg>` | Respond autonomously if the message is a routine prompt; escalate to human if it requires judgment |
| `[cc-supervisor][autonomous] SessionEnd: ...` | Notify human: "Session ended. Verifying artifacts…"; run artifact check; report result |
| `⏰ watchdog: no activity for Xs` | Run `cc-capture --tail 60`; attempt `cc-send "Please continue"`; if no response after one more timeout, escalate to human |

**Autonomous Stop decision logic:**

```
read <summary> from notification

if summary indicates task is NOT complete (still planning / files not yet created):
    cc-send "Please continue and complete all remaining files."

elif summary indicates an error or blocker:
    cc-send "There is an error: <description>. Please fix it and continue."
    # if same error appears again → escalate to human

elif summary indicates task is complete (files created / tests passing / done):
    notify human: "Task complete. Verifying artifacts…"
    → proceed to Phase 5
```

**Escalate to human when:**
- The same error appears twice in a row
- Claude Code asks a question that requires human judgment (credentials, destructive operations, ambiguous requirements)
- Watchdog fires twice without recovery
- More than 10 rounds have passed without completion

---

### Phase 5 — Agent: Verify and Report

When the task appears complete, OpenClaw verifies the output exists in `<project-dir>` and reports to the human:

```
Task supervision complete.
Mode: relay / autonomous
Rounds: <N>
Project dir: <project-dir>
Summary: <what was built>
```

The human decides whether to accept the result, request changes, or start a new task.

---

## Quick Reference

```bash
# Start supervised session
cc-supervise ~/Projects/my-app

# Send a prompt
cc-send "your task here"

# Capture recent output (diagnostics)
cc-capture --tail 50

# View event log
cat "$CC_SUPERVISOR_HOME/logs/events.ndjson" | jq .

# Observe as human
tmux attach -t cc-supervise
# Detach without closing: Ctrl-B, D

# Test watchdog with 1-minute timeout
CC_TIMEOUT=60 cc-supervise ~/Projects/my-app

# Retry queued notifications
cc-flush-queue
```

---

## End-to-End Test

To verify the full supervision loop with real Claude Code, follow the step-by-step guide:

```
~/.openclaw/skills/cc-supervisor/example-project/E2E_TEST.md
```

The guide walks through: copy test project → register hooks → start autonomous session → drive Claude Code to completion → verify artifacts.

---

## Event Log Format

Each line in `logs/events.ndjson`:

```json
// Stop event (tool_name is null for non-tool events)
{"ts":"2026-01-01T12:00:00Z","event_type":"Stop","session_id":"abc123","event_id":"evt456","summary":"Last 30 lines of pane output or last assistant message","tool_name":null}

// PostToolUse event (tool_name populated)
{"ts":"2026-01-01T12:00:01Z","event_type":"PostToolUse","session_id":"abc123","event_id":"evt457","summary":"Tool: Bash","tool_name":"Bash"}
```

---

## Troubleshooting

**通知未送达：**
1. 确认环境变量已设置：`echo $OPENCLAW_CHANNEL $OPENCLAW_TARGET`
2. 检查队列：`cat "$CC_SUPERVISOR_HOME/logs/notification.queue"`
3. 手动重试：`cc-flush-queue`
4. 检查事件日志：`cat "$CC_SUPERVISOR_HOME/logs/events.ndjson" | jq .`

**`openclaw` not in PATH:**
Notifications are queued to `logs/notification.queue`. Once `openclaw` is available,
run `cc-flush-queue` to retry.

**Session already exists:**
`cc-supervise` reattaches to the existing session (idempotent). To force a fresh session:
```bash
tmux kill-session -t cc-supervise && cc-supervise ~/Projects/my-app
```
