#!/usr/bin/env bash
# test-session-routing.sh - Test session-based routing
# Usage: ./test-session-routing.sh [session-id]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${CC_PROJECT_DIR}/scripts/lib/log.sh"

SESSION_ID="${1:-${OPENCLAW_SESSION_ID:-}}"

if [ -z "$SESSION_ID" ]; then
  echo "Usage: $0 [session-id]"
  echo "Or set OPENCLAW_SESSION_ID environment variable"
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "测试基于 Session 的路由"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Session ID: $SESSION_ID"
echo ""

# ── Function: get_session_routing_info ────────────────────────────────────────
get_session_routing_info() {
  local session_id="$1"
  local agent_id="${OPENCLAW_AGENT_ID:-main}"
  local session_file="$HOME/.openclaw/agents/$agent_id/sessions/sessions.json"

  if [ ! -f "$session_file" ]; then
    log_warn "Session file not found: $session_file"
    return 1
  fi

  local session_data=$(jq -r \
    --arg sid "$session_id" \
    'to_entries[] | select(.value.sessionId == $sid) | .value' \
    "$session_file" 2>/dev/null)

  if [ -z "$session_data" ]; then
    log_warn "Session not found: $session_id"
    return 1
  fi

  # 优先级: deliveryContext.to > lastTo > origin.to
  local delivery_to=$(echo "$session_data" | jq -r '.deliveryContext.to // .lastTo // .origin.to // empty')

  if [ -n "$delivery_to" ]; then
    echo "$delivery_to"
    return 0
  else
    log_warn "No routing target found in session"
    return 1
  fi
}

# ── Function: infer_channel_from_target ───────────────────────────────────────
infer_channel_from_target() {
  local target="$1"

  if [[ "$target" =~ ^(channel|user): ]]; then
    echo "discord"
  elif [[ "$target" =~ ^chat: ]]; then
    echo "telegram"
  elif [[ "$target" =~ ^\+[0-9]+ ]]; then
    echo "whatsapp"
  else
    echo "discord"
  fi
}

# ── Test 1: Query session metadata ────────────────────────────────────────────
echo "【测试 1】查询 session 元数据"
echo "────────────────────────────────────────────────────────────────"

AGENT_ID="${OPENCLAW_AGENT_ID:-main}"
SESSION_FILE="$HOME/.openclaw/agents/$AGENT_ID/sessions/sessions.json"

if [ ! -f "$SESSION_FILE" ]; then
  echo "✗ Session file not found: $SESSION_FILE"
  exit 1
fi

echo "Session file: $SESSION_FILE"
echo ""

SESSION_DATA=$(jq -r \
  --arg sid "$SESSION_ID" \
  'to_entries[] | select(.value.sessionId == $sid) | .value' \
  "$SESSION_FILE" 2>/dev/null)

if [ -z "$SESSION_DATA" ]; then
  echo "✗ Session not found in session store"
  echo ""
  echo "可能原因："
  echo "  1. Session ID 不存在或已过期"
  echo "  2. Session 与当前 channel/target 不匹配"
  echo "  3. Agent ID 不正确 (current: $AGENT_ID)"
  exit 1
fi

echo "✓ Session found"
echo ""
echo "完整 session 数据："
echo "$SESSION_DATA" | jq '.'
echo ""

# ── Test 2: Extract routing info ──────────────────────────────────────────────
echo "【测试 2】提取路由信息"
echo "────────────────────────────────────────────────────────────────"

DELIVERY_TO=$(echo "$SESSION_DATA" | jq -r '.deliveryContext.to // empty')
LAST_TO=$(echo "$SESSION_DATA" | jq -r '.lastTo // empty')
ORIGIN_TO=$(echo "$SESSION_DATA" | jq -r '.origin.to // empty')
ORIGIN_FROM=$(echo "$SESSION_DATA" | jq -r '.origin.from // empty')
ORIGIN_PROVIDER=$(echo "$SESSION_DATA" | jq -r '.origin.provider // empty')

