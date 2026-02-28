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

# 2. Verify it matches the environment variable
if [ -n "${OPENCLAW_SESSION_ID:-}" ]; then
  if [ "$SESSION_ID" = "$OPENCLAW_SESSION_ID" ]; then
    echo "✓ Matches OPENCLAW_SESSION_ID environment variable"
  else
    echo "❌ MISMATCH: Does not match OPENCLAW_SESSION_ID"
    echo "   Testing: $SESSION_ID"
    echo "   Env var: $OPENCLAW_SESSION_ID"
    exit 1
  fi
else
  echo "⚠ WARNING: OPENCLAW_SESSION_ID environment variable not set"
fi

echo ""
echo "✓ Session ID verification complete: $SESSION_ID"
echo ""
echo "Note: This script only validates format and consistency."
echo "It cannot verify if this session ID will actually receive messages."
echo "Use Phase 3.5 test message to verify end-to-end routing."

