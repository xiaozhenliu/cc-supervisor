#!/usr/bin/env bash
# test-handle-human-reply.sh - Verify Phase 3 reply execution gate behavior.
# Usage: ./scripts/test-handle-human-reply.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HANDLER_SCRIPT="${SCRIPT_DIR}/handle-human-reply.sh"
TEST_DIR="$(mktemp -d)"
SEND_LOG="${TEST_DIR}/send.log"
trap 'rm -rf "${TEST_DIR}"' EXIT

cat > "${TEST_DIR}/mock-send.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${MOCK_SEND_LOG:?}"
EOF
chmod +x "${TEST_DIR}/mock-send.sh"

cat > "${TEST_DIR}/mock-capture.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--tail" ]]; then
  shift 2
fi
if [[ "${1:-}" == "--grep" ]]; then
  shift 2
fi
printf 'mock snapshot\n'
EOF
chmod +x "${TEST_DIR}/mock-capture.sh"

assert_handler() {
  local description="$1"
  local mode="$2"
  local input="$3"
  local expected_exit="$4"
  local expected_action="$5"
  local expected_executed="$6"
  local expected_command_kind="$7"
  local expected_command_value="${8:-}"

  : > "$SEND_LOG"

  set +e
  local output
  output="$(MOCK_SEND_LOG="$SEND_LOG" \
    CC_SEND_SCRIPT="${TEST_DIR}/mock-send.sh" \
    CC_CAPTURE_SCRIPT="${TEST_DIR}/mock-capture.sh" \
    bash "$HANDLER_SCRIPT" --mode "$mode" --message "$input" 2>"${TEST_DIR}/stderr.log")"
  local exit_code=$?
  set -e

  if [[ "$exit_code" != "$expected_exit" ]]; then
    echo "✗ FAIL: $description"
    echo "  expected exit=$expected_exit actual=$exit_code"
    cat "${TEST_DIR}/stderr.log"
    exit 1
  fi

  local actual_action actual_executed actual_command_kind actual_command_value
  actual_action="$(echo "$output" | jq -r '.action')"
  actual_executed="$(echo "$output" | jq -r '.executed')"
  actual_command_kind="$(echo "$output" | jq -r '.command_kind // ""')"
  actual_command_value="$(echo "$output" | jq -r '.command_value // ""')"

  if [[ "$actual_action" != "$expected_action" || "$actual_executed" != "$expected_executed" || "$actual_command_kind" != "$expected_command_kind" || "$actual_command_value" != "$expected_command_value" ]]; then
    echo "✗ FAIL: $description"
    echo "  expected action=$expected_action executed=$expected_executed kind=$expected_command_kind value=$expected_command_value"
    echo "  actual   action=$actual_action executed=$actual_executed kind=$actual_command_kind value=$actual_command_value"
    echo "$output"
    exit 1
  fi

  echo "✓ PASS: $description"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Human Reply Handler"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

assert_handler "forward executes cc-send" "auto" "cc 修复登录超时" "0" "forward" "true" "send_text" "修复登录超时"
if ! grep -qx "修复登录超时" "$SEND_LOG"; then
  echo "✗ FAIL: forward did not invoke send script with raw content"
  exit 1
fi

assert_handler "cmd继续 executes fixed continue text" "relay" "cmd继续" "0" "continue" "true" "send_text" "Please continue."
if ! grep -qx "Please continue." "$SEND_LOG"; then
  echo "✗ FAIL: continue did not invoke send script"
  exit 1
fi

assert_handler "cmd停止 executes Escape key" "relay" "cmd停止" "0" "pause" "true" "send_key" "Escape"
if ! grep -qx -- "--key Escape" "$SEND_LOG"; then
  echo "✗ FAIL: pause did not invoke send key"
  exit 1
fi

assert_handler "cmd检查 captures output without sending" "auto" "cmd检查" "0" "status" "false" "capture" "--tail 20"
if [[ -s "$SEND_LOG" ]]; then
  echo "✗ FAIL: status should not invoke send script"
  exit 1
fi

assert_handler "cmd退出 captures output and signals phase 4" "auto" "cmd退出" "0" "exit" "false" "capture" "--tail 20 --grep complete|done|error|fail|summary"
if [[ -s "$SEND_LOG" ]]; then
  echo "✗ FAIL: done should not invoke send script"
  exit 1
fi

EXIT_OUTPUT="$(MOCK_SEND_LOG="$SEND_LOG" CC_SEND_SCRIPT="${TEST_DIR}/mock-send.sh" CC_CAPTURE_SCRIPT="${TEST_DIR}/mock-capture.sh" bash "$HANDLER_SCRIPT" --mode auto --message "cmd退出")"
if [[ "$(echo "$EXIT_OUTPUT" | jq -r '.next_phase')" != "phase_4" ]]; then
  echo "✗ FAIL: exit should hint phase_4"
  exit 1
fi

assert_handler "meta stays on supervisor side" "auto" "不要自动 commit" "0" "meta" "false" "" ""
if [[ -s "$SEND_LOG" ]]; then
  echo "✗ FAIL: meta should not invoke send script"
  exit 1
fi

assert_handler "empty cc body returns invalid input" "auto" "cc" "2" "error" "false" "" ""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All reply handler tests passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
