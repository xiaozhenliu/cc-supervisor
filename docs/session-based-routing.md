# 基于 Session 元数据的可靠路由方案

## 核心思路

**不依赖环境变量，而是从 OpenClaw session 元数据中查询来源 channel 和 target，确保回复路由到正确的地方。**

## Session 元数据结构

通过 `openclaw sessions --json` 或直接读取 `~/.openclaw/agents/{agent}/sessions/sessions.json`，可以获取 session 的完整元数据：

```json
{
  "sessionId": "34a017d4-b4d0-4e4f-9d2b-5c18f91acaf5",
  "deliveryContext": {
    "to": "channel:1464891798139961345"
  },
  "origin": {
    "label": "channel:1464891798139961345",
    "provider": "heartbeat",
    "from": "channel:1464891798139961345",
    "to": "channel:1464891798139961345"
  },
  "chatType": "direct",
  "lastTo": "channel:1464891798139961345"
}
```

**关键字段**：
- `deliveryContext.to`: 回复目标（最可靠）
- `lastTo`: 最后的目标（fallback）
- `origin.from`: 消息来源
- `origin.provider`: 来源提供商

## 实现方案

### 方案 A: 查询 session 元数据（推荐）

**优点**：
- 最可靠：使用 session 的实际来源信息
- 不依赖环境变量
- 自动适应不同的 channel（discord/telegram/webchat）

**缺点**：
- 需要额外的查询操作（性能开销）
- 如果 session 不存在会失败

**实现**：

```bash
# 1. 查询 session 元数据
get_session_routing_info() {
  local session_id="$1"
  local agent_id="${OPENCLAW_AGENT_ID:-main}"
  local session_file="$HOME/.openclaw/agents/$agent_id/sessions/sessions.json"

  if [ ! -f "$session_file" ]; then
    log_warn "Session file not found: $session_file"
    return 1
  fi

  # 从 session 文件中提取路由信息
  local session_data=$(jq -r \
    --arg sid "$session_id" \
    'to_entries[] | select(.value.sessionId == $sid) | .value' \
    "$session_file" 2>/dev/null)

  if [ -z "$session_data" ]; then
    log_warn "Session not found: $session_id"
    return 1
  fi

  # 提取 deliveryContext.to（最优先）
  local delivery_to=$(echo "$session_data" | jq -r '.deliveryContext.to // empty')

  # 如果没有 deliveryContext，使用 lastTo
  if [ -z "$delivery_to" ]; then
    delivery_to=$(echo "$session_data" | jq -r '.lastTo // empty')
  fi

  # 如果还是没有，使用 origin.to
  if [ -z "$delivery_to" ]; then
    delivery_to=$(echo "$session_data" | jq -r '.origin.to // empty')
  fi

  if [ -n "$delivery_to" ]; then
    echo "$delivery_to"
    return 0
  else
    log_warn "No routing target found in session"
    return 1
  fi
}

# 2. 从 target 推断 channel
infer_channel_from_target() {
  local target="$1"

  # target 格式: channel:123456789 或 user:123456789
  if [[ "$target" =~ ^channel: ]] || [[ "$target" =~ ^user: ]]; then
    # Discord 格式
    echo "discord"
  elif [[ "$target" =~ ^chat: ]]; then
    # Telegram 格式
    echo "telegram"
  elif [[ "$target" =~ ^\+[0-9]+ ]]; then
    # WhatsApp 格式 (E.164)
    echo "whatsapp"
  else
    # 默认
    echo "discord"
  fi
}

# 3. 使用查询到的信息发送通知
_notify_discord() {
  local session_id="$1"
  local msg="$2"
  local event_type="${3:-unknown}"

  # 查询 session 路由信息
  local target=""
  local channel=""

  if target=$(get_session_routing_info "$session_id"); then
    channel=$(infer_channel_from_target "$target")
    log_info "Routing from session metadata: channel=$channel target=$target"
  else
    # Fallback 到环境变量
    target="${OPENCLAW_TARGET:-}"
    channel="${OPENCLAW_CHANNEL:-discord}"
    log_warn "Using fallback routing: channel=$channel target=$target"
  fi

  # 发送通知
  if openclaw agent \
      --session-id "$session_id" \
      --message "$msg" \
      --deliver \
      --reply-channel "$channel" \
      ${target:+--reply-to "$target"} \
      2>/dev/null; then
    log_info "Notification sent: channel=$channel target=$target"
  else
    log_warn "Notification failed — queuing"
    _notify_enqueue "$msg" "$event_type"
  fi
}
```

