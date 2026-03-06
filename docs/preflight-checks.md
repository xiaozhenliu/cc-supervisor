# Preflight Checks

## Overview

`scripts/preflight-check.sh` is a unified preflight validation orchestrator that checks all prerequisites before starting cc-supervisor. It calls independent validation scripts in sequence, making the system modular and maintainable.

## Architecture

### Modular Design

The preflight system is composed of independent scripts that can be used standalone or orchestrated together:

```
preflight-check.sh (orchestrator)
├── check-commands.sh      - Verify required commands
├── ensure-session-id.sh   - Validate/resolve session ID
├── check-env.sh           - Check optional env vars
└── check-structure.sh     - Verify project structure
```

**Benefits:**
- **Low coupling**: Each script is independent and reusable
- **Easy testing**: Test each component separately
- **Flexible**: Use individual scripts or the full orchestrator
- **Maintainable**: Changes to one check don't affect others

## What It Checks

### 1. Required Commands (`check-commands.sh`)
- `openclaw` - OpenClaw CLI
- `tmux` - Terminal multiplexer
- `jq` - JSON processor

If any command is missing, the script provides installation instructions.

### 2. OPENCLAW_SESSION_ID (`ensure-session-id.sh`)
- Validates existing session ID format (UUID)
- Attempts to resolve from active OpenClaw session store
- Fails fast if no active session can be resolved
- Exports the validated session ID

### 3. Optional Environment Variables (`check-env.sh`)
- `OPENCLAW_CHANNEL` - notification channel (discord/telegram/whatsapp)
- `OPENCLAW_TARGET` - notification target (channel ID, chat ID, phone number)
- `OPENCLAW_ACCOUNT` - OpenClaw account (optional)

These are not required but will be reported if missing.

### 4. Project Structure (`check-structure.sh`)
- `scripts/` directory exists
- `logs/` directory exists
- `scripts/supervisor_run.sh` exists
- `scripts/lib/log.sh` exists
- `scripts/lib/notify.sh` exists

## Usage

### For LLM Agents (Recommended)

Run preflight checks before Phase 1:

```bash
CC_SUPERVISOR_HOME="${CC_SUPERVISOR_HOME:-$HOME/.openclaw/skills/cc-supervisor}"
eval "$("$CC_SUPERVISOR_HOME/scripts/preflight-check.sh")"
```

If successful, all required environment variables are exported automatically. Proceed to `cc-start`.

If failed, the script outputs clear error messages. Fix the errors and retry.

### For Manual Testing

```bash
cd /path/to/cc-supervisor
eval "$(./scripts/preflight-check.sh)"
```

### Using Individual Check Scripts

Each check script can be used standalone for targeted validation:

```bash
# Check only required commands
./scripts/check-commands.sh

# Check only environment variables
./scripts/check-env.sh

# Check only project structure
./scripts/check-structure.sh

# Check/resolve session ID
eval "$(./scripts/ensure-session-id.sh)"
```

### For CI/CD

```bash
# Run without eval to see output only
./scripts/preflight-check.sh

# Check exit code
if [ $? -eq 0 ]; then
  echo "Preflight checks passed"
else
  echo "Preflight checks failed"
  exit 1
fi
```

## Output Format

### Success Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Running preflight checks for cc-supervisor...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1/4] Checking required commands...
✓ openclaw command
✓ tmux command
✓ jq command

[2/4] Checking OPENCLAW_SESSION_ID...
✓ Using existing OPENCLAW_SESSION_ID: 908534f0...1d6e

[3/4] Checking optional environment variables...
✓ OPENCLAW_CHANNEL: discord
✓ OPENCLAW_TARGET: 1466784529527214122
⚠ OPENCLAW_ACCOUNT not set (optional)

[4/4] Checking project structure...
✓ Directory exists: scripts/
✓ Directory exists: logs/
✓ File exists: scripts/supervisor_run.sh
✓ File exists: scripts/lib/log.sh
✓ File exists: scripts/lib/notify.sh

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ All preflight checks passed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Ready to start cc-supervisor!

export OPENCLAW_SESSION_ID='908534f0-5405-435e-a5f3-f000dc841d6e'
export CC_PROJECT_DIR='/Users/xz/Projects/cc-supervisor'
```

### Failure Output

```
[1/4] Checking required commands...
✓ openclaw command
✗ tmux command
✓ jq command

Missing required commands: tmux

Install instructions:
  - tmux: brew install tmux (macOS) or apt install tmux (Linux)
```

## Integration with cc-start

`cc-start.sh` automatically runs preflight checks at the beginning (Step 0). If preflight checks fail, `cc-start` will abort with clear error messages.

## Benefits

1. **Fast startup**: Checks are orchestrated in a single preflight entrypoint with clear failure boundaries
2. **Token efficiency**: LLM agents don't need to manually verify each requirement
3. **Clear error messages**: Installation instructions provided for missing dependencies
4. **Correct routing**: Session ID must come from an active OpenClaw session
5. **Consistent validation**: Same checks every time, no human error

## Exit Codes

- `0` - All checks passed, environment variables exported
- `1` - One or more checks failed, error messages printed

## Environment Variables Exported

On success, the script exports:

- `OPENCLAW_SESSION_ID` - Validated active session ID
- `CC_PROJECT_DIR` - Absolute path to cc-supervisor project

These can be used by subsequent scripts without re-validation.
