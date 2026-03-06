# OpenClaw Reference Documentation

> **Purpose**: This document provides accurate reference for OpenClaw CLI commands used in cc-supervisor. All information is extracted from actual `openclaw --help` output.

**OpenClaw Version**: 2026.2.26 (bc50708)

---

## Core Concepts

### What is OpenClaw?
OpenClaw is a self-hosted gateway connecting chat apps (WhatsApp, Telegram, Discord, iMessage) to AI coding agents.

**Official Documentation**: https://docs.openclaw.ai

### Key Components
- **Gateway**: Central WebSocket hub (default port: 18789)
- **Agent**: AI agent that executes tasks via the gateway
- **Session**: Conversation context with unique session ID
- **Channel**: Communication channel (telegram, whatsapp, discord, etc.)
- **Message**: Communication unit between human/agent

---

## CLI Commands

### `openclaw agent`

Run one agent turn via the Gateway.

**Documentation**: https://docs.openclaw.ai/cli/agent

**Syntax**:
```bash
openclaw agent [options]
```

**Key Options**:
- `--session-id <id>`: Use an explicit session ID (used by cc-supervisor)
- `-m, --message <text>`: Message body for the agent
- `--deliver`: Send the agent's reply back to the selected channel
- `--reply-to <target>`: Delivery target override
- `--reply-channel <channel>`: Delivery channel override
- `--reply-account <id>`: Delivery account ID override
- `--agent <id>`: Agent ID (overrides routing bindings)
- `--to <number>`: Recipient number in E.164 (derives session key)
- `--channel <channel>`: Delivery channel
- `--thinking <level>`: Thinking level (off|minimal|low|medium|high)
- `--json`: Output result as JSON
- `--local`: Run embedded agent locally (requires API keys)

**Examples**:
```bash
# Send message to specific session (cc-supervisor usage)
openclaw agent --session-id abc123 --message "Task complete"

# Send message and deliver reply
openclaw agent --session-id abc123 --message "Continue" --deliver --reply-channel whatsapp --reply-to "+15555550123"

# Start new session with phone number
openclaw agent --to +15555550123 --message "status update"
```

### `openclaw message send`

Send a message through a channel.

**Documentation**: https://docs.openclaw.ai/cli/message

**Syntax**:
```bash
openclaw message send [options]
```

**Key Options**:
- `-t, --target <dest>`: Recipient/channel (E.164 for WhatsApp/Signal, chat ID for Telegram/Discord)
- `-m, --message <text>`: Message body
- `--channel <channel>`: Channel (telegram|whatsapp|discord|slack|etc.)
- `--account <id>`: Channel account ID
- `--reply-to <id>`: Reply-to message ID
- `--media <path-or-url>`: Attach media (image/audio/video/document)
- `--json`: Output result as JSON
- `--silent`: Send without notification
- `--dry-run`: Print payload without sending

**Examples**:
```bash
# Send text message
openclaw message send --target +15555550123 --message "Hi"

# Send with media
openclaw message send --target +15555550123 --message "Photo" --media photo.jpg

# Send via Discord
openclaw message send --channel discord --target "channel:123" --message "Alert"
```

### `openclaw system event`

Enqueue a system event and optionally trigger a heartbeat.

**Documentation**: https://docs.openclaw.ai/cli/system

**Syntax**:
```bash
openclaw system event [options]
```

**Examples**:
```bash
# Enqueue system event
openclaw system event --text "Daily summary check"

# Trigger immediately
openclaw system event --text "Check emails" --mode now
```

---

## Environment Variables

### Used by cc-supervisor

- `OPENCLAW_SESSION_ID`: Current session identifier (required for `--session-id`)
- `OPENCLAW_CHANNEL`: Communication channel (discord, telegram, etc.)
- `OPENCLAW_TARGET`: Target channel/user ID for delivery
- `OPENCLAW_ACCOUNT`: Account ID for multi-account channels

### Configuration Location

OpenClaw config is stored at `~/.openclaw/openclaw.json`

---

## Session Management

### Session ID Behavior

