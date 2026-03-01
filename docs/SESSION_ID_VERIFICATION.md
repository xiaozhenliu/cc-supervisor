# Session ID 验证报告

## 验证日期
2026-02-28

## 验证范围
1. Session ID 获取
2. Session ID 检查
3. Session ID 使用
4. 通知发送格式

---

## 1. Session ID 获取（Phase 0）

### 位置
- `SKILL.md` Phase 0 (lines 93-103)
- `scripts/get-session-id.sh`

### 实现逻辑
```bash
eval "$($CC_SUPERVISOR_HOME/scripts/get-session-id.sh)"
```

### get-session-id.sh 行为
1. **检查环境变量**：检查 `$OPENCLAW_SESSION_ID` 是否已设置
2. **验证格式**：使用正则表达式验证 UUID 格式
   - 正则：`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`
   - 要求：小写十六进制，标准 UUID v4 格式
3. **成功**：输出 `export OPENCLAW_SESSION_ID='<uuid>'`
4. **失败情况**：
   - 环境变量未设置 → 退出码 1，错误消息
   - 格式不是 UUID → 退出码 1，错误消息

### ✅ 验证结果：正确
- 只使用环境变量，不调用不可靠的命令
- 严格验证 UUID 格式
- 拒绝路由格式（如 `agent:ruyi:discord:channel:...`）
- 清晰的错误消息

---

## 2. Session ID 检查（Phase 0）

### 位置
- `SKILL.md` Phase 0 (line 100)
- `scripts/verify-session-id.sh`

### 实现逻辑
```bash
$CC_SUPERVISOR_HOME/scripts/verify-session-id.sh "$OPENCLAW_SESSION_ID"
```

### verify-session-id.sh 行为
1. **接收参数**：接收 session ID 作为参数或从环境变量读取
2. **验证格式**：使用相同的 UUID 正则表达式验证
3. **验证一致性**：检查参数与 `$OPENCLAW_SESSION_ID` 是否一致
4. **输出**：
   - ✓ 格式有效
   - ✓ 与环境变量匹配
   - 提示：需要 Phase 3.5 测试消息验证端到端路由

### ✅ 验证结果：正确
- 双重验证格式
- 确保一致性
- 清晰的成功/失败消息
- 提醒需要端到端测试

---

## 3. Session ID 使用（Hook 回调）

### 位置
- `scripts/on-cc-event.sh` (lines 164-180)

### 实现逻辑
```bash
openclaw agent \
  --session-id "$OPENCLAW_SESSION_ID" \
  --message "$NOTIFY_MSG" \
  ${OPENCLAW_TARGET:+--deliver} \
  ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"} \
  2>/dev/null
```

### 使用方式
1. **检查环境变量**：先检查 `$OPENCLAW_SESSION_ID` 是否设置
2. **调用 openclaw agent**：使用 `--session-id` 参数传递 UUID
3. **可选参数**：
   - `--deliver`：如果 `OPENCLAW_TARGET` 设置则添加
   - `--reply-to "$OPENCLAW_TARGET"`：指定回复目标
4. **失败处理**：如果发送失败，将消息加入队列

### ✅ 验证结果：正确
- 使用 `--session-id` 参数（正确）
- 传递 UUID 格式的 session ID（正确）
- 有失败回退机制（队列）
- 日志记录清晰

---

## 4. 通知发送格式

### 位置
- `scripts/on-cc-event.sh` (lines 155-162)

### 消息格式

#### Stop 事件（auto 模式）
```
[cc-supervisor][auto] Stop: <summary>
```

#### Stop 事件（relay 模式）
```
[cc-supervisor][relay] Stop:
<summary>
```

#### 其他事件
```
[cc-supervisor][<mode>] <event_type>: <summary>
```

### ✅ 验证结果：正确
- 格式清晰，易于解析
- 包含模式标识（auto/relay）
- 包含事件类型
- 包含摘要信息

---

## 5. SKILL.md 文档验证

### Phase 0 文档（lines 94-107）

