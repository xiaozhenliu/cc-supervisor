#!/usr/bin/env bash
# get-session-id.sh - Reliably get current OpenClaw session ID
# Usage: source this script or run: eval "$(./get-session-id.sh)"

set -euo pipefail

# Method 1: Check if already set (most reliable)
if [ -n "${OPENCLAW_SESSION_ID:-}" ]; then
  echo "export OPENCLAW_SESSION_ID='$OPENCLAW_SESSION_ID'" >&2
  echo "# Using existing session ID: $OPENCLAW_SESSION_ID" >&2
  echo "export OPENCLAW_SESSION_ID='$OPENCLAW_SESSION_ID'"
  exit 0
fi

# Method 2: Get from openclaw CLI
SESSION_ID=$(openclaw session-id 2>/dev/null || echo "")

if [ -n "$SESSION_ID" ]; then
  # Validate UUID format
  if echo "$SESSION_ID" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    echo "export OPENCLAW_SESSION_ID='$SESSION_ID'" >&2
    echo "# Got session ID from openclaw CLI: $SESSION_ID" >&2
    echo "export OPENCLAW_SESSION_ID='$SESSION_ID'"
    exit 0
  else
    echo "# WARNING: openclaw session-id returned invalid format: $SESSION_ID" >&2
  fi
fi

# Method 3: Generate new (fallback only - should rarely happen)
SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
echo "export OPENCLAW_SESSION_ID='$SESSION_ID'" >&2
echo "# WARNING: Generated new session ID (openclaw session-id failed): $SESSION_ID" >&2
echo "# This may cause Hook notifications to fail!" >&2
echo "export OPENCLAW_SESSION_ID='$SESSION_ID'"
