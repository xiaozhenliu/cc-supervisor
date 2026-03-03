# Phase 1 — Start (Automated)

**Purpose:** Start tmux session with Claude Code and verify hook routing.

---

## Session ID Resolution (Critical First Step)

**CRITICAL**: `OPENCLAW_SESSION_ID` must be available before running cc-start.

### How it works:
1. If `OPENCLAW_SESSION_ID` is set → validate and use it
2. If not set → query session store using `OPENCLAW_AGENT_ID` + `OPENCLAW_CHANNEL` + `OPENCLAW_TARGET`
3. `cc-start` handles this automatically via `find-active-session.sh`

### Policy:
- Session ID must come from a real active OpenClaw session.
- Do **not** generate random UUIDs for supervisor routing.

### Required environment variables:
- `OPENCLAW_AGENT_ID` — Agent name (main, ruyi, etc.)
- `OPENCLAW_CHANNEL` — Communication channel (discord, telegram, etc.)
- `OPENCLAW_TARGET` — Target channel/user ID for delivery

### If session ID resolution fails:
cc-start will exit with error code 1 and clear message indicating OpenClaw environment issue.

---

## Hook Bootstrap Fallback Lifecycle

`cc-start` (via `supervisor_run.sh`) writes `logs/hook.env` as a transient bootstrap bridge.

Plain-language lifecycle:
1. Startup writes fallback values (`OPENCLAW_SESSION_ID`, `OPENCLAW_AGENT_ID`, `OPENCLAW_CHANNEL`, `OPENCLAW_TARGET`).
2. Hook callback uses inherited process env first.
3. If required env is missing, callback loads fallback file.
4. On successful fallback validation, callback deletes `logs/hook.env` immediately.

Why this exists:
- Some hook executions may not inherit all runtime env values.
- One-time consume-delete prevents stale fallback from contaminating future sessions.

Troubleshooting:
- If first hook works but later hooks fail, inspect `logs/supervisor.log` for fallback validation warnings.
- If fallback validation fails, missing keys are logged and notifications are queued non-fatally.

---

## Execution Ownership Clarification

Initialization is performed by the process that executes `cc-start` (typically the subagent running this skill flow).

Do not assume parent/other agents share that initialized runtime env. If a hook callback runs without inherited env, it may rely on transient fallback bootstrap as described above.

---

## Command

Run one command. It handles all checks, hook install, tmux startup, and verification automatically.

```bash
CC_SUPERVISOR_HOME="${CC_SUPERVISOR_HOME:-$HOME/.openclaw/skills/cc-supervisor}"
"$CC_SUPERVISOR_HOME/scripts/cc-start.sh" <project-dir> [relay|auto]
```

**What cc-start does internally:**
- Validates/retrieves OPENCLAW_SESSION_ID
- Checks required commands (openclaw, tmux, jq, uuidgen)
- Validates OPENCLAW_TARGET is set
- Installs hooks into target project
- Starts tmux session with all required env vars
- Sends hook verification test message
- Waits up to 30s for hook callback to confirm routing works

---

## Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| `0` | Success, hook routing verified | Proceed to Phase 2 |
| `1` | Fatal error (missing commands, env vars, etc.) | Fix and retry |
| `2` | Hook verification timeout | Run `cc-flush-queue`, retry once, then escalate |

---

## Handling Timeout (Exit Code 2)

```bash
"$CC_SUPERVISOR_HOME/scripts/cc-flush-queue.sh"
# Retry cc-start once
if "$CC_SUPERVISOR_HOME/scripts/cc-start.sh" "$PROJECT_DIR" "$CC_MODE"; then
  echo "Retry succeeded, proceeding to Phase 2"
else
  echo "Second timeout, escalating to human"
  exit 1
fi
```

---

## Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Missing required commands: ...` | Tools not installed | Install missing tools (tmux, jq, openclaw, claude), retry |
| `OPENCLAW_TARGET not set` | Environment variable missing | Cannot auto-fix, escalate to human |
| `Hook '...' not found after install` | Hook installation failed | Check `.claude/settings.local.json`, escalate |
| `Directory trust prompt` | Claude Code needs directory approval | Human must: `tmux attach -t cc-supervise`, type `y`, `Ctrl-B D`, re-run cc-start |
| `TIMEOUT: ...` | Hook callback not received | Exit code 2, follow timeout handling above |

---

## Success Indicator

Look for: `=== cc-start complete ===`

This means:
- ✓ Session ID validated
- ✓ All commands available
- ✓ Hooks installed
- ✓ tmux session running
- ✓ Hook routing verified

---

## Next Step

Once Phase 1 completes successfully (exit code 0), proceed to **Phase 2**.

**Read:** `docs/phase-2.md`
