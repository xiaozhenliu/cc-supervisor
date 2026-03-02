#!/usr/bin/env bash
# ensure-session-id.sh - Ensure OPENCLAW_SESSION_ID is available and valid
# This script should be called BEFORE supervisor_run.sh to guarantee session ID availability
#
# Usage: eval "$(./ensure-session-id.sh)"
# Returns: exports OPENCLAW_SESSION_ID if successful, exits with error otherwise

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"

# ── Step 1: Check if OPENCLAW_SESSION_ID is already set ──────────────────────
if [ -n "${OPENCLAW_SESSION_ID:-}" ]; then
  # Validate UUID format
  if echo "$OPENCLAW_SESSION_ID" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    log_info "✓ Using existing OPENCLAW_SESSION_ID: $OPENCLAW_SESSION_ID"
    echo "export OPENCLAW_SESSION_ID='$OPENCLAW_SESSION_ID'"
    exit 0
  else
    log_error "OPENCLAW_SESSION_ID has invalid format: $OPENCLAW_SESSION_ID"
    log_error "Expected UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (lowercase hex)"
    exit 1
  fi
fi

# ── Step 2: Try to get session ID from OpenClaw CLI ──────────────────────────
log_info "OPENCLAW_SESSION_ID not set, attempting to retrieve from OpenClaw..."

if ! command -v openclaw &>/dev/null; then
  log_error "openclaw command not found in PATH"
  log_error "Install with: npm install -g openclaw@latest"
  exit 1
fi

# Try to get current session ID from OpenClaw
# Note: This assumes OpenClaw provides a way to query the current session
# If not available, we need to document that users MUST set it manually
SESSION_ID_OUTPUT=$(openclaw config get session-id 2>/dev/null || true)

if [ -n "$SESSION_ID_OUTPUT" ]; then
  # Validate format
  if echo "$SESSION_ID_OUTPUT" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    log_info "✓ Retrieved session ID from OpenClaw: $SESSION_ID_OUTPUT"
    echo "export OPENCLAW_SESSION_ID='$SESSION_ID_OUTPUT'"
    exit 0
  fi
fi

# ── Step 3: Check if running inside OpenClaw agent context ───────────────────
# When OpenClaw runs an agent, it should set OPENCLAW_SESSION_ID automatically
# If we reach here, it means we're NOT in an agent context

log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_error "OPENCLAW_SESSION_ID is required but not available"
log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_error ""
log_error "This skill must be run from within an OpenClaw agent session."
log_error "The OpenClaw agent should automatically set OPENCLAW_SESSION_ID."
log_error ""
log_error "If you are running this manually for testing, set it first:"
log_error "  export OPENCLAW_SESSION_ID=\$(uuidgen | tr '[:upper:]' '[:lower:]')"
log_error ""
log_error "If you are in an OpenClaw agent session and seeing this error,"
log_error "please report this as a bug."
exit 1
