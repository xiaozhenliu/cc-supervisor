# Session-Based Routing 实施总结

## 修改的文件

### 1. `scripts/lib/notify.sh` - 核心路由逻辑

**新增功能**：
- `get_session_routing_info()`: 从 OpenClaw session store 查询路由信息
- `infer_channel_from_target()`: 根据 target 格式推断 channel

**修改的函数**：
- `_notify_discord()`: 实现混合路由策略
  - 优先查询 session 元数据
  - Fallback 到环境变量
  - 始终使用 `--deliver` 和 `--reply-channel`

**路由策略**：
```bash
# 1. 尝试从 session 获取
if target=$(get_session_routing_info "$session_id"); then
  channel=$(infer_channel_from_target "$target")
  # 使用 session 的实际来源
fi

# 2. Fallback 到环境变量
if [ -z "$target" ]; then
  target="${OPENCLAW_TARGET:-}"
  channel="${OPENCLAW_CHANNEL:-discord}"
fi

# 3. 发送通知（显式路由）
openclaw agent \
  --session-id "$session_id" \
  --message "$msg" \
  --deliver \
  --reply-channel "$channel" \
  ${target:+--reply-to "$target"}
```

### 2. `SKILL.md` - 文档更新

**新增章节**：
- "Notification Routing" 完全重写
- 说明 session-based routing 策略
- 提供命令格式示例
- 解释为什么这种方式更可靠

**关键信息**：
- 路由优先级：session 元数据 > 环境变量
- 始终使用 `--deliver` 和 `--reply-channel`
- 自动适应不同 channel（discord/telegram/webchat）

### 3. `scripts/diagnose-routing.sh` - 诊断工具增强

**新增检查**：
- Step 5: 从 session store 提取路由信息
- Step 7: 对比旧实现和新实现的命令

**输出示例**：
```
【5】检查 OpenClaw session 信息
✓ Session 元数据找到
✓ 路由目标: channel:1464891798139961345
✓ 推断 channel: discord
```

### 4. 新增文件

**分析文档**：
- `docs/notification-routing-analysis.md` - 问题根因分析
- `docs/session-based-routing.md` - 完整实施方案

**测试工具**：
- `scripts/test-session-routing.sh` - 测试 session 路由提取

## 工作原理

### Session 元数据结构

```json
{
  "sessionId": "34a017d4-b4d0-4e4f-9d2b-5c18f91acaf5",
  "deliveryContext": {
    "to": "channel:1464891798139961345"
  },
  "origin": {
    "from": "channel:1464891798139961345",
    "to": "channel:1464891798139961345",
    "provider": "heartbeat"
  },
  "lastTo": "channel:1464891798139961345"
}
```

### 提取优先级

1. `deliveryContext.to` (最优先)
2. `lastTo` (次优先)
3. `origin.to` (最后)

### Channel 推断规则

| Target 格式 | 推断的 Channel |
|------------|---------------|
| `channel:123` 或 `user:123` | discord |
| `chat:123` | telegram |
| `+1234567890` | whatsapp |
| 其他 | discord (默认) |

## 优势

### 之前（环境变量）

```bash
# 问题 1: 缺少 --reply-channel
openclaw agent \
  --session-id "$session_id" \
  --message "$msg" \
  ${OPENCLAW_TARGET:+--deliver} \
  ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"}

# 问题 2: OPENCLAW_TARGET 未设置时不发送
# 问题 3: 依赖手动配置的环境变量
# 问题 4: 可能与 session 实际来源不一致
```

### 现在（Session 元数据）

```bash
# 优点 1: 始终添加 --deliver 和 --reply-channel
# 优点 2: 自动从 session 获取实际来源
# 优点 3: 不依赖手动配置
# 优点 4: 确保"从哪来，回哪去"

openclaw agent \
  --session-id "$session_id" \
  --message "$msg" \
  --deliver \
  --reply-channel "$channel" \
  --reply-to "$target"
```

## 向后兼容

- 如果环境变量已正确设置，直接使用（快速路径）
- 如果环境变量缺失，自动查询 session（可靠路径）
- 如果 session 不存在（新 UUID），fallback 到环境变量
- 不会破坏现有配置

## 测试步骤

### 1. 诊断当前环境

```bash
./scripts/diagnose-routing.sh
```

### 2. 测试 session 路由提取

```bash
./scripts/test-session-routing.sh
```

### 3. 测试实际通知

```bash
# 设置 session ID
export OPENCLAW_SESSION_ID="your-session-id"

# 发送测试通知
source scripts/lib/notify.sh
notify "$OPENCLAW_SESSION_ID" "Test notification" "test"

# 检查日志
tail -f logs/cc-supervisor.log
```

### 4. 验证路由

检查通知是否到达正确的 channel：
- Discord: 检查对应的 channel
- Telegram: 检查对应的 chat
- Webchat: 检查 OpenClaw web 界面

## 故障排查

### 问题 1: Session 未找到

**症状**: 日志显示 "Failed to get routing info from session"

**原因**:
- Session ID 是新生成的临时 UUID
- Session 已过期被清理
- Session store 文件不存在

**解决**:
- 设置环境变量作为 fallback
- 使用真实的 session ID（从 OpenClaw 获取）

### 问题 2: jq 未安装

**症状**: Session 查询失败

**原因**: `jq` 命令不可用

**解决**:
```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq
```

### 问题 3: 仍然走 webchat

**症状**: 消息仍然发送到 webchat

**可能原因**:
1. Session 的实际来源就是 webchat
2. Target 格式无法识别，默认为 discord 但路由失败
3. OpenClaw 配置问题

**诊断**:
```bash
# 查看 session 的实际来源
./scripts/test-session-routing.sh

# 检查 OpenClaw 配置
cat ~/.openclaw/openclaw.json | jq .
```

## 性能考虑

### 查询开销

- 每次通知需要读取 session store JSON 文件
- 使用 `jq` 解析 JSON（快速）
- 典型开销：< 10ms

### 优化建议

如果性能成为问题，可以考虑：
1. 缓存 session 路由信息（方案 C）
2. 优先使用环境变量（如果已正确设置）
3. 定期清理过期 session

## 相关文件

- `scripts/lib/notify.sh` - 核心实现
- `SKILL.md` - 使用文档
- `scripts/diagnose-routing.sh` - 诊断工具
- `scripts/test-session-routing.sh` - 测试工具
- `docs/notification-routing-analysis.md` - 问题分析
- `docs/session-based-routing.md` - 实施方案
