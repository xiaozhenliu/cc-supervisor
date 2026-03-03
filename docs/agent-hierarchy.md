# Agent Hierarchy Architecture

## Core Concept

**Claude Code is NOT an agent** — it's a tool process. The architecture supports two usage patterns:

### Pattern 1: Single Agent (Direct Usage)

```
User → Agent (primary role)
         ↓ invokes cc-supervisor skill
         ↓ sets CC_SUPERVISOR_ROLE=supervisor
       Same Agent (supervisor role) ← Role transition
         ↓ starts Claude Code
       Claude Code (tool process)
         ↓ hook fires
       Notify Agent (via OPENCLAW_SESSION_ID)
```

**Key point**: Same agent, different roles (primary → supervisor)

### Pattern 2: Agent Delegation (Two Agents)

```
User → Main Agent (delegator)
         ↓ delegates task
       Sub Agent (primary role) ← Different agent
         ↓ invokes cc-supervisor skill
         ↓ sets CC_SUPERVISOR_ROLE=supervisor
       Sub Agent (supervisor role) ← Role transition
         ↓ starts Claude Code
       Claude Code (tool process)
         ↓ hook fires
       Notify Sub Agent (via OPENCLAW_SESSION_ID)
         ↓ reports result
       Main Agent
```

**Key point**: Two different agents (Main delegates to Sub), Sub transitions from primary to supervisor

## Terminology Clarification

### Two Different Concepts

1. **Role** (Primary vs Supervisor)
   - Describes the state of an agent relative to cc-supervisor skill
   - Primary: Can invoke the skill
   - Supervisor: Currently executing supervision, cannot invoke skill again
   - **Same agent** transitions between roles

2. **Agent Relationship** (Main vs Sub)
   - Describes delegation between different agents
   - Main agent: Delegates tasks to other agents
   - Sub agent: Receives delegated tasks
   - **Different agents** in a delegation hierarchy

### Example: Main Delegates to Ruyi

```
Main agent (delegator)
  ↓ delegates
Ruyi agent (primary role) ← Different agent from Main
  ↓ invokes skill
Ruyi agent (supervisor role) ← Same agent (Ruyi), different role
  ↓ starts Claude Code
Claude Code (tool)
  ↓ hook notifies
Ruyi agent (supervisor role) ← Receives notification
  ↓ reports
Main agent (delegator) ← Back to Main
```

**Three entities**:
1. Main agent (delegator)
2. Ruyi agent (executor, transitions primary → supervisor)
3. Claude Code (tool)

## Role Definition (Flexible, Not Hardcoded)

### Primary Role
- **Definition**: Agent state before invoking cc-supervisor skill
- **Can be**: Any agent (main, ruyi, custom)
- **Environment**: `CC_SUPERVISOR_ROLE` is unset or `primary`
- **Can do**: Invoke cc-supervisor skill

### Supervisor Role
- **Definition**: Agent state after invoking cc-supervisor skill
- **Same agent**: The agent transitions to supervisor role
- **Environment**: `CC_SUPERVISOR_ROLE=supervisor`
- **Cannot do**: Invoke cc-supervisor skill again (prevents recursion)
- **Marked by**: `CC_SUPERVISOR_ROLE=supervisor`
- **Restriction**: Cannot invoke cc-supervisor skill again (prevents recursion)

## Self-Identification Mechanism

Agents identify their role via `CC_SUPERVISOR_ROLE` environment variable:

| Value | Role | Can Call Skill? | Meaning |
|-------|------|-----------------|---------|
| (unset) or `primary` | Primary | ✓ Yes | Can invoke cc-supervisor |
| `supervisor` | Supervisor | ✗ No | Already supervising, prevents recursion |

### Role Check in SKILL.md

```bash
# At skill entry point (Phase 0)
if [[ "${CC_SUPERVISOR_ROLE:-}" == "supervisor" ]]; then
  echo "ERROR: cc-supervisor skill cannot be invoked recursively"
  exit 1
fi

# Mark as supervisor
export CC_SUPERVISOR_ROLE=supervisor
```

## Key Understanding

### What is Claude Code?
- A CLI tool that runs in tmux
- Has its own internal session ID (visible in hook JSON)
- **Not an OpenClaw agent** — just an execution tool

### Who Should Receive Hook Notifications?
- **The caller** (whoever invoked the cc-supervisor skill)
- If sub agent (ruyi) calls the skill → notify ruyi
- If main agent calls the skill → notify main
- If run standalone → notify the user's session (if available)

### Session ID Confusion

There are TWO different session IDs:

| Session ID | Source | Purpose |
|------------|--------|---------|
| `OPENCLAW_SESSION_ID` (env var) | Caller's OpenClaw session | **Use this for hook notifications** |
| `session_id` (hook JSON) | Claude Code's internal session | For logging only, NOT for routing |

## Correct Hook Notification Logic

```bash
# ✓ CORRECT: Use caller's session ID from environment
notify "${OPENCLAW_SESSION_ID:-}" "$message" "$event_type"

# ✗ WRONG: Use Claude Code's internal session ID
notify "$SESSION_ID" "$message" "$event_type"  # $SESSION_ID from hook JSON
```

