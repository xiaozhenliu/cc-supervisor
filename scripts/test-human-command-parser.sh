#!/usr/bin/env bash
# test-human-command-parser.sh - Verify explicit human-command parsing rules.
# Usage: ./scripts/test-human-command-parser.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER_SCRIPT="${SCRIPT_DIR}/parse-human-command.sh"

assert_parse() {
  local description="$1"
  local mode="$2"
  local input="$3"
  local expected_ok="$4"
  local expected_action="$5"
  local expected_reason="$6"
  local expected_content="${7:-}"

  local output
  output="$(bash "$PARSER_SCRIPT" --mode "$mode" --message "$input")"

  local actual_ok actual_action actual_reason actual_content
  actual_ok="$(echo "$output" | jq -r '.ok')"
  actual_action="$(echo "$output" | jq -r '.action')"
  actual_reason="$(echo "$output" | jq -r '.reason')"
  actual_content="$(echo "$output" | jq -r '.content')"

  if [[ "$actual_ok" == "$expected_ok" && "$actual_action" == "$expected_action" && "$actual_reason" == "$expected_reason" && "$actual_content" == "$expected_content" ]]; then
    echo "✓ PASS: $description"
  else
    echo "✗ FAIL: $description"
    echo "  expected: ok=$expected_ok action=$expected_action reason=$expected_reason content=$expected_content"
    echo "  actual:   ok=$actual_ok action=$actual_action reason=$actual_reason content=$actual_content"
    exit 1
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Human Command Parser"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

assert_parse "cc + space forwards to Claude" "auto" "cc 修复登录超时" "true" "forward" "cc_prefix" "修复登录超时"
assert_parse "cc: forwards to Claude" "auto" "cc: 修复登录超时" "true" "forward" "cc_prefix" "修复登录超时"
assert_parse "cc： forwards to Claude" "relay" "cc：修复登录超时" "true" "forward" "cc_prefix" "修复登录超时"
assert_parse "cc newline forwards multiline content" "relay" $'cc\n1. 修复登录超时\n2. 补测试' "true" "forward" "cc_prefix" $'1. 修复登录超时\n2. 补测试'
assert_parse "uppercase CC is accepted" "auto" "CC 补测试" "true" "forward" "cc_prefix" "补测试"
assert_parse "cc without body is rejected" "auto" "cc" "false" "error" "empty_forward_content" ""
assert_parse "cmd继续 stays with agent" "auto" "cmd继续" "true" "continue" "cmd_continue" ""
assert_parse "cmd 停止 stays with agent" "relay" "cmd 停止" "true" "pause" "cmd_pause" ""
assert_parse "cmd:检查 stays with agent" "relay" "cmd:检查" "true" "status" "cmd_status" ""
assert_parse "cmd：退出 stays with agent" "auto" "cmd：退出" "true" "exit" "cmd_exit" ""
assert_parse "single y sends key" "relay" "y" "true" "send_key" "simple_key_reply" "y"
assert_parse "numeric choice sends key" "auto" "2" "true" "send_key" "simple_key_reply" "2"
assert_parse "named key canonicalizes Enter" "auto" "enter" "true" "send_key" "simple_key_reply" "Enter"
assert_parse "plain text defaults to meta" "auto" "不要自动 commit" "true" "meta" "default_meta" "不要自动 commit"
assert_parse "words starting with cc but not prefix stay meta" "relay" "ccache 清理一下" "true" "meta" "default_meta" "ccache 清理一下"
assert_parse "single-char old shortcut is now meta" "auto" "续" "true" "meta" "default_meta" "续"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All parser tests passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
