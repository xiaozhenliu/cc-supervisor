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
| Task complete | "done", "完成", "好的" | Proceed to Phase 4 verification |
| Simple answer | "y", "n", "1", "2" | Send key via `cc-send --key` |
| Continue | "continue", "继续" | Send "Please continue." |
| Meta-instruction | "不要审核", "跳过确认", "直接推进" | Adjust OpenClaw behavior, do NOT forward |
| Task content | "实现登录", "修复bug", file paths | Forward via `cc-send` |
| Control | "STOP", "PAUSE" | Execute control action |

### Meta-instruction Detection

Messages that reference **OpenClaw's behavior** are meta-instructions:
- "不要…" / "只做…" / "跳过…" / "直接…" / "你应该…"
- "don't review" / "just confirm" / "skip X" / "be more aggressive"
- "不要问我" / "持续推进" / "自动处理"

**Critical:** Meta-instructions adjust OpenClaw's supervision strategy. They are NOT forwarded to Claude Code.

---

## auto Mode

### Principle
OpenClaw is in the loop. OpenClaw autonomously drives Claude Code and only escalates when truly stuck.

### Core Design Decision (2026-03-02)

**Problem:** In auto mode, OpenClaw was forwarding human meta-instructions to Claude Code, causing confusion.

**Solution:** Strict message type separation:
- **Human messages are meta-instructions by default**
- **To forward to Claude, human must use `[toclaude]` prefix**
- **OpenClaw escalates only when it cannot auto-resolve**

### Workflow
1. Claude Code stops → OpenClaw analyzes output
2. OpenClaw decides next action automatically
3. OpenClaw sends command to Claude Code
4. Repeat until task complete or escalation needed

### Human Message Handling

| Message Type | Detection | Action |
|--------------|-----------|--------|
| Control command | `STOP`, `PAUSE`, `WAIT`, `HOLD` | Execute immediately |
| Meta-instruction | Any message **without** `[toclaude]` | Adjust OpenClaw behavior |
| Task content | Message starts with `[toclaude]` | Strip prefix, forward to Claude |

### Examples

**Scenario 1: Human adjusts OpenClaw behavior**
```
Human: "不要问我了，持续推进"
OpenClaw: Internalizes → becomes more aggressive in auto-approving
Action: Does NOT forward to Claude
```

**Scenario 2: Claude needs external info**
```
Claude: "Please provide your Stripe API key"
OpenClaw: Detects need for real external info → escalates to human
Human: "[toclaude] 使用测试 key sk_test_123"
OpenClaw: Strips prefix → forwards "使用测试 key sk_test_123" to Claude
```

**Scenario 3: Human wants to skip a feature**
```
Claude: "Should I implement payment integration?"
OpenClaw: Escalates (business decision)
Human: "跳过支付功能"
OpenClaw: Interprets as meta-instruction → tells Claude to skip payment
```

### Escalation Conditions

OpenClaw escalates to human when:
- **Real external info needed**: API keys, credentials, URLs
- **Physical environment access**: Real devices, external services
- **Business decisions**: Which feature to build, architecture choices
- **Stuck in loop**: Same error 3 times
- **System failures**: Claude crashed, hooks broken

OpenClaw does NOT escalate for:
- File/dependency/config/git operations → auto-approve
- Technical decisions (library choice, code structure) → auto-decide
- Recoverable errors → retry with different approach
- Dev configs (ports, paths, test data) → use defaults

### Escalation Format

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

## Design Rationale

### Why `[toclaude]` Prefix?

**Problem:** Single text channel carries two semantic types:
- Control messages (for OpenClaw)
- Data messages (for Claude Code)

**Alternatives considered:**
1. ❌ Text classification (LLM-based) → Too unreliable at boundaries
2. ❌ Explicit prefix for meta-instructions → Verbose, easy to forget
3. ✅ Explicit prefix for task content → Rare in auto mode, clear intent

**Decision:** In auto mode, human messages are meta-instructions by default. This matches the mode's purpose: OpenClaw drives, human adjusts strategy.

### Why Different Rules for relay vs auto?

**relay mode:** Human makes all decisions → needs to send both meta-instructions and task content frequently → requires classification

**auto mode:** OpenClaw makes decisions → human rarely sends task content → default to meta-instruction, require explicit prefix for task content

This design minimizes cognitive load in each mode's primary use case.

---

## Implementation Status

- ✅ SKILL.md updated with new auto mode logic
- ✅ relay mode classification rules documented
- ⏳ Scripts need update to enforce `[toclaude]` prefix handling
- ⏳ Tests need update to verify mode separation

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