### 方案 B: 混合方案（平衡性能和可靠性）

**优点**：
- 优先使用环境变量（快速）
- 环境变量缺失时查询 session（可靠）
- 兼顾性能和可靠性

**实现**：

```bash
_notify_discord() {
  local session_id="$1"
  local msg="$2"
  local event_type="${3:-unknown}"

  local target="${OPENCLAW_TARGET:-}"
  local channel="${OPENCLAW_CHANNEL:-discord}"

  # 如果环境变量未设置，查询 session
  if [ -z "$target" ]; then
    log_info "OPENCLAW_TARGET not set, querying session metadata..."
    if target=$(get_session_routing_info "$session_id"); then
      channel=$(infer_channel_from_target "$target")
      log_info "Routing from session: channel=$channel target=$target"
    else
      log_warn "Failed to get routing info from session, notification may fail"
    fi
  fi

  # 发送通知（始终添加 --deliver 和 --reply-channel）
  if openclaw agent \
      --session-id "$session_id" \
      --message "$msg" \
      --deliver \
      --reply-channel "$channel" \
      ${target:+--reply-to "$target"} \
      2>/dev/null; then
    log_info "Notification sent: channel=$channel target=$target"
  else
    log_warn "Notification failed — queuing"
    _notify_enqueue "$msg" "$event_type"
  fi
}
```

### 方案 C: 缓存 session 路由信息（最优性能）

**优点**：
- 第一次查询后缓存结果
- 后续通知使用缓存（无性能开销）
- 仍然保持可靠性

**实现**：

```bash
# 全局缓存
declare -A SESSION_ROUTING_CACHE

get_cached_routing_info() {
  local session_id="$1"

  # 检查缓存
  if [ -n "${SESSION_ROUTING_CACHE[$session_id]:-}" ]; then
    echo "${SESSION_ROUTING_CACHE[$session_id]}"
    return 0
  fi

  # 查询并缓存
  if target=$(get_session_routing_info "$session_id"); then
    channel=$(infer_channel_from_target "$target")
    SESSION_ROUTING_CACHE[$session_id]="$channel|$target"
    echo "$channel|$target"
    return 0
  else
    return 1
  fi
}

_notify_discord() {
  local session_id="$1"
  local msg="$2"
  local event_type="${3:-unknown}"

  local target="${OPENCLAW_TARGET:-}"
  local channel="${OPENCLAW_CHANNEL:-discord}"

  # 如果环境变量未设置，使用缓存的路由信息
  if [ -z "$target" ]; then
    if routing_info=$(get_cached_routing_info "$session_id"); then
      channel="${routing_info%%|*}"
      target="${routing_info##*|}"
      log_info "Using cached routing: channel=$channel target=$target"
    fi
  fi

  # 发送通知
  if openclaw agent \
      --session-id "$session_id" \
      --message "$msg" \
      --deliver \
      --reply-channel "$channel" \
      ${target:+--reply-to "$target"} \
      2>/dev/null; then
    log_info "Notification sent: channel=$channel target=$target"
  else
    log_warn "Notification failed — queuing"
    _notify_enqueue "$msg" "$event_type"
  fi
}
```

## 推荐实施方案

**方案 B（混合方案）** 是最佳选择，因为：

1. **向后兼容**：如果环境变量已正确设置，直接使用（快速）
2. **自动修复**：如果环境变量缺失，自动查询 session（可靠）
3. **简单实现**：不需要复杂的缓存机制
4. **易于调试**：日志清楚显示使用了哪种路由方式

## 实施步骤

### 1. 修改 `scripts/lib/notify.sh`

添加辅助函数：

