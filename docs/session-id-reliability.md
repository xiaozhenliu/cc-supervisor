# Session ID 可靠性改进方案

## 问题描述

原有设计中，`OPENCLAW_SESSION_ID` 的获取是被动的：
- `supervisor_run.sh` 只传递环境变量，不主动获取
- 如果环境变量未设置或丢失，通知会静默失败
- 错误发现太晚（tmux session 已启动后才警告）

## 改进方案

### 1. 前置验证机制

新增 `ensure-session-id.sh` 脚本，在 `supervisor_run.sh` 启动时**立即**执行：

```bash
# 在 supervisor_run.sh 开头（第 17 行之后）
if [ -z "${OPENCLAW_SESSION_ID:-}" ]; then
  # 尝试获取/验证 session ID
  eval "$(bash ensure-session-id.sh)"
fi
```

### 2. 多层获取策略

`ensure-session-id.sh` 按优先级尝试：

1. **检查环境变量**: 如果 `OPENCLAW_SESSION_ID` 已设置且格式正确，直接使用
2. **查询 OpenClaw CLI**: 尝试 `openclaw config get session-id`（如果 OpenClaw 支持）
3. **失败快速退出**: 如果都失败，立即报错并退出，不启动 tmux session

### 3. 优势

- **Fail-fast**: 在启动前就发现问题，避免无效的 tmux session
- **自动化**: 如果 OpenClaw 提供查询接口，可以自动获取
- **清晰错误**: 明确告知用户如何设置 session ID

## 使用方式

### 方式 1: 手动设置（推荐）

```bash
export OPENCLAW_SESSION_ID="your-session-id-here"
./scripts/supervisor_run.sh
```

### 方式 2: 自动获取（如果 OpenClaw 支持）

```bash
# ensure-session-id.sh 会自动从 OpenClaw 获取
./scripts/supervisor_run.sh
```

## 注意事项

1. **OpenClaw API 依赖**: 当前实现假设 `openclaw config get session-id` 可用，需要验证
2. **Agent 上下文**: 在 OpenClaw agent 内运行时，应该自动设置 `OPENCLAW_SESSION_ID`
3. **向后兼容**: 如果环境变量已设置，行为与原来完全一致

## 后续改进

如果 OpenClaw 不提供 `config get session-id`，可以考虑：
- 从 `~/.openclaw/openclaw.json` 读取配置
- 提供交互式提示让用户输入
- 缓存 session ID 到本地文件（需考虑安全性）
