#!/usr/bin/env bash
# verify-session-id.sh - Verify that session ID is correct and can receive messages
# Usage: ./verify-session-id.sh [session-id]

set -euo pipefail

SESSION_ID="${1:-${OPENCLAW_SESSION_ID:-}}"

if [ -z "$SESSION_ID" ]; then
  echo "ERROR: No session ID provided and OPENCLAW_SESSION_ID not set"
  echo "Usage: $0 [session-id]"
  exit 1
fi

echo "Verifying session ID: $SESSION_ID"

# 1. Validate format
if ! echo "$SESSION_ID" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
  echo "❌ FAIL: Invalid UUID format"
  echo "   Expected: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (lowercase hex)"
  echo "   Got: $SESSION_ID"
  exit 1
fi
echo "✓ Format valid (UUID v4)"

# 2. Check if openclaw can send to this session
echo "Testing message delivery to session..."
TEST_MSG="[test] Session ID verification at $(date +%s)"

if command -v openclaw >/dev/null 2>&1; then
  if openclaw agent --session-id "$SESSION_ID" --message "$TEST_MSG" 2>&1 | grep -q "success\|delivered\|sent"; then
    echo "✓ Message sent successfully"
  else
    echo "⚠ WARNING: Message send status unclear"
  fi
else
  echo "⚠ WARNING: openclaw command not found, cannot test delivery"
fi

# 3. Compare with current session
CURRENT_SESSION=$(openclaw session-id 2>/dev/null || echo "")
if [ -n "$CURRENT_SESSION" ]; then
  if [ "$SESSION_ID" = "$CURRENT_SESSION" ]; then
    echo "✓ Matches current OpenClaw session"
  else
    echo "❌ MISMATCH: Does not match current session"
    echo "   Testing: $SESSION_ID"
    echo "   Current: $CURRENT_SESSION"
    echo "   Messages will go to the wrong session!"
    exit 1
  fi
else
  echo "⚠ WARNING: Could not get current session ID from openclaw"
fi

echo ""
echo "Session ID verification complete: $SESSION_ID"
