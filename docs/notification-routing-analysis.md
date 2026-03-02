# 通知路由问题分析：为什么消息走 webchat 而不是 Discord

## 问题现象

大部分消息走了 webchat 而不是 Discord 频道。

## 根本原因分析

### 1. OpenClaw 路由机制

根据 `openclaw agent --help` 和代码分析，OpenClaw 的路由逻辑是：

```bash
openclaw agent \
  --session-id "$OPENCLAW_SESSION_ID" \
  --message "$msg" \
  ${OPENCLAW_TARGET:+--deliver} \
  ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"}
```

**关键点**：
- `--session-id`: 指定会话 ID（必需）
- `--deliver`: 是否发送回复（如果没有这个标志，消息不会发送）
- `--reply-to`: 指定回复目标（如果没有，使用 session 的默认路由）

### 2. 当前实现的问题

查看 `scripts/lib/notify.sh` 第 48-53 行：

```bash
if openclaw agent \
    --session-id "$session_id" \
    --message "$msg" \
    ${OPENCLAW_TARGET:+--deliver} \
    ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"} \
    2>/dev/null; then
```

**问题所在**：

1. **条件性添加 `--deliver`**: 只有当 `OPENCLAW_TARGET` 设置时才添加 `--deliver`
   - 如果 `OPENCLAW_TARGET` 为空，`--deliver` 不会被添加
   - 没有 `--deliver`，消息不会被发送到任何地方

2. **缺少 `--reply-channel`**: 没有指定 `--reply-channel discord`
   - OpenClaw 可能使用 session 的默认 channel（可能是 webchat）
   - 即使设置了 `OPENCLAW_CHANNEL=discord` 环境变量，也没有传递给 `openclaw agent` 命令

3. **`OPENCLAW_TARGET` 的含义不明确**:
   - 从代码看，`OPENCLAW_TARGET` 应该是 Discord channel ID 或用户 ID
   - 但如果未设置或设置错误，路由就会失败

### 3. 为什么走 webchat？

**推测的路由逻辑**：

```
如果 OPENCLAW_TARGET 为空：
  → 不添加 --deliver
  → 消息不发送（或发送到 session 默认路由）
  → session 默认路由可能是 webchat

如果 OPENCLAW_TARGET 设置但没有 --reply-channel：
  → OpenClaw 使用 session 的原始 channel
  → 如果 session 是从 webchat 创建的，就回到 webchat
```

### 4. 环境变量传递链

检查环境变量的传递路径：

1. **用户设置** (在 `~/.zshrc`):
   ```bash
   export OPENCLAW_CHANNEL=discord
   export OPENCLAW_TARGET=<discord-channel-id>
   ```

2. **传递到 tmux session** (`supervisor_run.sh` 第 76-78 行):
   ```bash
   -e "OPENCLAW_CHANNEL=${OPENCLAW_CHANNEL:-}" \
   -e "OPENCLAW_ACCOUNT=${OPENCLAW_ACCOUNT:-}" \
   -e "OPENCLAW_TARGET=${OPENCLAW_TARGET:-}"
   ```

3. **传递到 hook 脚本** (通过 tmux 环境):
   - Hook 脚本继承 tmux session 的环境变量

4. **使用在 notify.sh** (第 51-52 行):
   ```bash
   ${OPENCLAW_TARGET:+--deliver} \
   ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"}
   ```

**问题**：即使 `OPENCLAW_CHANNEL=discord`，也没有传递给 `openclaw agent` 命令！

## 可能的失败场景

### 场景 1: OPENCLAW_TARGET 未设置

```bash
# 用户忘记设置
unset OPENCLAW_TARGET

# 结果
openclaw agent --session-id "xxx" --message "msg"
# 没有 --deliver，消息不发送或走默认路由（webchat）
```

### 场景 2: OPENCLAW_TARGET 设置但格式错误

```bash
# 用户设置了错误的格式
export OPENCLAW_TARGET="my-channel"  # 应该是 channel:123456789

# 结果
openclaw agent --session-id "xxx" --message "msg" --deliver --reply-to "my-channel"
# --reply-to 格式错误，OpenClaw 无法路由，fallback 到 webchat
```

### 场景 3: 缺少 --reply-channel

```bash
# 即使 OPENCLAW_TARGET 正确
export OPENCLAW_TARGET="channel:123456789"

# 当前命令
openclaw agent --session-id "xxx" --message "msg" --deliver --reply-to "channel:123456789"

# 问题：没有 --reply-channel discord
# OpenClaw 可能使用 session 的原始 channel（如果是 webchat 创建的 session，就回到 webchat）
```

## 改进方案

### 方案 1: 始终添加 --deliver 和 --reply-channel（推荐）

**优点**：
- 明确指定路由，不依赖 session 默认值
- 即使 `OPENCLAW_TARGET` 未设置，也能路由到正确的 channel
- 更可靠，不会 fallback 到 webchat

**实现**：
```bash
openclaw agent \
  --session-id "$session_id" \
  --message "$msg" \
  --deliver \
  --reply-channel "${OPENCLAW_CHANNEL:-discord}" \
  ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"}
```

