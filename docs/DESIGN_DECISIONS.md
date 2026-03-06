# cc-supervisor Design Decisions

## Supervision Modes

### Overview

cc-supervisor supports two supervision modes that fundamentally differ in who controls the interaction loop:

| Mode | Controller | Use Case |
|------|-----------|----------|
| `relay` | Human | Sensitive tasks, full control, learning how Claude works |
| `auto` | OpenClaw | Long tasks, autonomous execution, minimal human intervention |

---

## relay Mode

### Principle
Human is in the loop. OpenClaw notifies human of every Stop event and waits for human decision.

### Workflow
1. Claude Code stops → OpenClaw notifies human
2. Human reviews output and decides next action
3. Human sends reply
4. OpenClaw classifies reply and executes

### Human Message Classification

| Message Type | Examples | Action |
|--------------|----------|--------|
| Forward to Claude | `cc 实现登录`, `cc: 修复 bug` | Forward via `cc-send` |
| Exit round | `cmd退出` | Proceed to Phase 4 verification |
| Simple answer | `y`, `n`, `1`, `2` | Send key via `cc-send --key` |
| Continue | `cmd继续` | Send "Please continue." |
| Meta-instruction | "不要审核", "跳过确认", "直接推进" | Adjust OpenClaw behavior, do NOT forward |
| Control | `cmd停止` | Execute control action |
| Status | `cmd检查` | Inspect current state and report back |

### Meta-instruction Detection

Messages that do **not** start with `cc` are meta-instructions or supervisor commands by default.

**Critical:** Meta-instructions adjust OpenClaw's supervision strategy. They are NOT forwarded to Claude Code.

---

## auto Mode

### Principle

OpenClaw is a **state machine**, not a decision-maker. Its only job is to classify Claude's current state and route to the correct fixed-template action. OpenClaw never generates project-specific content or technical suggestions.

### Core Design Decision (2026-03-02)

**Problem:** OpenClaw was generating project-specific guidance (e.g., "Try: `<alternative suggestion>`"), acting as a technical advisor despite having no deep understanding of the project. Claude Code has far better project context.

**Solution:** Strict action chains — every message OpenClaw sends to Claude is a fixed template. OpenClaw classifies state, routes to a chain, executes the template. No free-form content generation.

### Action Chains

#### Main Flow (Happy Path)

| Chain | Trigger | Action |
|-------|---------|--------|
| **L1** Send new task | Human provides task | `cc-send "<task>"` (verbatim passthrough) |
| **L2** Confirm continue | Claude asks whether to continue (y/n, proceed?) | `cc-send --key y` |
| **L3** Confirm option | Claude presents multiple options with a recommended one | `cc-send --key <recommended option>` |
| **L4** Trigger automated tests | Claude reports task complete | `cc-send "Please run the tests."` |
| **L5** Trigger commit+merge | Claude reports automated tests passed | `cc-send "Please commit the current changes, merge them into main locally, and report completion."` |
| **L6** Report success | Claude reports commit+merge complete | Notify human, wait for new task |

#### Exception Path

| Chain | Trigger | Action |
|-------|---------|--------|
| **L7** Escalate to human | Blocked / needs real-environment testing / automated tests failed | Notify human, wait for instruction |

#### Flow Diagram

```
L1 → L2/L3 (loop) → L4 → L5 → L6
          ↓
         L7 (any stage, when blocked)
```

#### Hard State-Machine Rules

1. **Only L6 and L7 terminate a supervision round.**
   - L1/L2/L3/L4/L5 are non-terminal; after execution, return to `WAIT_EVENT`.
2. **L4 → L5 requires explicit TEST_PASS marker.**
   - If automated tests are not explicitly reported as passed, do not enter L5.
3. **L5 success requires merge + post-merge tests passed.**
   - If merge fails or post-merge tests fail, route directly to L7.

#### State Transition Table (from/to/guard)

| From | To | Guard |
|------|----|-------|
| `WAIT_EVENT` | L1 | Human provides task content |
| `WAIT_EVENT` | L2 | Claude asks simple proceed/continue confirmation |
| `WAIT_EVENT` | L3 | Claude presents options with a recommended choice |
| `WAIT_EVENT` | L4 | Claude reports implementation complete |
| L4 | L5 | Explicit automated `TEST_PASS` marker present |
| L5 | L6 | Commit completed, merge to `main` completed, post-merge tests passed |
| L5 | L7 | Commit/merge/post-merge test step fails |
| L1/L2/L3/L4/L5 | `WAIT_EVENT` | Action sent successfully and no terminal condition met |
| Any | L7 | Blocked, real-environment requirement, repeated error, or system failure |

### Key Rules

- **L1 is always human passthrough** — OpenClaw never rewrites the task
- **L2 and L3 are confirmation only** — OpenClaw selects what Claude recommends, never overrides
- **L7 describes the blocker, never suggests a solution** — Claude decides how to recover
- **No self-recovery** — OpenClaw does not retry with alternative suggestions; it escalates immediately
- **Two types of testing — never confuse:**
  - Automated tests (`npm test`, `pytest`, etc.) → Claude runs these → L4 triggers this
  - Real-environment tests (manual QA, real device, live API) → human must do these → L7 escalates

