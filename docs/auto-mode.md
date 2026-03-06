# Auto Mode - Detailed Guide

**Mode**: `auto`
**Control**: OpenClaw handles only deterministic, low-risk supervisor actions
**Use when**: Long tasks where human wants fewer interruptions but still wants clear escalation boundaries

---

## Overview

OpenClaw is a **small state machine**, not a decision-maker. It may auto-handle only documented low-risk prompts, then return to waiting. It must not invent project policy, rewrite the task, or inject new work such as tests, commits, or merges unless the human explicitly sends that instruction via `cc ...`.

**Core principle:** Only messages starting with `cc` are task content for Claude Code. All other human messages are supervisor commands, simple key replies, or meta-instructions.

---

## Human Message Handling

| Message Type | Detection | Action |
|--------------|-----------|--------|
| **Task content** | Message starts with `cc` | Strip prefix, forward via `cc-send` |
| **Simple answer** | Exact `y` / `n` / `1` / `2` / `Enter` | Forward via `cc-send --key` |
| **Control command** | `cmd停止` | Interrupt Claude, wait for human instruction |
| **Continue command** | `cmd继续` | `cc-send "Please continue."` |
| **Status command** | `cmd检查` | Inspect current state, report back |
| **Exit command** | `cmd退出` | Request Phase 4 verification; final success still depends on Phase 4 checks |
| **Meta-instruction** (default) | Any other message | Persist to `logs/supervisor-state.json`; do NOT forward |

Supported persisted preferences:
- `不要自动继续` / `不要自动确认` → `auto_continue_simple_prompts=false`
- `恢复自动继续` / `恢复自动确认` → `auto_continue_simple_prompts=true`
- `完成前先让我看` / `先给我review` → `require_review_before_phase_4=true`
- `完成了直接结束` / `完成后直接汇报` → `require_review_before_phase_4=false`

---

## Human Intervention - Interrupt and Resume

| Human says | Action |
|------------|--------|
| `cmd停止` | Run `handle-human-reply.sh`; it sends `Escape` |
| `cmd继续` | Run `handle-human-reply.sh`; it sends `Please continue.` |
| `cmd检查` | Run `handle-human-reply.sh`; it returns a `snapshot` |
| `cmd退出` | Run `handle-human-reply.sh`; if it returns `next_phase=="phase_4"`, start Phase 4 verification |
| `cc <message>` | Run `handle-human-reply.sh`; it strips prefix and forwards to Claude |
| `y` / `n` / `1` / `2` / `Enter` | Run `handle-human-reply.sh`; it forwards the key directly |
| Any other message | Meta-instruction — persist locally, do NOT forward |

**CRITICAL:** `Ctrl+c` fully exits the Claude session. Only use `Escape` to interrupt. To resume after interrupt, send "continue".

---

## Action Chains

| Chain | Trigger | Action |
|-------|---------|--------|
| **L1** Send human intent | Human provides `cc ...` or a simple key reply | Forward exactly once via `cc-send` |
| **L2** Confirm continue | Claude asks a simple proceed/continue confirmation | `cc-send --key y` |
| **L3** Confirm recommended option | Claude presents options with a recommended one | `cc-send --key <recommended option>` |
| **L4** Completion candidate | Claude reports task complete with no pending prompt | Proceed to Phase 4 verification |
| **L5** Escalate | Blocked / needs real-environment testing / watchdog recurrence / verification failed | Notify human, wait for instruction |

**Flow:** L1 → L2/L3 (loop) → L4; L5 at any stage when blocked.

Where:
- L4 = completion candidate, not an automatic test/commit stage
- L5 = escalation to human

### Hard State-Machine Rules

1. **Only Phase 4 success or L5 escalation terminates a supervision round.**
   - L1/L2/L3 are non-terminal; after execution, return to `WAIT_EVENT`.
2. **Do not inject project policy.**
   - No default "run tests", "commit", or "merge main" messages unless the human explicitly sends them via `cc ...`.
