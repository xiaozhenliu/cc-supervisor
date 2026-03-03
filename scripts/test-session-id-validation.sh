#!/usr/bin/env bash
# test-session-id-validation.sh - Test the session ID validation mechanism
# Usage: ./test-session-id-validation.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENSURE_SCRIPT="${SCRIPT_DIR}/ensure-session-id.sh"
CC_START_SCRIPT="${SCRIPT_DIR}/cc-start.sh"

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

# Test 4: Not set (should fail outside active OpenClaw context)
echo "Test 4: OPENCLAW_SESSION_ID not set"
unset OPENCLAW_SESSION_ID
if bash "$ENSURE_SCRIPT" >/dev/null 2>&1; then
  echo "✓ PASS: Successfully resolved from active OpenClaw context"
else
  echo "⚠ Expected outside OpenClaw context: active session resolution failed"
fi
echo ""

# Test 5: Policy regression - no random UUID generation guidance
echo "Test 5: No random UUID generation guidance in ensure-session-id.sh"
if grep -qE 'uuidgen|Generate a temporary session ID|temporary UUID is sufficient' "$ENSURE_SCRIPT"; then
  echo "✗ FAIL: Found deprecated random UUID generation guidance"
  exit 1
else
  echo "✓ PASS: No random UUID generation fallback guidance"
fi
echo ""

# Test 6: cc-start session variable consistency
echo "Test 6: cc-start uses OPENCLAW_SESSION_ID consistently"
if grep -qE '\$SESSION_ID([^A-Z_]|$)' "$CC_START_SCRIPT"; then
  echo "✗ FAIL: Found runtime \$SESSION_ID reference in cc-start.sh"
  exit 1
else
  echo "✓ PASS: No runtime \$SESSION_ID references"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