**变化**：
- `--deliver` 始终添加（不再条件性）
- `--reply-channel` 始终添加，使用 `OPENCLAW_CHANNEL` 或默认 `discord`
- `--reply-to` 仍然条件性添加（如果有 target 就指定，没有就用 channel 默认）

### 方案 2: 验证 OPENCLAW_TARGET 格式

**优点**：
- 在发送前验证 target 格式
- 避免格式错误导致路由失败

**实现**：
```bash
# 在 notify.sh 中添加验证
validate_target() {
  local target="$1"
  # Discord channel: channel:123456789
  # Discord user: user:123456789
  # Telegram: chat:123456789
  if [[ "$target" =~ ^(channel|user|chat):[0-9]+$ ]]; then
    return 0
  else
    log_warn "Invalid OPENCLAW_TARGET format: $target (expected: channel:ID or user:ID)"
    return 1
  fi
}
```

### 方案 3: 从 session 元数据获取路由信息

**优点**：
- 不依赖环境变量
- 使用 session 的实际来源 channel

**实现**：
```bash
# 查询 session 的元数据
SESSION_INFO=$(openclaw sessions --json | jq -r ".[] | select(.id==\"$session_id\")")
CHANNEL=$(echo "$SESSION_INFO" | jq -r '.channel')
TARGET=$(echo "$SESSION_INFO" | jq -r '.target')

# 使用查询到的信息
openclaw agent \
  --session-id "$session_id" \
  --message "$msg" \
  --deliver \
  --reply-channel "$CHANNEL" \
  --reply-to "$TARGET"
```

**缺点**：
- 需要额外的 API 调用
- 性能开销
- 如果 session 不存在会失败

### 方案 4: 混合方案（最可靠）

结合方案 1 和方案 2：

```bash
# 1. 验证 OPENCLAW_TARGET（如果设置了）
if [[ -n "${OPENCLAW_TARGET:-}" ]]; then
  if ! validate_target "$OPENCLAW_TARGET"; then
    log_error "Invalid OPENCLAW_TARGET, cannot route notification"
    _notify_enqueue "$msg" "$event_type"
    return 1
  fi
fi

# 2. 始终添加 --deliver 和 --reply-channel
openclaw agent \
  --session-id "$session_id" \
  --message "$msg" \
  --deliver \
  --reply-channel "${OPENCLAW_CHANNEL:-discord}" \
  ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"}
```

## 诊断步骤

在修改代码前，先诊断当前环境：

### 1. 检查环境变量

```bash
echo "OPENCLAW_CHANNEL=${OPENCLAW_CHANNEL:-<not set>}"
echo "OPENCLAW_TARGET=${OPENCLAW_TARGET:-<not set>}"
echo "OPENCLAW_ACCOUNT=${OPENCLAW_ACCOUNT:-<not set>}"
echo "OPENCLAW_SESSION_ID=${OPENCLAW_SESSION_ID:-<not set>}"
```

### 2. 检查 tmux session 环境

```bash
tmux show-environment -t cc-supervise | grep OPENCLAW
```

### 3. 测试 openclaw agent 命令

```bash
# 测试 1: 不带 --deliver（应该不发送）
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "Test 1: no deliver"

# 测试 2: 带 --deliver 但没有 --reply-to（应该走 session 默认路由）
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "Test 2: deliver no target" --deliver

# 测试 3: 带 --deliver 和 --reply-to（应该走指定路由）
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "Test 3: deliver with target" --deliver --reply-to "$OPENCLAW_TARGET"

# 测试 4: 带 --deliver, --reply-channel 和 --reply-to（最完整）
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "Test 4: full routing" --deliver --reply-channel discord --reply-to "$OPENCLAW_TARGET"
```

### 4. 检查 notification.queue

```bash
cat "$CC_SUPERVISOR_HOME/logs/notification.queue"
# 查看队列中的 channel 和 target 值
```

### 5. 检查 OpenClaw session 信息

```bash
openclaw sessions --json | jq ".[] | select(.id==\"$OPENCLAW_SESSION_ID\")"
# 查看 session 的原始 channel 和 target
```

## 推荐方案

**方案 1（始终添加 --deliver 和 --reply-channel）** 是最可靠的，因为：

1. **明确性**: 不依赖 OpenClaw 的默认行为
2. **简单性**: 不需要额外的验证或查询
3. **向后兼容**: 即使 `OPENCLAW_TARGET` 未设置，也能工作
4. **可预测**: 行为一致，不会因 session 来源不同而变化

**实施步骤**：
1. 先运行诊断步骤，确认问题
2. 修改 `scripts/lib/notify.sh` 的 `_notify_discord` 函数
3. 添加 `--deliver` 和 `--reply-channel` 为必需参数
4. 测试各种场景
5. 更新文档

## 相关文件

- `scripts/lib/notify.sh` - 通知路由实现
- `scripts/supervisor_run.sh` - 环境变量传递
- `docs/openclaw-reference.md` - OpenClaw 路由文档