echo "deliveryContext.to: ${DELIVERY_TO:-<empty>}"
echo "lastTo: ${LAST_TO:-<empty>}"
echo "origin.to: ${ORIGIN_TO:-<empty>}"
echo "origin.from: ${ORIGIN_FROM:-<empty>}"
echo "origin.provider: ${ORIGIN_PROVIDER:-<empty>}"
echo ""

# ── Test 3: Determine routing target ──────────────────────────────────────────
echo "【测试 3】确定路由目标"
echo "────────────────────────────────────────────────────────────────"

if TARGET=$(get_session_routing_info "$SESSION_ID"); then
  echo "✓ Routing target: $TARGET"

  CHANNEL=$(infer_channel_from_target "$TARGET")
  echo "✓ Inferred channel: $CHANNEL"
else
  echo "✗ Failed to get routing target"
  exit 1
fi
echo ""

# ── Test 4: Compare with environment variables ────────────────────────────────
echo "【测试 4】对比环境变量"
echo "────────────────────────────────────────────────────────────────"

ENV_CHANNEL="${OPENCLAW_CHANNEL:-<not set>}"
ENV_TARGET="${OPENCLAW_TARGET:-<not set>}"

echo "环境变量:"
echo "  OPENCLAW_CHANNEL: $ENV_CHANNEL"
echo "  OPENCLAW_TARGET: $ENV_TARGET"
echo ""
echo "Session 元数据:"
echo "  Channel: $CHANNEL"
echo "  Target: $TARGET"
echo ""

if [ "$ENV_CHANNEL" != "$CHANNEL" ] || [ "$ENV_TARGET" != "$TARGET" ]; then
  echo "⚠ 不一致！"
  echo ""
  echo "建议："
  echo "  export OPENCLAW_CHANNEL=\"$CHANNEL\""
  echo "  export OPENCLAW_TARGET=\"$TARGET\""
else
  echo "✓ 一致"
fi
echo ""

# ── Test 5: Build openclaw command ────────────────────────────────────────────
echo "【测试 5】构建 openclaw 命令"
echo "────────────────────────────────────────────────────────────────"

echo "当前实现（可能有问题）："
echo ""
if [ -n "${OPENCLAW_TARGET:-}" ]; then
  echo "  openclaw agent \\"
  echo "    --session-id \"$SESSION_ID\" \\"
  echo "    --message \"[test]\" \\"
  echo "    --deliver \\"
  echo "    --reply-to \"$OPENCLAW_TARGET\""
else
  echo "  openclaw agent \\"
  echo "    --session-id \"$SESSION_ID\" \\"
  echo "    --message \"[test]\""
  echo ""
  echo "  ⚠ 没有 --deliver，消息不会发送！"
fi
echo ""

echo "推荐实现（基于 session 元数据）："
echo ""

# Generate a distinctive test message
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TEST_MSG="🧪 [cc-supervisor] Session Routing Test
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Time: $TIMESTAMP
Session: ${SESSION_ID:0:8}...
Channel: $CHANNEL
Target: $TARGET
Source: session metadata
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
If you see this message in the CORRECT channel, session-based routing works! ✓"

echo "  openclaw agent \\"
echo "    --session-id \"$SESSION_ID\" \\"
echo "    --message \"\$TEST_MSG\" \\"
echo "    --deliver \\"
echo "    --reply-channel \"$CHANNEL\" \\"
echo "    --reply-to \"$TARGET\""
echo ""
echo "实际测试消息内容："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$TEST_MSG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Summary ────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "测试总结"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✓ Session 元数据查询成功"
echo "✓ 路由信息提取成功"
echo "  - Channel: $CHANNEL"
echo "  - Target: $TARGET"
echo ""
echo "下一步："
echo "  1. 发送实际测试通知（可选）："
echo "     openclaw agent --session-id \"$SESSION_ID\" --message \"\$TEST_MSG\" --deliver --reply-channel \"$CHANNEL\" --reply-to \"$TARGET\""
echo ""
echo "  2. 或使用 notify 函数测试："
echo "     source scripts/lib/notify.sh"
echo "     notify \"$SESSION_ID\" \"\$TEST_MSG\" \"test\""
echo ""
echo "  3. 验证消息是否到达正确的 channel"
echo ""
echo "参考文档：docs/openclaw-reference.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
