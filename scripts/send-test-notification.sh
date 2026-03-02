#!/usr/bin/env bash
# send-test-notification.sh - Send a distinctive test notification
# Usage: ./send-test-notification.sh [session-id]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${CC_PROJECT_DIR}/scripts/lib/log.sh"
source "${CC_PROJECT_DIR}/scripts/lib/notify.sh"

SESSION_ID="${1:-${OPENCLAW_SESSION_ID:-}}"

if [ -z "$SESSION_ID" ]; then
  echo "Usage: $0 [session-id]"
  echo "Or set OPENCLAW_SESSION_ID environment variable"
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "发送测试通知"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get routing info
TARGET=""
CHANNEL=""
ROUTING_SOURCE="unknown"

if TARGET=$(get_session_routing_info "$SESSION_ID"); then
  CHANNEL=$(infer_channel_from_target "$TARGET")
  ROUTING_SOURCE="session metadata"
  echo "✓ 从 session 元数据获取路由信息"
  echo "  Channel: $CHANNEL"
  echo "  Target: $TARGET"
else
  TARGET="${OPENCLAW_TARGET:-}"
  CHANNEL="${OPENCLAW_CHANNEL:-discord}"
  ROUTING_SOURCE="environment variables"
  echo "⚠ 使用环境变量作为 fallback"
  echo "  Channel: $CHANNEL"
  echo "  Target: ${TARGET:-<not set>}"
fi
echo ""

# Generate distinctive test message
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TEST_NUMBER=$((RANDOM % 1000))

TEST_MSG="🧪 [cc-supervisor] Session Routing Test #$TEST_NUMBER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏰ Time: $TIMESTAMP
🆔 Session: ${SESSION_ID:0:8}...${SESSION_ID: -4}
📡 Channel: $CHANNEL
🎯 Target: $TARGET
📍 Source: $ROUTING_SOURCE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ If you see this in the CORRECT channel → routing works!
❌ If you see this in webchat → routing failed!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "测试消息内容："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$TEST_MSG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Ask for confirmation
if [[ -t 0 ]]; then
  read -r -p "发送测试通知？(y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
  fi
fi

echo ""
echo "正在发送..."
echo ""

# Send notification
notify "$SESSION_ID" "$TEST_MSG" "test"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "测试通知已发送"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "请检查以下位置："
echo ""

case "$CHANNEL" in
  discord)
    echo "  📱 Discord channel: $TARGET"
    ;;
  telegram)
    echo "  📱 Telegram chat: $TARGET"
    ;;
  whatsapp)
    echo "  📱 WhatsApp: $TARGET"
    ;;
  *)
    echo "  📱 Channel: $CHANNEL"
    echo "  🎯 Target: $TARGET"
    ;;
esac

echo ""
echo "如果消息出现在 webchat 而不是上述位置，说明路由失败。"
echo ""
echo "故障排查："
echo "  1. 运行诊断: ./scripts/diagnose-routing.sh"
echo "  2. 检查日志: tail -f logs/cc-supervisor.log"
echo "  3. 查看队列: cat logs/notification.queue"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
