#!/usr/bin/env bash
# diagnose-routing.sh - Diagnose notification routing issues
# Usage: ./diagnose-routing.sh

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

source "${CC_PROJECT_DIR}/scripts/lib/runtime_context.sh"

REQUESTED_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      REQUESTED_ID="${2:?'--id requires a supervision id'}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

runtime_context_init "${REQUESTED_ID:-${CC_SUPERVISION_ID:-default}}"
SESSION_NAME="$CC_TMUX_SESSION"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "通知路由诊断工具"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Check environment variables ───────────────────────────────────────
echo "【1】检查环境变量"
echo "────────────────────────────────────────────────────────────────"

check_var() {
  local var_name="$1"
  local var_value="${!var_name:-}"
  if [ -n "$var_value" ]; then
    echo "✓ $var_name = $var_value"
  else
    echo "✗ $var_name = <未设置>"
  fi
}

check_var "OPENCLAW_SESSION_ID"
check_var "OPENCLAW_CHANNEL"
check_var "OPENCLAW_TARGET"
check_var "OPENCLAW_ACCOUNT"
echo ""

# ── Step 2: Check tmux session environment ────────────────────────────────────
echo "【2】检查 tmux session 环境"
echo "────────────────────────────────────────────────────────────────"

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "✓ tmux session '$SESSION_NAME' 存在"
  echo ""
  echo "环境变量："
  tmux show-environment -t "$SESSION_NAME" | grep -E 'OPENCLAW|CC_SUPERVISION_ID|CC_RUNTIME_DIR|CC_EVENTS_FILE' || echo "  (无相关变量)"
else
  echo "✗ tmux session '$SESSION_NAME' 不存在"
fi
echo ""

# ── Step 3: Validate OPENCLAW_TARGET format ───────────────────────────────────
echo "【3】验证 OPENCLAW_TARGET 格式"
echo "────────────────────────────────────────────────────────────────"

if [ -n "${OPENCLAW_TARGET:-}" ]; then
  if [[ "$OPENCLAW_TARGET" =~ ^(channel|user|chat):[0-9]+$ ]]; then
    echo "✓ 格式正确: $OPENCLAW_TARGET"
  else
    echo "✗ 格式错误: $OPENCLAW_TARGET"
    echo "  预期格式: channel:123456789 或 user:123456789"
  fi
else
  echo "⚠ OPENCLAW_TARGET 未设置"
  echo "  这会导致消息无法路由到 Discord"
fi
echo ""

# ── Step 4: Check OpenClaw CLI ────────────────────────────────────────────────
echo "【4】检查 OpenClaw CLI"
echo "────────────────────────────────────────────────────────────────"

if command -v openclaw &>/dev/null; then
  OPENCLAW_VERSION=$(openclaw --version 2>&1 | head -1)
  echo "✓ openclaw 已安装: $OPENCLAW_VERSION"
else
  echo "✗ openclaw 未安装或不在 PATH 中"
  echo "  安装: npm install -g openclaw@latest"
fi
echo ""

# ── Step 5: Check session info ────────────────────────────────────────────────
echo "【5】检查 OpenClaw session 信息"
echo "────────────────────────────────────────────────────────────────"

if [ -n "${OPENCLAW_SESSION_ID:-}" ] && command -v openclaw &>/dev/null; then
  AGENT_ID="${OPENCLAW_AGENT_ID:-main}"
  SESSION_FILE="$HOME/.openclaw/agents/$AGENT_ID/sessions/sessions.json"

  if [ -f "$SESSION_FILE" ] && command -v jq &>/dev/null; then
    SESSION_DATA=$(jq -r \
      --arg sid "$OPENCLAW_SESSION_ID" \
      'to_entries[] | select(.value.sessionId == $sid) | .value' \
      "$SESSION_FILE" 2>/dev/null)

    if [ -n "$SESSION_DATA" ]; then
      echo "✓ Session 元数据找到"
      echo ""
      echo "路由信息："
      echo "$SESSION_DATA" | jq '{
        deliveryContext,
        origin,
        lastTo,
        chatType
      }'
      echo ""

      # Extract routing target
      DELIVERY_TO=$(echo "$SESSION_DATA" | jq -r '.deliveryContext.to // .lastTo // .origin.to // empty')
      if [ -n "$DELIVERY_TO" ]; then
        echo "✓ 路由目标: $DELIVERY_TO"

        # Infer channel
        if [[ "$DELIVERY_TO" =~ ^(channel|user): ]]; then
          INFERRED_CHANNEL="discord"
        elif [[ "$DELIVERY_TO" =~ ^chat: ]]; then
          INFERRED_CHANNEL="telegram"
        elif [[ "$DELIVERY_TO" =~ ^\+[0-9]+ ]]; then
          INFERRED_CHANNEL="whatsapp"
        else
          INFERRED_CHANNEL="discord"
        fi
        echo "✓ 推断 channel: $INFERRED_CHANNEL"
      else
        echo "⚠ 无法从 session 提取路由目标"
      fi
    else
      echo "⚠ Session 在 session store 中未找到"
      echo "  可能是新生成的临时 UUID"
    fi
  else
    if [ ! -f "$SESSION_FILE" ]; then
      echo "⚠ Session store 文件不存在: $SESSION_FILE"
    elif ! command -v jq &>/dev/null; then
      echo "⚠ jq 未安装，无法解析 session 数据"
    fi
  fi
