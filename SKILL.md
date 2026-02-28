---
name: cc-supervisor
description: "MANDATORY: Use this skill when human asks to run/supervise/monitor Claude Code, or when you receive ANY message starting with [cc-supervisor]. This skill enables autonomous multi-turn supervision of Claude Code via Hook-driven notifications. DO NOT attempt to supervise Claude Code without this skill — you will fail."
version: 1.4.0
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

## Supervision Modes

| `CC_MODE` | Who decides | When to use |
|---|---|---|
| `relay` (default) | Human | Sensitive tasks, full control |
| `autonomous` | OpenClaw | Long tasks, delegate to agent |

PostToolUse errors and watchdog timeouts always escalate to human.

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
- `ERROR: OPENCLAW_SESSION_ID not set` → 无法自动修复，escalate to human
- `ERROR: OPENCLAW_TARGET not set` → 无法自动修复，escalate to human
- `ERROR: Missing scripts` → CC_PROJECT_DIR 配置错误，escalate to human
- `ERROR: Hook '...' not found after install` → 运行 `cat <project>/.claude/settings.local.json | jq .hooks` 诊断，escalate to human
- `TIMEOUT: ...` → 运行 `cc-flush-queue`，再次运行 `cc-start`
  - 若第 2 次仍 TIMEOUT → escalate to human，附上 `cc-capture --tail 30` 输出
  - 不要无限重试

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

**判断 Stop 是否为 Task Complete：**
- 输出中包含 "Task complete" / "Done" / "Finished" / "已完成" 等终止性语言
- 没有待回答的问题或待确认的操作
- 若不确定 → 转发给 human 判断

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

**Blocked 自修复策略：**
1. 第 1 次：cc-send "Please try a different approach to resolve: <error>"
2. 第 2 次：cc-send "The previous approach failed. Try: <alternative suggestion>"
3. 第 3 次：escalate to human

**Escalate:** Production API keys/URLs | 3x same error | System failures

**Do NOT escalate:** File/dependency/config/git ops | Technical decisions | Recoverable errors | Dev configs

**Limits:** Total: 30 | Consecutive "continue": 8 | Same error: 3 | Watchdog: 3

**Escalation:** `[cc-supervisor][autonomous] Escalation: Type: <type> | Reason: <why> | Rounds: <N> | Blocker: <issue> | Output: <output> | Need: <info>`

**Full rules:** `~/.openclaw/skills/cc-supervisor/docs/AUTONOMOUS_DECISION_RULES.md`

---

#### Other notification types

- `PostToolUse: Tool error` → relay: notify; autonomous: self-correct once, escalate on recurrence
- `Notification: <msg>` → relay: notify; autonomous: handle if routine, escalate if judgment needed
- `SessionEnd` →
  1. 通知 human: "[cc-supervisor] Session ended (session_id=...)"
  2. 检查任务是否已完成（查看最后一条 Stop 事件内容）
  3. 若任务未完成 → escalate: "Session ended unexpectedly. Last output: <cc-capture --tail 20>"
  4. 若任务已完成 → 进入 Phase 4
- `⏰ watchdog` → `cc-capture --tail 60`; relay: forward to human; autonomous:
  - 第 1 次：`cc-send "Please continue."` + 内部记录告警次数
  - 第 2 次：不再发 continue，escalate: `[cc-supervisor][autonomous] Escalation: Type: watchdog | Reason: 2nd inactivity timeout | Rounds: <N> | Blocker: no activity for <Xs> | Output: <cc-capture --tail 20> | Need: human check`
  - 第 3 次及以后：仅 escalate，不发 continue
- `[poll] snapshot` → If stuck → `cc-send "Please continue."`; if working → no action

---

### Phase 4 — Verify and Report

1. 运行 `cc-capture --tail 40` 获取最终输出
2. 确认输出中有实质性内容（非空、非纯错误信息）
3. 若输出为空或只有错误 → 不报告完成，escalate:
   `[cc-supervisor] Phase 4 verification failed: <reason> | Mode: <mode> | Rounds: <N> | Last output: <cc-capture --tail 10 output>`
4. 报告格式：`Task complete. Mode: <mode> | Rounds: <N> | Summary: <what was built>`

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