#### 说明内容
```bash
# CRITICAL: Verify OPENCLAW_SESSION_ID is set and has correct UUID format
# Session ID MUST be UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# NOT routing format like: agent:ruyi:discord:channel:1466784529527214122
# The routing format is a session key, not a session ID
```

### ✅ 验证结果：正确且无歧义
- 明确说明必须是 UUID 格式
- 明确说明路由格式是 session key，不是 session ID
- 提供了格式示例
- 说明了失败情况的处理

---

## 6. 端到端流程验证

### 完整流程
1. **Phase 0**：OpenClaw agent 设置 `$OPENCLAW_SESSION_ID`（UUID 格式）
2. **Phase 0**：`get-session-id.sh` 验证并导出环境变量
3. **Phase 0**：`verify-session-id.sh` 二次验证格式和一致性
4. **Phase 3**：启动 Claude Code，环境变量传递给子进程
5. **Phase 3.5**：发送测试消息，验证 Hook 通知能否返回
6. **Hook 回调**：`on-cc-event.sh` 使用 `$OPENCLAW_SESSION_ID` 调用 `openclaw agent --session-id`
7. **通知接收**：OpenClaw agent 接收到 `[cc-supervisor]` 消息

### ✅ 验证结果：流程完整且正确

---

## 7. 潜在问题和建议

### ⚠️ 发现的问题

#### 问题 1：环境变量传递
**位置**：Phase 3 启动 Claude Code

**当前实现**：
```bash
OPENCLAW_SESSION_ID=$OPENCLAW_SESSION_ID cc-supervise <project-dir>
```

**问题**：这种写法只在当前命令的环境中设置变量，不会传递给 Hook 回调。

**原因**：Hook 回调是由 Claude Code 进程启动的子进程，需要确保环境变量被正确继承。

**建议**：在 `supervisor_run.sh` 中确保 `OPENCLAW_SESSION_ID` 被 export，或者在 SKILL.md 中明确说明需要先 export。

#### 问题 2：Phase 3.5 验证超时
**位置**：Phase 3.5 Hook 通知验证

**当前实现**：等待 30 秒超时

**问题**：如果 Hook 通知失败，agent 需要等待 30 秒才能发现问题。

**建议**：考虑添加更短的初步检查（如 5 秒），如果没有收到通知，立即检查日志和队列。

---

## 8. 总体评估

### ✅ 正确的方面
1. Session ID 格式验证严格（UUID only）
2. 拒绝路由格式的 session key
3. 双重验证机制（get + verify）
4. 清晰的错误消息
5. 使用正确的 `openclaw agent --session-id` 参数
6. 通知格式清晰且易于解析
7. 有失败回退机制（队列）

### ⚠️ 需要改进的方面
1. 环境变量传递机制需要明确
2. Phase 3.5 超时可以优化

### 📊 总体评分
**9/10** - 实现基本正确且无歧义，有小的改进空间

---

## 9. 建议的改进

### 改进 1：明确环境变量传递
在 SKILL.md Phase 3 中添加说明：

```bash
# Ensure OPENCLAW_SESSION_ID is exported before starting
export OPENCLAW_SESSION_ID

OPENCLAW_SESSION_ID=$OPENCLAW_SESSION_ID cc-supervise <project-dir>
```

### 改进 2：优化 Phase 3.5 验证
添加快速失败检查：

```bash
# Wait 5 seconds for initial response
sleep 5

# Quick check: did Hook fire?
if ! tail -1 logs/events.ndjson | grep -q "Stop"; then
  echo "⚠️ No Hook event detected after 5 seconds"
  echo "Checking diagnostics..."
  # Run diagnostics
fi

# Continue waiting up to 30 seconds total
```

---

## 10. 结论

当前的 skill 对于 session ID 的获取、检查、使用和通知发送格式**基本正确且无重大歧义**。

主要优点：
- 严格的 UUID 格式验证
- 清晰的文档说明
- 正确的 API 使用

需要注意的点：
- 确保环境变量正确传递给 Hook 回调
- 可以优化验证超时机制

总体而言，实现质量高，可以投入使用。
