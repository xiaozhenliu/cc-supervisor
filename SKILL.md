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

### Step 1 — Start the supervised session

```bash
cc-supervise ~/Projects/my-app
```

Creates (or reuses) tmux session `cc-supervise`, starts Claude Code inside `~/Projects/my-app`, and launches the watchdog daemon (default timeout: 30 minutes).

### Step 2 — Send the initial task

```bash
cc-send "implement the login API"
```

### Step 3 — Wait for Hook notification (no polling)

When Claude Code finishes a turn, `on-cc-event.sh` calls `openclaw message send` with a summary.

| Notification | Meaning | Action |
|---|---|---|
| `[cc-supervisor][relay] Stop: <summary>` | Claude Code finished a turn (relay mode) | Read summary, decide next step |
| `[cc-supervisor][autonomous] Stop: <summary> \| ACTION_REQUIRED: decide_and_continue` | Claude Code finished a turn (autonomous mode) | OpenClaw evaluates and continues autonomously |
| `[cc-supervisor][*] PostToolUse: Tool error — <tool>: <msg>` | A tool call failed | Analyze error, send correction |
| `[cc-supervisor][*] Notification: <msg>` | Claude Code is waiting for input | Respond with `cc_send.sh` |
| `[cc-supervisor][*] SessionEnd: ...` | Session closed | Task complete or crashed — check logs |
| `⏰ watchdog: no activity for Xs` | Inactivity timeout | Run `cc_capture.sh`, decide to intervene |

> **Agent 轮询约定：** 每 30 分钟调用一次 `cc-flush-queue`，重试因 Gateway 临时不可用导致的积压通知，规避长时间停滞。

### Step 4 — Decision logic on Stop

```
if summary shows task is NOT complete:
    cc_send.sh "Continue: <specific next step>"

elif summary shows task is complete:
    Notify the human: "Task finished."

elif summary shows an error:
    cc_send.sh "Fix the error: <specific instruction>"
    # or notify human if the error requires human judgment
```

### Step 5 — Repeat until done

Each `cc_send.sh` triggers Claude Code → fires another `Stop` hook → notifies OpenClaw again.

### Step 6 — Handle timeout alerts

On receiving `⏰ watchdog: no activity for Xs`:

```bash
cc-capture --tail 60
```

Decide:
- Still working (false alarm) → wait longer
- Stuck waiting for input → `cc_send.sh "Please proceed"`
- Crashed/hung → `cc-supervise ~/Projects/my-app` (reattaches to existing session)

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
