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

# ── Step 2: Resolve from active OpenClaw session store ───────────────────────
log_info "OPENCLAW_SESSION_ID not set, searching for active OpenClaw session..."

FIND_SESSION_SCRIPT="${SCRIPT_DIR}/find-active-session.sh"
if [ -f "$FIND_SESSION_SCRIPT" ]; then
  if SESSION_ID_EXPORT=$(bash "$FIND_SESSION_SCRIPT" 2>&1); then
    eval "$SESSION_ID_EXPORT"
    if echo "$OPENCLAW_SESSION_ID" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
      log_info "✓ Resolved active OPENCLAW_SESSION_ID: $OPENCLAW_SESSION_ID"
      echo "export OPENCLAW_SESSION_ID='$OPENCLAW_SESSION_ID'"
      exit 0
    fi

    log_error "Resolved OPENCLAW_SESSION_ID has invalid format: $OPENCLAW_SESSION_ID"
    exit 1
  fi

  log_error "$SESSION_ID_EXPORT"
else
  log_error "find-active-session.sh not found: $FIND_SESSION_SCRIPT"
fi

# ── Step 3: Fail with actionable guidance (no random UUID fallback) ──────────
log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_error "OPENCLAW_SESSION_ID is required and could not be resolved"
log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_error ""
log_error "SOLUTION: Use a real active OpenClaw session context"
log_error "  1. Ensure OPENCLAW_AGENT_ID, OPENCLAW_CHANNEL, OPENCLAW_TARGET are set correctly"
log_error "  2. Ensure a matching active session exists in OpenClaw session store"
log_error "  3. Or set OPENCLAW_SESSION_ID=<existing-session-id> from an active session"
log_error ""
log_error "IMPORTANT: Do NOT generate random UUIDs."
exit 1