```bash
# 在文件开头添加
get_session_routing_info() {
  local session_id="$1"
  local agent_id="${OPENCLAW_AGENT_ID:-main}"
  local session_file="$HOME/.openclaw/agents/$agent_id/sessions/sessions.json"

  if [ ! -f "$session_file" ]; then
    return 1
  fi

  local session_data=$(jq -r \
    --arg sid "$session_id" \
    'to_entries[] | select(.value.sessionId == $sid) | .value' \
    "$session_file" 2>/dev/null)

  if [ -z "$session_data" ]; then
    return 1
  fi

  # 优先级: deliveryContext.to > lastTo > origin.to
  local delivery_to=$(echo "$session_data" | jq -r '.deliveryContext.to // .lastTo // .origin.to // empty')

  if [ -n "$delivery_to" ]; then
    echo "$delivery_to"
    return 0
  else
    return 1
  fi
}

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
```

修改 `_notify_discord` 函数：

```bash
_notify_discord() {
  local session_id="$1"
  local msg="$2"
  local event_type="${3:-unknown}"

  if [[ -z "$session_id" ]]; then
    log_warn "OPENCLAW_SESSION_ID not set — queuing for later replay (event=$event_type)"
    _notify_enqueue "$msg" "$event_type"
    return 0
  fi

  if ! command -v openclaw &>/dev/null; then
    log_warn "openclaw not in PATH — queuing notification (event=$event_type)"
    _notify_enqueue "$msg" "$event_type"
    return 0
  fi

  # 获取路由信息：优先使用环境变量，否则查询 session
  local target="${OPENCLAW_TARGET:-}"
  local channel="${OPENCLAW_CHANNEL:-discord}"

  if [ -z "$target" ]; then
    log_info "OPENCLAW_TARGET not set, querying session metadata..."
    if target=$(get_session_routing_info "$session_id"); then
      channel=$(infer_channel_from_target "$target")
      log_info "Routing from session: channel=$channel target=$target"
    else
      log_warn "Failed to get routing info from session"
    fi
  fi

  # 发送通知（始终添加 --deliver 和 --reply-channel）
  if openclaw agent \
      --session-id "$session_id" \
      --message "$msg" \
      --deliver \
      --reply-channel "$channel" \
      ${target:+--reply-to "$target"} \
      2>/dev/null; then
    log_info "openclaw agent triggered: channel=$channel target=${target:-<default>} event=$event_type session=$session_id"
  else
    log_warn "openclaw agent failed — queuing (event=$event_type)"
    _notify_enqueue "$msg" "$event_type"
  fi
}
```

### 2. 更新诊断脚本

在 `scripts/diagnose-routing.sh` 中添加 session 元数据检查：

```bash
echo "【8】测试 session 元数据查询"
echo "────────────────────────────────────────────────────────────────"

if [ -n "${OPENCLAW_SESSION_ID:-}" ]; then
  AGENT_ID="${OPENCLAW_AGENT_ID:-main}"
  SESSION_FILE="$HOME/.openclaw/agents/$AGENT_ID/sessions/sessions.json"

  if [ -f "$SESSION_FILE" ]; then
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
    else
      echo "⚠ Session 在 session store 中未找到"
    fi
  else
    echo "⚠ Session store 文件不存在: $SESSION_FILE"
  fi
else
  echo "⚠ 跳过（OPENCLAW_SESSION_ID 未设置）"
fi
```

### 3. 测试

```bash
# 1. 运行诊断
./scripts/diagnose-routing.sh

# 2. 测试路由查询
source scripts/lib/notify.sh
get_session_routing_info "$OPENCLAW_SESSION_ID"

# 3. 测试完整通知流程
notify "$OPENCLAW_SESSION_ID" "Test notification" "test"
```

## 优势总结

| 方面 | 之前（环境变量） | 现在（session 元数据） |
|------|-----------------|---------------------|
| **可靠性** | 依赖手动设置 | 自动从 session 获取 |
| **准确性** | 可能过期或错误 | 始终是 session 的实际来源 |
| **维护性** | 需要用户配置 | 自动工作 |
| **跨 channel** | 需要为每个 channel 配置 | 自动适应 |
| **错误恢复** | 失败后难以修复 | 自动 fallback |

## 注意事项

1. **jq 依赖**: 需要确保 `jq` 已安装（install.sh 已检查）
2. **Session 文件位置**: 默认在 `~/.openclaw/agents/main/sessions/sessions.json`
3. **性能**: 每次通知需要读取 JSON 文件（可以考虑缓存）
4. **新 session**: 如果是新生成的临时 UUID，session 文件中可能不存在（fallback 到环境变量）