3. **L4 is only a candidate.**
   - If output still contains questions, confirmations, or obvious errors, do not enter Phase 4; keep waiting or escalate.
4. **Honor persisted preferences.**
   - If `auto_continue_simple_prompts=false`, stop auto-confirming and escalate instead.
   - If `require_review_before_phase_4=true`, notify human before auto-reporting success.

### State Transition Table

| From | To | Guard |
|------|----|-------|
| `WAIT_EVENT` | L1 | Human message starts with `cc` |
| `WAIT_EVENT` | L1 | Human message is a simple key reply classified as `send_key` |
| `WAIT_EVENT` | L2 | Claude asks simple proceed/continue confirmation and auto-continue is enabled |
| `WAIT_EVENT` | L3 | Claude presents options with a recommended choice and no human review gate applies |
| `WAIT_EVENT` | L4 | Claude reports implementation complete and no pending prompt is visible |
| L1/L2/L3 | `WAIT_EVENT` | Action sent successfully and no terminal condition met |
| L4 | Phase 4 | Completion looks credible |
| Any | L5 | Blocked, real-environment requirement, repeated error, watchdog recurrence, disabled auto-continue, or system failure |

---

## L5 Escalation Triggers

**Escalate when:**
- API keys/credentials/URLs needed
- Real-environment testing required (real devices, real users, external services)
- Verification failed or output is ambiguous after a claimed completion
- Same error 3 times (stuck in loop)
- Watchdog fires more than once
- `auto_continue_simple_prompts=false` and Claude is waiting for confirmation
- System failures (Claude crashed, hooks broken)

**Two types of testing — never confuse:**
- **Automated tests** (`npm test`, `pytest`, etc.) happen only if the task or human explicitly asks Claude to run them
- **Real-environment tests** (manual QA, real device, live API) require human involvement → escalate

**Do NOT escalate for:**
- File/dependency/config/git operations when Claude is simply asking to continue
- Technical decisions that Claude can resolve itself
- Simple y/n or recommended-option prompts while auto-continue is still enabled

---

## Limits

| Limit | Threshold | Action |
|-------|-----------|--------|
| Total rounds | 30 | STOP. L5: "Reached 30-round limit." |
| Consecutive auto-confirms | 8 | STOP. L5 with last output. |
| Same error | 3 | STOP. L5 with error details. |
| Watchdog alerts | 2 | STOP. L5. No more auto-recovery. |

---

## Escalation Format (L5)

```
[cc-supervisor][auto] Escalation: <reason>

Type: <stop-type>
Rounds: <N>
Blocker: <issue-description>
Output: <last-10-lines>

Action needed: <what-human-should-do>

To reply to Claude, start your message with: cc <your-message>
Simple replies may use: y / n / 1 / 2 / Enter
Any message without `cc` is treated as a supervisor command or meta-instruction.
```

---

## Examples

### Example 1: Auto-approve simple confirmation

```
Claude: "Should I proceed with installing dependencies? (y/n)"
→ Trigger: L2
→ Action: cc-send --key y
```

### Example 2: Auto-approve recommended option

```
Claude: "Choose authentication method:
1) JWT (Recommended)
2) Session cookies"
→ Trigger: L3
→ Action: cc-send --key 1
```

### Example 3: Escalate for credentials

```
Claude: "I need the API key for the payment gateway"
→ Trigger: L5
→ Action: Escalate to human with context
```

### Example 4: Human meta-instruction

```
Human: "不要自动继续，完成前先让我看"
→ This is meta-instruction (no `cc` prefix)
→ Persist to logs/supervisor-state.json
→ Effects: auto_continue_simple_prompts=false, require_review_before_phase_4=true
→ Do NOT forward to Claude
```

### Example 5: Human task content

```
Human: "cc 修改登录超时时间为30秒"
→ This is task content (`cc` prefix)
→ Strip prefix, forward: cc-send "修改登录超时时间为30秒"
```
