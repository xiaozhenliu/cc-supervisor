# SKILL.md 更新说明

## 更新原因

根据 session ID 可靠性改进，SKILL.md 需要更新以反映新的验证机制和时机。

## 更新内容

### 1. Phase 1 — Start (automated) 部分

**更新位置**: 第 121-137 行

**主要变化**:
- 添加了 "Session ID validation" 说明段落
- 明确指出验证发生在两个地方：
  1. `cc-start` 开始时（fail-fast）
  2. `supervisor_run.sh` 启动 tmux 时（double-check）
- 强调错误现在**立即**出现（启动前），而不是启动后
- 添加了手动测试的命令示例

**新增内容**:
```markdown
**Session ID validation:** `cc-start` uses `ensure-session-id.sh` to validate `OPENCLAW_SESSION_ID` **before** starting the tmux session. This ensures notifications will work from the start. The validation happens in two places:
1. At the beginning of `cc-start` (fail-fast if missing)
2. When `supervisor_run.sh` starts the tmux session (double-check)
```

### 2. Notification Routing 部分

**更新位置**: 第 367-373 行

**主要变化**:
- 添加了 session ID 验证机制的说明
- 更新了 fallback 行为：从 "skip" 改为 "fail-fast"
- 强调现在会在启动前就验证，而不是静默失败

**新增内容**:
```markdown
**Session ID validation:** The system now validates `OPENCLAW_SESSION_ID` **before** starting the tmux session (via `ensure-session-id.sh`). This ensures notifications will work from the start, rather than failing silently later.

Fallback: Session ID not set → fail-fast (no tmux session created) | ...
```

### 3. Troubleshooting 部分

**更新位置**: 第 377-388 行

**主要变化**:
- 扩展了 "No notifications" 故障排查步骤
- 新增了 "Session ID validation fails" 专门章节
- 添加了验证脚本的使用方法
- 提供了更详细的错误处理指导

**新增内容**:
```markdown
**No notifications:**
- Check session ID: `echo $OPENCLAW_SESSION_ID`
- Check queue: `cat "$CC_SUPERVISOR_HOME/logs/notification.queue"`
- Flush queue: `cc-flush-queue`
- Verify session ID format: `bash "$CC_SUPERVISOR_HOME/scripts/ensure-session-id.sh"`

**Session ID validation fails:**
- `ERROR: OPENCLAW_SESSION_ID not set` → Must be set by OpenClaw agent environment
- For manual testing: `export OPENCLAW_SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')`
- Verify format: lowercase UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
```

## 关键改进点

### 1. 验证时机更明确

**之前**: 只说 "handles session ID validation"，没有说明何时验证
**现在**: 明确说明在 Phase 1 的两个地方验证，且是**启动前**验证

### 2. 错误行为更清晰

**之前**: "Session ID not set → skip"（静默失败）
**现在**: "Session ID not set → fail-fast (no tmux session created)"（立即报错）

### 3. 故障排查更完善

**之前**: 只有简单的命令列表
**现在**: 分类的故障排查步骤，包括验证脚本的使用

## 对 Agent 的影响

使用这个 skill 的 agent 现在会：

1. **更早发现问题**: 在 Phase 1 开始时就知道 session ID 是否可用
2. **更清晰的错误**: 知道错误是"立即"出现的，不是启动后才发现
3. **更好的故障排查**: 有专门的验证脚本可以使用
4. **更可靠的通知**: 确保 tmux session 启动时通知一定能工作

## 测试建议

Agent 应该测试以下场景：

1. **正常场景**: `OPENCLAW_SESSION_ID` 已设置且格式正确
2. **缺失场景**: `OPENCLAW_SESSION_ID` 未设置，应该立即报错
3. **格式错误**: `OPENCLAW_SESSION_ID` 格式不正确，应该立即报错
4. **故障排查**: 使用 `ensure-session-id.sh` 验证 session ID

## 相关文件

- `SKILL.md` - 已更新（3 个部分）
- `scripts/ensure-session-id.sh` - 新增的验证脚本
- `scripts/cc-start.sh` - 已集成验证
- `scripts/supervisor_run.sh` - 已集成验证
- `docs/session-id-improvement-summary.md` - 改进总结
