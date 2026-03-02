#!/usr/bin/env bash
# test-session-id-validation.sh - Test the session ID validation mechanism
# Usage: ./test-session-id-validation.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENSURE_SCRIPT="${SCRIPT_DIR}/ensure-session-id.sh"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Session ID Validation Mechanism"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1: Valid session ID already set
echo "Test 1: Valid OPENCLAW_SESSION_ID already set"
export OPENCLAW_SESSION_ID="12345678-1234-1234-1234-123456789abc"
if bash "$ENSURE_SCRIPT" >/dev/null 2>&1; then
  echo "✓ PASS: Accepted valid session ID"
else
  echo "✗ FAIL: Rejected valid session ID"
fi
echo ""

# Test 2: Invalid format
echo "Test 2: Invalid OPENCLAW_SESSION_ID format"
export OPENCLAW_SESSION_ID="invalid-format"
if bash "$ENSURE_SCRIPT" >/dev/null 2>&1; then
  echo "✗ FAIL: Accepted invalid format"
else
  echo "✓ PASS: Rejected invalid format"
fi
echo ""

# Test 3: Uppercase UUID (should fail - requires lowercase)
echo "Test 3: Uppercase UUID (should be lowercase)"
export OPENCLAW_SESSION_ID="12345678-1234-1234-1234-123456789ABC"
if bash "$ENSURE_SCRIPT" >/dev/null 2>&1; then
  echo "✗ FAIL: Accepted uppercase UUID"
else
  echo "✓ PASS: Rejected uppercase UUID"
fi
echo ""

# Test 4: Not set (will try to get from OpenClaw)
echo "Test 4: OPENCLAW_SESSION_ID not set"
unset OPENCLAW_SESSION_ID
if bash "$ENSURE_SCRIPT" >/dev/null 2>&1; then
  echo "✓ PASS: Successfully retrieved from OpenClaw or handled gracefully"
else
  echo "⚠ Expected: Should fail if not in OpenClaw context"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
