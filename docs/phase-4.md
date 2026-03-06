# Phase 4 — Verify and Report

**Purpose:** Verify task completion and report results to human.

---

## Verification Steps

### 0. Honor Stored Supervisor Preferences

In `auto` mode, inspect `logs/supervisor-state.json` first.

- If `require_review_before_phase_4==true` → notify human that completion needs review, do not auto-report success yet
- Otherwise continue with verification

### 1. Check Final Status

```bash
cc-capture --tail 20 --grep "complete|done|error|fail|summary"
```

This shows the final output with completion/error indicators.

### 2. If Unclear, Get More Context

```bash
cc-capture --tail 40
```

Get more lines if the first check doesn't provide enough information.

### 3. Confirm Substantive Content

Verify the output has:
- ✓ Substantive content (not empty)
- ✓ Not pure errors
- ✓ Clear completion signals

### 4. Handle Verification Failure

If output is empty or errors only → **DO NOT report complete.**

Instead, escalate:
```
[cc-supervisor] Phase 4 verification failed: <reason>
Mode: <mode>
Rounds: <N>
Last output: <cc-capture --tail 10 output>
```

---

## Report Format

Once verified, report to human:

```
Task complete.
Mode: <mode>
Rounds: <N>
Summary: <what was built>
```

**Summary should include:**
- What was accomplished
- Key files created/modified
- Any important notes or caveats

---

## Examples

### Success Report

```
Task complete.
Mode: auto
Rounds: 12
Summary: Implemented user login API with JWT authentication. Created routes/auth.js, middleware/auth.js, and tests. All tests passing.
```

### Verification Failure

```
[cc-supervisor] Phase 4 verification failed: Output shows only errors, no completion
Mode: relay
Rounds: 8
Last output: Error: Cannot find module 'jsonwebtoken'
```

---

## End of Workflow

Phase 4 is the final phase. After reporting:
- Task is complete
- Supervision session ends
- Human can review results or start new task

---

## Troubleshooting

If you encounter issues during verification:
- Check `logs/events.ndjson` for full event history
- Review `logs/supervisor.log` for script execution logs
- Use `tmux attach -t cc-supervise` to observe Claude Code directly

For detailed troubleshooting, see main SKILL.md Troubleshooting section.
