# Archived: Flexible Agent Hierarchy Design

This document is historical and contains superseded terminology such as `primary` role values.
Do not use it as the current source of truth for `CC_SUPERVISOR_ROLE`.

## Problem Statement

Original design had issues:
1. Main agent was hardcoded as "main"
2. No way for agents to know their role dynamically
3. No protection against recursive skill invocation

## New Design

### Role Definition

**Primary Agent** (主 agent):
- Any agent that invokes cc-supervisor skill
- Can be `main`, `ruyi`, or any other agent
- Determined dynamically, not hardcoded

**Supervisor Agent** (子 agent):
- Agent executing the supervision task
- Receives hook notifications
- Cannot invoke cc-supervisor skill again (prevents recursion)

### Role Identification Mechanism

Use environment variable `CC_SUPERVISOR_ROLE`:

| Value | Meaning | Can Call Skill? |
|-------|---------|-----------------|
| (unset) or `primary` | Primary agent | ✓ Yes |
| `supervisor` | Supervisor agent | ✗ No (prevents recursion) |

### Implementation

#### 1. SKILL.md Entry Point

Add role check at the beginning:

```bash
# Check if already in supervisor role (prevent recursion)
if [[ "${CC_SUPERVISOR_ROLE:-}" == "supervisor" ]]; then
  echo "ERROR: cc-supervisor skill cannot be invoked recursively"
  echo "This agent is already executing a supervision task"
  exit 1
fi

# Mark this invocation as supervisor role
export CC_SUPERVISOR_ROLE=supervisor
```

#### 2. supervisor_run.sh

Pass role to tmux session:

```bash
# Set supervisor role for this execution context
export CC_SUPERVISOR_ROLE=supervisor

# Pass to tmux session
tmux new-session -d -s "$SESSION_NAME" \
  -e "CC_SUPERVISOR_ROLE=supervisor" \
  ...
```

#### 3. Hook Notification Flow

```
User → Primary Agent (any agent, CC_SUPERVISOR_ROLE unset)
         ↓ invokes cc-supervisor skill
         ↓ sets CC_SUPERVISOR_ROLE=supervisor
       Supervisor Agent (CC_SUPERVISOR_ROLE=supervisor)
         ↓ starts Claude Code
       Claude Code (tool process)
         ↓ hook fires
       Notify Supervisor Agent (via OPENCLAW_SESSION_ID)
         ↓ processes notification
       Supervisor Agent reports to Primary Agent
```

### Benefits

1. **Flexible**: Any agent can be primary agent
2. **Self-aware**: Agents know their role via environment variable
3. **Safe**: Prevents recursive skill invocation
4. **Clear**: Role is explicit, not inferred from agent ID

### Example Scenarios

#### Scenario 1: Main calls Ruyi

```bash
# Main agent (primary)
CC_SUPERVISOR_ROLE=unset
OPENCLAW_SESSION_ID=main-session-123

# Main invokes skill → delegates to Ruyi
openclaw agent --agent ruyi --message "Use cc-supervisor to fix bug"

# Ruyi agent (becomes supervisor)
CC_SUPERVISOR_ROLE=supervisor  # Set by skill
OPENCLAW_SESSION_ID=ruyi-session-456

# Hook notifications go to ruyi-session-456
```

#### Scenario 2: Ruyi calls directly

```bash
# Ruyi agent (primary, not supervisor yet)
CC_SUPERVISOR_ROLE=unset
OPENCLAW_SESSION_ID=ruyi-session-789

# Ruyi invokes skill directly
# Skill sets CC_SUPERVISOR_ROLE=supervisor

# Hook notifications go to ruyi-session-789
```

#### Scenario 3: Recursive call (blocked)

```bash
# Supervisor agent tries to call skill again
CC_SUPERVISOR_ROLE=supervisor
OPENCLAW_SESSION_ID=supervisor-session-999

# Skill checks role → ERROR: recursive invocation blocked
```

### Migration Path

1. Update SKILL.md with role check
2. Update supervisor_run.sh to set CC_SUPERVISOR_ROLE
3. Update logs/hook.env to include CC_SUPERVISOR_ROLE
4. Update docs/agent-hierarchy.md with new design
5. Test all scenarios

### Environment Variables Summary

| Variable | Set By | Purpose |
|----------|--------|---------|
| `CC_SUPERVISOR_ROLE` | Skill entry point | Role identification & recursion prevention |
| `OPENCLAW_SESSION_ID` | Calling agent | Hook notification routing |
| `OPENCLAW_AGENT_ID` | Calling agent | Agent type (for logging) |
| `OPENCLAW_CHANNEL` | Calling agent | Delivery channel |
| `OPENCLAW_TARGET` | Calling agent | Delivery target |
