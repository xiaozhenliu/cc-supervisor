#!/usr/bin/env bash
# find-active-session.sh - Find active OpenClaw session ID from session store
#
# This script queries OpenClaw's session store to find the current active session.
# In main/sub agent scenarios, it looks for sessions containing both agent IDs.
#
# Usage: eval "$(./find-active-session.sh)"
# Returns: exports OPENCLAW_SESSION_ID if found, exits with error otherwise

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"

# ── Configuration ─────────────────────────────────────────────────────────────
AGENT_ID="${OPENCLAW_AGENT_ID:-ruyi}"
SESSION_STORE="$HOME/.openclaw/agents/$AGENT_ID/sessions/sessions.json"

# ── Helper: Query active sessions ────────────────────────────────────────────
find_active_session() {
  local agent_id="$1"
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

  # Query all sessions, sorted by last activity (most recent first)
  local sessions=$(jq -r '
    to_entries
    | map({
        key: .key,
        sessionId: .value.sessionId,
        lastActivity: .value.lastActivity // 0,
        origin: .value.origin,
        deliveryContext: .value.deliveryContext
      })
    | sort_by(.lastActivity)
    | reverse
    | .[]
    | @json
  ' "$session_file" 2>/dev/null)

  if [ -z "$sessions" ]; then
    log_warn "No sessions found in $session_file"
    return 1
  fi

  # Return the most recent session ID
  local session_id=$(echo "$sessions" | head -1 | jq -r '.sessionId')

  if [ -n "$session_id" ] && [ "$session_id" != "null" ]; then
    echo "$session_id"
    return 0
  fi

  return 1
}

# ── Main Logic ────────────────────────────────────────────────────────────────

log_info "Searching for active OpenClaw session..."
log_info "Agent ID: $AGENT_ID"
log_info "Session store: $SESSION_STORE"

# Try to find active session
if SESSION_ID=$(find_active_session "$AGENT_ID"); then
  # Validate UUID format
  if echo "$SESSION_ID" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    log_info "✓ Found active session: $SESSION_ID"
    echo "export OPENCLAW_SESSION_ID='$SESSION_ID'"
    exit 0
  else
    log_error "Found session ID but format is invalid: $SESSION_ID"
    exit 1
  fi
fi

# ── No active session found ───────────────────────────────────────────────────
log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_error "No active OpenClaw session found"
log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_error ""
log_error "Checked: $SESSION_STORE"
log_error ""
log_error "SOLUTION:"
log_error "1. Ensure you are running this from within an OpenClaw agent session"
log_error "2. Check that OpenClaw gateway is running: openclaw status"
log_error "3. Verify agent ID is correct: OPENCLAW_AGENT_ID=$AGENT_ID"
log_error ""
log_error "If running manually for testing, you MUST set OPENCLAW_SESSION_ID:"
log_error "  export OPENCLAW_SESSION_ID=<existing-session-id>"
log_error ""
log_error "IMPORTANT: Do NOT generate random UUIDs - use an actual session ID"
log_error "from an active OpenClaw session."
exit 1
