#!/usr/bin/env bash
# test-notification-queue-fallback.sh - Verify notifications queue when openclaw is unavailable.
# Usage: ./scripts/test-notification-queue-fallback.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="${CC_PROJECT_DIR}/scripts/on-cc-event.sh"
QUEUE_FILE="${CC_PROJECT_DIR}/logs/notification.queue"
EVENTS_FILE="${CC_PROJECT_DIR}/logs/events.ndjson"
LOG_FILE="${CC_PROJECT_DIR}/logs/supervisor.log"

assert_contains() {
  local description="$1"
  local file="$2"
  local needle="$3"

  if grep -Fq -- "$needle" "$file"; then
    echo "✓ PASS: $description"
  else
    echo "✗ FAIL: $description"
    echo "  missing: $needle"
    echo "  file: $file"
    exit 1
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Notification Queue Fallback"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

rm -f "$QUEUE_FILE" "$EVENTS_FILE" "$LOG_FILE"

HOOK_JSON='{"hook_event_name":"Notification","session_id":"claude-session","event_id":"evt-queue-1","message":"queue fallback test"}'

printf '%s' "$HOOK_JSON" | \
  CC_PROJECT_DIR="$CC_PROJECT_DIR" \
  CC_SUPERVISION_ID="default" \
  PATH="/usr/bin:/bin" \
  OPENCLAW_SESSION_ID="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee" \
  OPENCLAW_AGENT_ID="ruyi" \
  OPENCLAW_CHANNEL="discord" \
  OPENCLAW_TARGET="channel:test-queue" \
  bash "$HOOK_SCRIPT" >/dev/null

if [[ ! -f "$QUEUE_FILE" ]]; then
  echo "✗ FAIL: notification.queue was not created"
  exit 1
fi

assert_contains "queue entry records Notification event" "$QUEUE_FILE" "|Notification|"
assert_contains "queue entry records target" "$QUEUE_FILE" "channel:test-queue"
assert_contains "queue entry includes cc-supervisor marker" "$QUEUE_FILE" "[cc-supervisor][relay] Notification:"
assert_contains "supervisor log records missing openclaw path fallback" "$LOG_FILE" "openclaw not in PATH — queuing notification"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Notification queue fallback test passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