else
  echo "⚠ 跳过（OPENCLAW_SESSION_ID 未设置或 openclaw 未安装）"
fi
echo ""

# ── Step 6: Check notification queue ──────────────────────────────────────────
echo "【6】检查通知队列"
echo "────────────────────────────────────────────────────────────────"

QUEUE_FILE="$CC_NOTIFICATION_QUEUE_FILE"

if [ -f "$QUEUE_FILE" ]; then
  QUEUE_COUNT=$(wc -l < "$QUEUE_FILE" | tr -d ' ')
  echo "✓ 队列文件存在: $QUEUE_FILE"
  echo "  队列中有 $QUEUE_COUNT 条消息"

  if [ "$QUEUE_COUNT" -gt 0 ]; then
    echo ""
    echo "最近 3 条队列消息："
    tail -3 "$QUEUE_FILE" | while IFS='|' read -r timestamp channel account target event_type msg; do
      echo "  - 时间: $timestamp"
      echo "    channel: $channel"
      echo "    target: $target"
      echo "    事件: $event_type"
      echo "    消息: ${msg:0:50}..."
      echo ""
    done
  fi
else
  echo "✓ 队列文件不存在（没有失败的通知）"
fi
echo ""

# ── Step 7: Test routing command ──────────────────────────────────────────────
echo "【7】测试路由命令"
echo "────────────────────────────────────────────────────────────────"

if [ -n "${OPENCLAW_SESSION_ID:-}" ] && command -v openclaw &>/dev/null; then
  echo "当前使用的命令（旧实现，有问题）："
  echo ""

  if [ -n "${OPENCLAW_TARGET:-}" ]; then
    echo "  openclaw agent \\"
    echo "    --session-id \"$OPENCLAW_SESSION_ID\" \\"
    echo "    --message \"[test]\" \\"
    echo "    --deliver \\"
    echo "    --reply-to \"$OPENCLAW_TARGET\""
    echo ""
    echo "  ⚠ 问题：缺少 --reply-channel，可能路由到错误的 channel"
  else
    echo "  openclaw agent \\"
    echo "    --session-id \"$OPENCLAW_SESSION_ID\" \\"
    echo "    --message \"[test]\""
    echo ""
    echo "  ⚠ 问题：没有 --deliver 标志，消息不会发送！"
  fi

  echo ""
  echo "新实现（基于 session 元数据）："
  echo ""

  # Try to get routing from session
  if [ -n "${DELIVERY_TO:-}" ] && [ -n "${INFERRED_CHANNEL:-}" ]; then
    echo "  # 从 session 元数据获取路由信息"
    echo "  openclaw agent \\"
    echo "    --session-id \"$OPENCLAW_SESSION_ID\" \\"
    echo "    --message \"[test]\" \\"
    echo "    --deliver \\"
    echo "    --reply-channel \"$INFERRED_CHANNEL\" \\"
    echo "    --reply-to \"$DELIVERY_TO\""
  else
    echo "  # Fallback 到环境变量"
    echo "  openclaw agent \\"
    echo "    --session-id \"$OPENCLAW_SESSION_ID\" \\"
    echo "    --message \"[test]\" \\"
    echo "    --deliver \\"
    echo "    --reply-channel \"${OPENCLAW_CHANNEL:-discord}\" \\"
    if [ -n "${OPENCLAW_TARGET:-}" ]; then
      echo "    --reply-to \"$OPENCLAW_TARGET\""
    else
      echo "    # --reply-to 未设置，将使用 channel 默认目标"
    fi
  fi
else
  echo "⚠ 跳过（OPENCLAW_SESSION_ID 未设置或 openclaw 未安装）"
fi
echo ""

# ── Summary ────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "诊断总结"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ISSUES=()

[ -z "${OPENCLAW_SESSION_ID:-}" ] && ISSUES+=("OPENCLAW_SESSION_ID 未设置")
[ -z "${OPENCLAW_TARGET:-}" ] && ISSUES+=("OPENCLAW_TARGET 未设置（消息可能走 webchat）")
[ -n "${OPENCLAW_TARGET:-}" ] && ! [[ "$OPENCLAW_TARGET" =~ ^(channel|user|chat):[0-9]+$ ]] && ISSUES+=("OPENCLAW_TARGET 格式错误")
! command -v openclaw &>/dev/null && ISSUES+=("openclaw CLI 未安装")

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo "✓ 未发现明显问题"
  echo ""
  echo "如果消息仍然走 webchat，可能的原因："
  echo "  1. notify.sh 缺少 --reply-channel 参数"
  echo "  2. OpenClaw session 的原始 channel 是 webchat"
  echo "  3. Discord channel 配置错误"
  echo ""
  echo "建议：修改 notify.sh 添加 --reply-channel 参数（见方案文档）"
else
  echo "发现以下问题："
  for issue in "${ISSUES[@]}"; do
    echo "  ✗ $issue"
  done
  echo ""
  echo "请先修复这些问题，然后重新运行诊断。"
fi
echo ""
echo "详细分析和解决方案："
echo "  - docs/openclaw-reference.md (OpenClaw 命令与路由参数参考)"
echo "  - docs/agent-hierarchy.md (会话与通知路由背景)"
echo ""
echo "测试 session 路由："
echo "  ./scripts/test-session-routing.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
