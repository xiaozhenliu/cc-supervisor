#!/usr/bin/env bash
# test-hook-env-lifecycle.sh - Verify hook.env fallback consume-delete lifecycle
# Usage: ./test-hook-env-lifecycle.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$CC_PROJECT_DIR/scripts/on-cc-event.sh"
LOG_DIR="$CC_PROJECT_DIR/logs"
HOOK_ENV_FILE="$LOG_DIR/hook.env"

mkdir -p "$LOG_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing hook.env fallback lifecycle"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

emit_event() {
  local event_id="$1"
  local message="$2"
  printf '{"hook_event_name":"Notification","session_id":"claude-session","event_id":"%s","message":"%s"}' "$event_id" "$message" \
    | CC_PROJECT_DIR="$CC_PROJECT_DIR" bash "$HOOK_SCRIPT" >/tmp/hook-env-test.out 2>/tmp/hook-env-test.err
}

# Test 1: missing env + present hook.env -> load and delete
echo "Test 1: Missing env with hook.env present should consume and delete"
cat > "$HOOK_ENV_FILE" <<'EOF'
OPENCLAW_SESSION_ID=11111111-1111-1111-1111-111111111111
OPENCLAW_AGENT_ID=ruyi
OPENCLAW_CHANNEL=discord
OPENCLAW_TARGET=channel:test
CC_SUPERVISOR_ROLE=supervisor
EOF
unset OPENCLAW_SESSION_ID OPENCLAW_AGENT_ID OPENCLAW_CHANNEL OPENCLAW_TARGET
emit_event "evt-hook-env-1" "hook lifecycle test 1"
if [[ -f "$HOOK_ENV_FILE" ]]; then
  echo "✗ FAIL: hook.env still exists after successful fallback load"
  exit 1
else
  echo "✓ PASS: hook.env deleted after successful fallback load"
fi
echo ""

# Test 2: env already present -> no hook.env required
echo "Test 2: Present env should not require hook.env"
export OPENCLAW_SESSION_ID="22222222-2222-2222-2222-222222222222"
export OPENCLAW_AGENT_ID="ruyi"
export OPENCLAW_CHANNEL="discord"
export OPENCLAW_TARGET="channel:live"
rm -f "$HOOK_ENV_FILE"
emit_event "evt-hook-env-2" "hook lifecycle test 2"
if grep -q "Hook fallback not needed" /tmp/hook-env-test.err; then
  echo "✓ PASS: callback used inherited env without fallback file"
else
  echo "✗ FAIL: callback did not log inherited-env path"
  exit 1
fi
echo ""

# Test 3: stale file removed after first consume should not affect later run
echo "Test 3: Stale fallback file should not affect later callback after deletion"
cat > "$HOOK_ENV_FILE" <<'EOF'
OPENCLAW_SESSION_ID=33333333-3333-3333-3333-333333333333
OPENCLAW_AGENT_ID=ruyi
OPENCLAW_CHANNEL=discord
OPENCLAW_TARGET=channel:stale
EOF
unset OPENCLAW_SESSION_ID OPENCLAW_AGENT_ID OPENCLAW_CHANNEL OPENCLAW_TARGET
emit_event "evt-hook-env-3a" "hook lifecycle test 3 first"
if [[ -f "$HOOK_ENV_FILE" ]]; then
  echo "✗ FAIL: stale hook.env not deleted after consume"
  exit 1
fi

# Second callback with no inherited env and no fallback file should not silently reuse stale values
unset OPENCLAW_SESSION_ID OPENCLAW_AGENT_ID OPENCLAW_CHANNEL OPENCLAW_TARGET
emit_event "evt-hook-env-3b" "hook lifecycle test 3 second"
if grep -q "Hook fallback required but file not found" /tmp/hook-env-test.err; then
  echo "✓ PASS: no stale fallback reuse after consume-delete"
else
  echo "✗ FAIL: expected missing-fallback warning not found"
  exit 1
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All hook.env lifecycle tests passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
