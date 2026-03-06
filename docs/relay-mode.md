# Relay Mode - Detailed Guide

**Mode**: `relay` (default)
**Control**: Human makes all decisions
**Use when**: Sensitive tasks, full control required

---

## Overview

OpenClaw notifies human of every Stop event. Never acts on its own. Human makes all decisions.

## Workflow

1. Receive Stop event → Notify human with output
2. Wait for human reply
3. Run `handle-human-reply.sh`
4. Execute or report based on returned JSON

---

## Task Completion Detection

**Stop is Task Complete when ALL of:**
- Output contains terminal language: "Task complete" / "Done" / "Finished" / "已完成"
- No pending questions or confirmations
- When uncertain → forward to human. Never assume complete.

**Notification format:** `[cc-supervisor][relay] Stop (<type>): <output>`

---

## Human Reply Classification

| Reply Type | Examples | Action |
|------------|----------|--------|
| **Forward to Claude** | `cc 修复这个 bug` / `cc: 实现登录` | `cc-send "<text>"` |
| **Exit round** | `cmd退出` | Proceed to Phase 4 |
| **Simple answer** | "y" / "n" / "1" / "2" | `cc-send --key <answer>` |
| **Continue** | `cmd继续` | `cc-send "Please continue."` |
| **Meta-instruction** | "不要审核" / "跳过确认" / "直接推进" | Adjust YOUR behavior, do NOT forward |
| **Control** | `cmd停止` | Execute control action |
| **Status** | `cmd检查` | Inspect current state, report back |

---

## Classification Rules

### 1. Meta-instruction signals (adjust YOUR behavior, do NOT forward)

**Chinese patterns:**
- References agent behavior: "不要…" / "只做…" / "跳过…" / "直接…" / "你应该…"
- Workflow adjustments: "不要问我" / "持续推进" / "自动处理"

**English patterns:**
- "don't review" / "just confirm" / "skip X" / "be more aggressive"

### 2. Task content signals (forward via cc-send)

- Only messages starting with `cc` are task content
- Strip the `cc` prefix and forward the rest verbatim

### 3. When uncertain

Do not guess. If the message does not start with `cc`, treat it as a supervisor-side instruction.

---

## Critical Rules

**CRITICAL:** If human says "不要审核代码，只做确认，推进任务直到完成", this adjusts YOUR supervision strategy — it is NOT a prompt for Claude Code.

**Meta-instructions affect how YOU supervise, not what Claude does.**

---

## Examples

### Example 1: Meta-instruction

```
Human: "不要每次都问我，直接确认就好"
→ This is for YOU: adjust your behavior to be less interactive
→ Do NOT forward to Claude Code
```

### Example 2: Task content

```
Human: "cc 修改登录API的错误处理"
→ This is for Claude Code: technical instruction
→ Forward via: cc-send "修改登录API的错误处理"
```

### Example 3: Ambiguous

```
Human: "跳过测试"
→ No `cc` prefix
→ Treat as meta-instruction for supervision strategy, do NOT forward
```
