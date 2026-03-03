#!/usr/bin/env bash
# find-active-session.sh - Find active OpenClaw session ID from session store
#
# This script queries OpenClaw's session store to find the current active session
# by matching OPENCLAW_CHANNEL and OPENCLAW_TARGET environment variables.
#
# Matching logic:
#   1. Get OPENCLAW_CHANNEL and OPENCLAW_TARGET from environment
#   2. Query session store for sessions matching both channel and target
#   3. Return the sessionId of the matching session
#
# Usage: eval "$(./find-active-session.sh)"
# Returns: exports OPENCLAW_SESSION_ID if found, exits with error otherwise

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"

# ── Configuration ─────────────────────────────────────────────────────────────
AGENT_ID="${OPENCLAW_AGENT_ID:-}"
CHANNEL="${OPENCLAW_CHANNEL:-}"
TARGET="${OPENCLAW_TARGET:-}"

# ── Validation ───────────────────────────────────────────────────────────────
if [ -z "$AGENT_ID" ]; then
  log_error "OPENCLAW_AGENT_ID environment variable is not set"
  log_error "This variable must be set by OpenClaw when invoking the agent"
  log_error ""
  log_error "If you are running this manually for testing, set it first:"
  log_error "  export OPENCLAW_AGENT_ID=main  # or ruyi, or your agent name"
  exit 1
fi

SESSION_STORE="$HOME/.openclaw/agents/$AGENT_ID/sessions/sessions.json"
if [ -z "$CHANNEL" ]; then
  log_error "OPENCLAW_CHANNEL environment variable is not set"
  log_error "This variable is required to identify the current session"
  exit 1
fi

if [ -z "$TARGET" ]; then
  log_error "OPENCLAW_TARGET environment variable is not set"
  log_error "This variable is required to identify the current session"
  exit 1
fi

# ── Helper: Query active sessions ────────────────────────────────────────────
find_active_session() {
  local agent_id="$1"
  local channel="$2"
  local target="$3"
  local session_file="$HOME/.openclaw/agents/$agent_id/sessions/sessions.json"

  # Check if session file exists
  if [ ! -f "$session_file" ]; then
    log_warn "Session file not found: $session_file"
    return 1
  fi

  # Check if jq is available
  if ! command -v jq &>/dev/null; then
    log_error "jq is required but not found in PATH"
    return 1
  fi

  # Query sessions matching channel and target
  # Match logic: deliveryContext.channel == OPENCLAW_CHANNEL
  #              AND deliveryContext.to contains OPENCLAW_TARGET
  local session_id=$(jq -r --arg channel "$channel" --arg target "$target" '
    to_entries
    | map(select(
        .value.deliveryContext.channel == $channel and
        (.value.deliveryContext.to | tostring | contains($target))
      ))
    | sort_by(.value.lastActivity // 0)
    | reverse
    | .[0].value.sessionId // empty
  ' "$session_file" 2>/dev/null)

  if [ -n "$session_id" ] && [ "$session_id" != "null" ]; then
    echo "$session_id"
    return 0
  fi

  return 1
}

# ── Main Logic ────────────────────────────────────────────────────────────────

log_info "Searching for active OpenClaw session..."
log_info "Agent ID: $AGENT_ID"
log_info "Channel: $CHANNEL"
log_info "Target: $TARGET"
log_info "Session store: $SESSION_STORE"

# Try to find active session
if SESSION_ID=$(find_active_session "$AGENT_ID" "$CHANNEL" "$TARGET"); then
  # Validate UUID format
  if echo "$SESSION_ID" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    log_info "✓ Found matching session: $SESSION_ID"
    echo "export OPENCLAW_SESSION_ID='$SESSION_ID'"
    exit 0
  else
    log_error "Found session ID but format is invalid: $SESSION_ID"
    exit 1
  fi
fi

# ── No active session found ───────────────────────────────────────────────────
log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_error "No matching OpenClaw session found"
log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_error ""
log_error "Search criteria:"
log_error "  Agent ID: $AGENT_ID"
log_error "  Channel: $CHANNEL"
log_error "  Target: $TARGET"
log_error "  Session store: $SESSION_STORE"
log_error ""
log_error "SOLUTION:"
log_error "1. Verify OPENCLAW_CHANNEL and OPENCLAW_TARGET are correct"
log_error "2. Check that an active session exists: openclaw session list"
log_error "3. Ensure OpenClaw gateway is running: openclaw status"
log_error ""
log_error "If running manually for testing, you MUST set OPENCLAW_SESSION_ID:"
log_error "  export OPENCLAW_SESSION_ID=<existing-session-id>"
log_error ""
log_error "IMPORTANT: Do NOT generate random UUIDs - use an actual session ID"
log_error "from an active OpenClaw session matching your channel and target."
exit 1
