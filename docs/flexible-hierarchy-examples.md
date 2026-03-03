# Flexible Agent Hierarchy Examples

## Example 1: Main Agent Delegates to Ruyi

```bash
# User talks to main agent
User: "Help me fix the bug in my project"

# Main agent (primary role)
CC_SUPERVISOR_ROLE=<unset>
OPENCLAW_SESSION_ID=main-session-abc

# Main agent decides to delegate to ruyi
openclaw agent --agent ruyi --message "Use cc-supervisor to fix bug in /path/to/project"

# Ruyi agent receives message (becomes primary for this task)
CC_SUPERVISOR_ROLE=<unset>
OPENCLAW_SESSION_ID=ruyi-session-xyz

# Ruyi invokes cc-supervisor skill
# Skill checks: CC_SUPERVISOR_ROLE is unset → OK to proceed
# Skill sets: CC_SUPERVISOR_ROLE=supervisor

# Now ruyi is supervisor
CC_SUPERVISOR_ROLE=supervisor
OPENCLAW_SESSION_ID=ruyi-session-xyz

# supervisor_run.sh starts Claude Code
# Hook notifications go to ruyi-session-xyz

# If ruyi tries to invoke cc-supervisor again → BLOCKED
```

## Example 2: Ruyi Invokes Directly

```bash
# User talks to ruyi directly
User: "Use cc-supervisor to analyze this codebase"

# Ruyi agent (primary role)
CC_SUPERVISOR_ROLE=<unset>
OPENCLAW_SESSION_ID=ruyi-session-123

# Ruyi invokes cc-supervisor skill
# Skill checks: CC_SUPERVISOR_ROLE is unset → OK
# Skill sets: CC_SUPERVISOR_ROLE=supervisor

# Ruyi becomes supervisor
CC_SUPERVISOR_ROLE=supervisor
OPENCLAW_SESSION_ID=ruyi-session-123

# Hook notifications go to ruyi-session-123
```

## Example 3: Custom Agent

```bash
# User has a custom agent "code-reviewer"
User: "Review this PR using Claude Code"

# code-reviewer agent (primary role)
CC_SUPERVISOR_ROLE=<unset>
OPENCLAW_SESSION_ID=code-reviewer-session-456

# code-reviewer invokes cc-supervisor skill
# Skill checks: CC_SUPERVISOR_ROLE is unset → OK
# Skill sets: CC_SUPERVISOR_ROLE=supervisor

# code-reviewer becomes supervisor
CC_SUPERVISOR_ROLE=supervisor
OPENCLAW_SESSION_ID=code-reviewer-session-456

# Hook notifications go to code-reviewer-session-456
```

## Example 4: Recursion Prevention

```bash
# Supervisor agent tries to delegate
CC_SUPERVISOR_ROLE=supervisor
OPENCLAW_SESSION_ID=supervisor-session-789

# Supervisor tries to invoke cc-supervisor skill
# Skill checks: CC_SUPERVISOR_ROLE == supervisor → BLOCKED

ERROR: cc-supervisor skill cannot be invoked recursively
This agent is already executing a supervision task
Supervisor agents cannot delegate to other agents
```

## Key Benefits

1. **No Hardcoded IDs**: Works with any agent (main, ruyi, custom)
2. **Self-Aware**: Agents know their role via environment variable
3. **Safe**: Prevents infinite recursion
4. **Flexible**: Primary agent is whoever calls the skill
5. **Clear**: Role is explicit, not inferred

## Environment Variables

| Variable | Primary Agent | Supervisor Agent |
|----------|---------------|------------------|
| `CC_SUPERVISOR_ROLE` | (unset) or `primary` | `supervisor` |
| `OPENCLAW_SESSION_ID` | Caller's session | Same (receives hooks) |
| `OPENCLAW_AGENT_ID` | Agent type (main/ruyi/custom) | Same |

## Call Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Any Agent (Primary)                                         │
│ CC_SUPERVISOR_ROLE=<unset>                                  │
│ OPENCLAW_SESSION_ID=<primary-session>                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ Invokes cc-supervisor skill
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ SKILL.md Entry Point                                        │
│ ✓ Check: CC_SUPERVISOR_ROLE != supervisor                  │
│ → Set: CC_SUPERVISOR_ROLE=supervisor                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Same Agent (Now Supervisor)                                │
│ CC_SUPERVISOR_ROLE=supervisor                               │
│ OPENCLAW_SESSION_ID=<primary-session>                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ Starts supervisor_run.sh
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Claude Code (Tool Process)                                  │
│ Runs in tmux with supervisor's environment                  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ Hook fires
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Hook Notification                                           │
│ Uses OPENCLAW_SESSION_ID → <primary-session>                │
│ Notifies supervisor agent                                   │
└─────────────────────────────────────────────────────────────┘
```
