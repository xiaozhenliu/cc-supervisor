#!/usr/bin/env bash
# test-notification-template.sh - Verify notification text includes reply protocol.
# Usage: ./scripts/test-notification-template.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_LIB="${SCRIPT_DIR}/lib/message_templates.sh"

# shellcheck disable=SC1090
source "$TEMPLATE_LIB"

assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"

  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    echo "✓ PASS: $description"
  else
    echo "✗ FAIL: $description"
    echo "  missing: $needle"
    echo "  message:"
    printf '%s\n' "$haystack"
    exit 1
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Notification Template"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

STOP_MSG="$(build_supervisor_notification "auto" "Stop" "Task blocked on API key")"
assert_contains "stop message includes auto header" "$STOP_MSG" "[cc-supervisor][auto] Stop:"
assert_contains "stop message includes cc protocol" "$STOP_MSG" "发给 Claude：cc <内容>"
assert_contains "stop message includes cmd commands" "$STOP_MSG" "supervisor 命令：cmd继续 / cmd停止 / cmd检查 / cmd退出"

NOTIFY_MSG="$(build_supervisor_notification "relay" "Notification" "Waiting for confirmation")"
assert_contains "notification message includes relay header" "$NOTIFY_MSG" "[cc-supervisor][relay] Notification:"
assert_contains "notification message includes non-forward warning" "$NOTIFY_MSG" "其他消息：默认只给 supervisor，不转发"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All notification template tests passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
