# Auto Mode - Detailed Guide

**Mode**: `auto`
**Control**: OpenClaw drives autonomously
**Use when**: Long tasks, delegate to agent

---

## Overview

OpenClaw is a **state machine**, not a decision-maker. Classify Claude's state → route to the correct chain → execute fixed template. Never generate project-specific content.

**Core principle:** Human messages are meta-instructions by default. OpenClaw never rewrites tasks or suggests technical solutions.

---

## Human Message Handling

| Message Type | Detection | Action |
|--------------|-----------|--------|
| **Control command** | "stop" / "pause" / "暂停" / "停" | Interrupt Claude, wait for human instruction |
| **Meta-instruction** (default) | Any message without `[toclaude]` prefix | Internalize. Adjust YOUR behavior. Do NOT forward. |
| **Task content** | Message starts with `[toclaude]` | Strip prefix, forward via `cc-send` (L1) |

---

## Human Intervention - Interrupt and Resume

| Human says | Action |
|------------|--------|
| "stop" / "pause" / "暂停" / "停" | Send `cc-send --key Escape` repeatedly until Claude output shows "interrupted". Then wait. |
| "continue" / "继续" (after pause) | `cc-send "Please continue."` |
| `[toclaude] <message>` | Strip prefix, forward to Claude via `cc-send` |
| Any other message | Meta-instruction — adjust OpenClaw behavior only, do NOT forward |

**CRITICAL:** `Ctrl+c` fully exits the Claude session. Only use `Escape` to interrupt. To resume after interrupt, send "continue".

---

## Action Chains

| Chain | Trigger | Action |
|-------|---------|--------|
| **L1** Send new task | Human provides task via `[toclaude]` | `cc-send "<task>"` (verbatim) |
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

To reply to Claude, use: [toclaude] <your-message>
To adjust my behavior, reply without prefix.
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
→ This is meta-instruction (no [toclaude] prefix)
→ Internalize: skip L5 commit+merge chain, escalate after L4 instead
→ Do NOT forward to Claude
```

### Example 5: Human task content

```
Human: "[toclaude] 修改登录超时时间为30秒"
→ This is task content ([toclaude] prefix)
→ Strip prefix, forward: cc-send "修改登录超时时间为30秒"
```