## Call Flow Examples

### Example 1: Sub Agent Calls Skill

```bash
# Main agent calls sub agent
openclaw agent --agent ruyi --message "Use cc-supervisor to fix bug"

# Sub agent (ruyi) executes skill
# Environment: OPENCLAW_SESSION_ID=<ruyi-session-id>

# Skill starts Claude Code
supervisor_run.sh
  ↓
# Writes logs/hook.env with OPENCLAW_SESSION_ID=<ruyi-session-id>

# Claude Code triggers hook
# Hook reads OPENCLAW_SESSION_ID from env or logs/hook.env
# Notification sent to <ruyi-session-id>

# Sub agent receives notification, processes it
# Sub agent decides whether to report to main agent
```

### Example 2: Standalone Execution

```bash
# User runs directly
OPENCLAW_SESSION_ID=<user-session> ./scripts/supervisor_run.sh

# Hook notifications go to <user-session>
```

## Implementation Details

### supervisor_run.sh Responsibilities

1. **Capture caller's session ID**
   ```bash
   export OPENCLAW_SESSION_ID="${OPENCLAW_SESSION_ID:-}"
   export OPENCLAW_AGENT_ID="${OPENCLAW_AGENT_ID:-ruyi}"
   ```

2. **Persist to logs/hook.env** (for reliability)
   ```bash
   cat > logs/hook.env << EOF
   OPENCLAW_SESSION_ID=${OPENCLAW_SESSION_ID}
   OPENCLAW_AGENT_ID=${OPENCLAW_AGENT_ID}
   OPENCLAW_CHANNEL=${OPENCLAW_CHANNEL}
   OPENCLAW_TARGET=${OPENCLAW_TARGET}
   EOF
   ```

### on-cc-event.sh Responsibilities

1. **Restore environment if missing**
   ```bash
   if [[ -z "${OPENCLAW_SESSION_ID:-}" ]]; then
     source logs/hook.env
   fi
   ```

2. **Use caller's session for notifications**
   ```bash
   notify "${OPENCLAW_SESSION_ID:-}" "$message" "$event_type"
   ```

3. **Log Claude Code's session for debugging**
   ```bash
   # SESSION_ID from hook JSON is logged to events.ndjson
   # But NOT used for notification routing
   ```

## Why This Design?

### ✓ Correct Behavior
- Hook notifications go to the **caller** (sub agent)
- Sub agent can process and decide what to report
- Maintains proper call chain: Claude Code → Sub Agent → Main Agent

### ✗ Wrong Alternatives

**Alternative 1: Use Claude Code's session ID**
```bash
notify "$SESSION_ID" "$message"  # from hook JSON
```
Problem: Sends notification to Claude Code's internal session, which is not an OpenClaw agent session.

**Alternative 2: Always notify main agent**
```bash
notify "$MAIN_AGENT_SESSION_ID" "$message"
```
Problem: Bypasses sub agent, breaks the call chain.

## Environment Variable Reference

| Variable | Set By | Used By | Purpose |
|----------|--------|---------|---------|
| `OPENCLAW_SESSION_ID` | Caller (main/ruyi agent) | hook scripts | Caller's session for notifications |
| `OPENCLAW_AGENT_ID` | Caller or supervisor_run.sh | notify.sh | Agent type (main/ruyi) |
| `OPENCLAW_CHANNEL` | Caller or supervisor_run.sh | notify.sh | Delivery channel (discord/telegram) |
| `OPENCLAW_TARGET` | Caller or supervisor_run.sh | notify.sh | Delivery target (channel ID/phone) |

## Troubleshooting

### Problem: Notifications go to wrong session

**Symptom**: Hook notifications arrive at main agent instead of sub agent

**Diagnosis**:
```bash
# Check what session ID the hook is using
tail logs/events.ndjson | jq -r '.session_id'  # Claude Code's internal session
cat logs/hook.env | grep OPENCLAW_SESSION_ID   # Caller's session (should be used)
```

**Root Cause**:
- `OPENCLAW_SESSION_ID` environment variable points to main agent
- Should point to sub agent (ruyi) when sub agent calls the skill

**Solution**:
- Ensure sub agent's environment has correct `OPENCLAW_SESSION_ID`
- This is OpenClaw's responsibility when spawning sub agents
- cc-supervisor uses whatever `OPENCLAW_SESSION_ID` it receives

### Problem: Hook environment variables missing

**Symptom**: Hook fails to send notifications, logs show "OPENCLAW_SESSION_ID not set"

**Solution**:
- `logs/hook.env` provides fallback
- Hook automatically sources it if env vars are missing
- Check that `supervisor_run.sh` successfully wrote `logs/hook.env`

## Summary

1. **Claude Code is a tool, not an agent**
2. **Hook notifies the caller** (via `OPENCLAW_SESSION_ID` env var)
3. **Caller can be main agent, sub agent, or user session**
4. **logs/hook.env provides reliable fallback** for environment variables
5. **Hook JSON's session_id is for logging only**, not routing
