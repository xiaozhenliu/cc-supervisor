# Auto Mode - Detailed Guide

**Mode**: `auto`
**Control**: OpenClaw drives autonomously
**Use when**: Long tasks, delegate to agent

---

## Overview

OpenClaw is a **state machine**, not a decision-maker. Classify Claude's state → route to the correct chain → execute fixed template. Never generate project-specific content.

**Core principle:** Only messages starting with `cc` are task content for Claude Code. All other human messages are supervisor commands or meta-instructions. OpenClaw never rewrites tasks or suggests technical solutions.

---

## Human Message Handling

| Message Type | Detection | Action |
|--------------|-----------|--------|
| **Task content** | Message starts with `cc` | Strip prefix, forward via `cc-send` (L1) |
| **Control command** | `cmd停止` | Interrupt Claude, wait for human instruction |
| **Continue command** | `cmd继续` | `cc-send "Please continue."` |
| **Status command** | `cmd检查` | Inspect current state, report back |
| **Exit command** | `cmd退出` | Exit current round and proceed to completion handling |
| **Meta-instruction** (default) | Any other message | Internalize. Adjust YOUR behavior. Do NOT forward. |

---

## Human Intervention - Interrupt and Resume

| Human says | Action |
|------------|--------|
| `cmd停止` | Run `handle-human-reply.sh`; it sends `Escape` |
| `cmd继续` | Run `handle-human-reply.sh`; it sends `Please continue.` |
| `cmd检查` | Run `handle-human-reply.sh`; it returns a `snapshot` |
| `cmd退出` | Run `handle-human-reply.sh`; if it returns `next_phase=="phase_4"`, continue to Phase 4 |
| `cc <message>` | Run `handle-human-reply.sh`; it strips prefix and forwards to Claude |
| Any other message | Meta-instruction — adjust OpenClaw behavior only, do NOT forward |

**CRITICAL:** `Ctrl+c` fully exits the Claude session. Only use `Escape` to interrupt. To resume after interrupt, send "continue".

---

## Action Chains

| Chain | Trigger | Action |
|-------|---------|--------|
| **L1** Send new task | Human provides task via `cc` | `cc-send "<task>"` (verbatim) |
| **L2** Confirm continue | Claude asks whether to continue (y/n, proceed?) | `cc-send --key y` |
| **L3** Confirm option | Claude presents options with a recommended one | `cc-send --key <recommended option>` |
| **L4** Trigger automated tests | Claude reports task complete | `cc-send "Please run the tests."` |
| **L5** Trigger commit+merge | Claude reports automated tests passed | `cc-send "Please commit the current changes, merge them into main locally, and report completion."` |
| **L6** Report success | Claude reports commit+merge complete | Notify human, wait for new task |
| **L7** Escalate | Blocked / needs real-environment testing / automated tests failed | Notify human, wait for instruction |

**Flow:** L1 → L2/L3 (loop) → L4 → L5 → L6; L7 at any stage when blocked.

Where:
- L4 = automated tests
- L5 = commit + merge to `main`
- L6 = success report after merge

### Hard State-Machine Rules

1. **Only L6 and L7 terminate a supervision round.**
   - L1/L2/L3/L4/L5 are non-terminal; after execution, return to `WAIT_EVENT`.
2. **L4 → L5 requires explicit TEST_PASS marker.**
   - If automated tests are not explicitly reported as passed, do not enter L5.
3. **L5 success requires merge + post-merge tests passed.**
   - If merge fails or post-merge tests fail, route directly to L7.

### State Transition Table (from/to/guard)

| From | To | Guard |
|------|----|-------|
| `WAIT_EVENT` | L1 | Human message starts with `cc` |
| `WAIT_EVENT` | L2 | Claude asks simple proceed/continue confirmation |
| `WAIT_EVENT` | L3 | Claude presents options with a recommended choice |
| `WAIT_EVENT` | L4 | Claude reports implementation complete |
| L4 | L5 | Explicit automated `TEST_PASS` marker present |
| L5 | L6 | Commit completed, merge to `main` completed, post-merge tests passed |
| L5 | L7 | Commit/merge/post-merge test step fails |
| L1/L2/L3/L4/L5 | `WAIT_EVENT` | Action sent successfully and no terminal condition met |
| Any | L7 | Blocked, real-environment requirement, repeated error, or system failure |

---

## L7 Escalation Triggers

**Escalate when:**
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

---

## Limits

| Limit | Threshold | Action |
|-------|-----------|--------|
| Total rounds | 30 | STOP. L7: "Reached 30-round limit." |
| Consecutive L2 | 8 | STOP. L7 with last output. |
| Same error | 3 | STOP. L7 with error details. |
| Watchdog alerts | 2 | STOP. L7. No more auto-recovery. |

---

## Escalation Format (L7)

```
[cc-supervisor][auto] Escalation: <reason>

Type: <stop-type>
Rounds: <N>
Blocker: <issue-description>
Output: <last-10-lines>

Action needed: <what-human-should-do>

To reply to Claude, start your message with: cc <your-message>
Any message without `cc` is treated as a supervisor command or meta-instruction.
```

---

## Examples

### Example 1: Auto-approve simple confirmation

```
Claude: "Should I proceed with installing dependencies? (y/n)"
→ Trigger: L2 (confirm continue)
→ Action: cc-send --key y
```

### Example 2: Auto-approve recommended option

```
Claude: "Choose authentication method:
1) JWT (Recommended)
2) Session cookies"
→ Trigger: L3 (confirm option)
→ Action: cc-send --key 1
```

### Example 3: Escalate for credentials

```
Claude: "I need the API key for the payment gateway"
→ Trigger: L7 (credentials needed)
→ Action: Escalate to human with context
```

### Example 4: Human meta-instruction

```
Human: "不要自动commit，让我review后再commit"
→ This is meta-instruction (no `cc` prefix)
→ Internalize: skip L5 commit+merge chain, escalate after L4 instead
→ Do NOT forward to Claude
```

### Example 5: Human task content

```
Human: "cc 修改登录超时时间为30秒"
→ This is task content (`cc` prefix)
→ Strip prefix, forward: cc-send "修改登录超时时间为30秒"
```