### Who Talks to Claude

Claude Code's conversation partner is **OpenClaw (agent)**, not the human directly. OpenClaw sends messages on the human's behalf. Claude should never assume a human is manually typing responses.

### Human Message Handling

| Message Type | Detection | Action |
|--------------|-----------|--------|
| Control command | `cmd停止` | Interrupt Claude, wait for human instruction |
| Continue command | `cmd继续` | Send "Please continue." |
| Status command | `cmd检查` | Inspect current state and report back |
| Exit command | `cmd退出` | Finish current round only when completion is confirmed |
| Meta-instruction | Any message **without** `cc` | Adjust OpenClaw behavior, do NOT forward |
| Task content | Message starts with `cc` | Strip prefix, forward to Claude (L1) |

**Human intervention — interrupt and resume:**

| Human says | Action |
|------------|--------|
| `cmd停止` | Send `cc-send --key Escape` repeatedly until Claude output shows "interrupted". Then wait. |
| `cmd继续` | `cc-send "Please continue."` |
| `cmd检查` | Run capture/status checks and report back |
| `cmd退出` | Finish current round only if completion is actually confirmed |
| `cc <message>` | Strip prefix, forward to Claude via `cc-send` |
| Any other message | Meta-instruction — adjust OpenClaw behavior only, do NOT forward |

**CRITICAL:** `Ctrl+c` fully exits the Claude session. Only use `Escape` to interrupt. To resume after interrupt, send "continue".

### Escalation Conditions (L7)

Escalate when:
- **Real external info needed**: API keys, credentials, URLs
- **Physical environment access**: Real devices, external services
- **Tests failed**: Claude cannot self-recover
- **Stuck in loop**: Same error 3 times
- **System failures**: Claude crashed, hooks broken

Do NOT escalate for:
- File/dependency/config/git operations → auto-approve
- Technical decisions (library choice, code structure) → Claude decides
- Simple y/n confirmations → L2
- Multiple-choice with recommended option → L3

### Escalation Format

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

## Design Rationale

### Why `cc` Prefix?

**Problem:** Single text channel carries two semantic types:
- Control messages (for OpenClaw)
- Data messages (for Claude Code)

**Alternatives considered:**
1. ❌ Text classification (LLM-based) → Too unreliable at boundaries
2. ❌ Explicit prefix for meta-instructions → Verbose, easy to forget
3. ❌ Long prefixes like `[toclaude]` → Deterministic but heavy for Discord/mobile input
4. ✅ Short explicit prefix for task content (`cc`) → Clear intent with low typing cost

**Decision:** In both modes, only `cc`-prefixed messages are task content. Everything else stays on the supervisor side unless it matches an explicit `cmd...` supervisor command.

### Why Different Rules for relay vs auto?

**relay mode:** Human makes all decisions → still benefits from a deterministic forwarding boundary

**auto mode:** OpenClaw makes decisions → human rarely sends task content → even more important that forwarding requires an explicit prefix

This design minimizes cognitive load in each mode's primary use case.

---

## Implementation Status

- ✅ SKILL.md updated with explicit `cc` forwarding gate
- ✅ relay/auto mode command gate documented
- ✅ Scripts enforce `cc` prefix handling via `scripts/parse-human-command.sh`
- ✅ Phase 3 execution is funneled through `scripts/handle-human-reply.sh`
- ✅ Tests verify parsing and fixed-action execution

---

## Notification Routing

### Problem

Messages were routing to webchat instead of the originating channel (e.g., Discord) because routing relied solely on environment variables that weren't always set correctly.

### Solution: Session-Based Routing

Query OpenClaw session metadata to determine the source channel and target, ensuring replies return to the correct channel.

**Routing strategy (priority order):**
1. Query session metadata via `openclaw sessions --json` → extract `deliveryContext.to`
2. Fall back to environment variables (`OPENCLAW_CHANNEL`, `OPENCLAW_TARGET`)
3. Infer channel from target format (e.g., `channel:123` → discord)

**Always use `--deliver` and `--reply-channel` parameters** when calling `openclaw agent`.

### Session Metadata Structure

```json
{
  "sessionId": "...",
  "deliveryContext": { "to": "channel:1464891798139961345" },
  "origin": { "label": "channel:...", "provider": "heartbeat", "from": "channel:..." }
}
```

Key functions in `scripts/lib/notify.sh`:
- `get_session_routing_info()` — queries session store for routing info
- `infer_channel_from_target()` — infers channel type from target format

---

## Future Considerations

### Tool-based Control (Not Implemented)

Instead of text-based classification, use structured tool calls:
```typescript
classify_message({
  message: "不要问我了，持续推进",
  options: ["meta_instruction", "task_content", "control_command"]
})
```

This would eliminate ambiguity but requires OpenClaw to support tool-based control flow.

### Multi-channel Support

If OpenClaw supports multiple channels (Discord, Slack, etc.), consider:
- Dedicated control channel for meta-instructions
- Separate task channel for Claude Code communication

This would provide physical separation instead of prefix-based separation.