- Session IDs can be explicit (via `--session-id`) or derived (via `--to`)
- `--session-id`: Use an existing session or create one with that ID
- `--to <number>`: Derives session key from E.164 phone number
- Sessions persist across agent turns
- Multiple messages can target the same session

### Routing

- `--agent <id>`: Override agent routing
- `--channel`: Specify delivery channel
- `--reply-channel`: Override delivery channel for replies
- `--reply-to`: Override delivery target
- `--deliver`: Actually send the reply (without this, agent runs but doesn't deliver)

---

## cc-supervisor Integration Pattern

### How cc-supervisor Uses OpenClaw

**Notification Flow**:
```bash
# Hook callback sends notification to OpenClaw session
openclaw agent \
  --session-id "$OPENCLAW_SESSION_ID" \
  --message "[cc-supervisor] Stop: Task complete" \
  --deliver \
  --reply-channel "${OPENCLAW_CHANNEL:-discord}" \
  ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"}
```

**Key Points**:
- Uses `--session-id` to maintain conversation context
- Uses `--deliver` + `--reply-channel` for explicit channel routing
- Uses `--reply-to` when target is available
- Falls back gracefully if `openclaw` is not in PATH (queues notification)

---

## Common Issues

### Command Not Found
- **Symptom**: `openclaw: command not found`
- **Cause**: CLI not in PATH
- **Solution**: Install via `npm install -g openclaw@latest`

### Session Not Found
- **Symptom**: Error about invalid session
- **Cause**: Session ID doesn't exist or expired
- **Solution**: Verify `$OPENCLAW_SESSION_ID` is from an active OpenClaw session

### Message Not Delivered
- **Symptom**: Agent runs but no message appears
- **Cause**: Missing `--deliver`, wrong `--reply-channel`, or invalid `--reply-to`
- **Solution**: Add `--deliver`, set `--reply-channel`, and verify target

---

## Testing & Verification

### Verify OpenClaw Installation
```bash
openclaw --version
# Should output: OpenClaw 2026.2.26 (bc50708) or similar
```

### Test Agent Command
```bash
# Test without delivery
openclaw agent --session-id test123 --message "Hello"

# Test with delivery (requires valid target)
openclaw agent --session-id test123 --message "Hello" --deliver --reply-channel whatsapp --reply-to "+15555550123"
```

### Check Environment
```bash
echo $OPENCLAW_SESSION_ID
echo $OPENCLAW_CHANNEL
echo $OPENCLAW_TARGET
```

---

## Additional Commands

### Gateway Management
```bash
# Start gateway
openclaw gateway --port 18789

# Check health
openclaw health

# View status
openclaw status
```

### Channel Management
```bash
# Login to channels
openclaw channels login

# Check channel status
openclaw channels status --probe
```

### Configuration
```bash
# Interactive setup
openclaw configure

# Get config value
openclaw config get <key>

# Set config value
openclaw config set <key> <value>
```

---

## cc-supervisor Hook Bootstrap Fallback Notes

### Purpose of `logs/hook.env`

`logs/hook.env` is a transient bootstrap fallback used by `scripts/on-cc-event.sh` when hook callback runtime env inheritance is missing required OpenClaw values.

### Lifecycle

1. `scripts/supervisor_run.sh` writes `logs/hook.env` at startup.
2. `scripts/on-cc-event.sh` first prefers inherited env values.
3. Callback loads fallback file only if required keys are missing (`OPENCLAW_SESSION_ID`, `OPENCLAW_AGENT_ID`).
4. After successful fallback load and validation, callback deletes `logs/hook.env` immediately.

### Session binding clarification

- Hook JSON field `session_id` is Claude Code internal session context.
- cc-supervisor notification routing must use `OPENCLAW_SESSION_ID` for OpenClaw conversation continuity.

### Operational policy

- Use real active OpenClaw sessions for `OPENCLAW_SESSION_ID`.
- Do not use randomly generated UUIDs for supervisor notification routing.

---

## References

- **Official CLI Docs**: https://docs.openclaw.ai/cli
- **Agent Command**: https://docs.openclaw.ai/cli/agent
- **Message Command**: https://docs.openclaw.ai/cli/message
- **System Command**: https://docs.openclaw.ai/cli/system
