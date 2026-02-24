# cc-supervisor 端到端测试

验证 cc-supervisor 完整监督流程的测试步骤。测试分两种模式，分别对应 SKILL.md 中的 relay 和 autonomous 工作流。

---

## 前置条件

```bash
ls ~/.openclaw/skills/cc-supervisor/scripts/supervisor_run.sh
command -v tmux && command -v jq && command -v claude && echo "依赖检查通过"
```

---

## 准备测试目录

**Agent 执行：**

```bash
TEST_DIR=~/Projects/example-project
mkdir -p "$TEST_DIR"
cp -r ~/.openclaw/skills/cc-supervisor/example-project/. "$TEST_DIR/"
echo "测试目录：$TEST_DIR"
```

注册 Hooks：

```bash
CC_PROJECT_DIR=~/.openclaw/skills/cc-supervisor \
CLAUDE_WORKDIR="$TEST_DIR" \
  ~/.openclaw/skills/cc-supervisor/scripts/install-hooks.sh

# 验证
cat "$TEST_DIR/.claude/settings.local.json" | jq '.hooks | keys'
# 预期：["Notification", "PostToolUse", "SessionEnd", "Stop"]
```

---

## 测试 A — relay 模式

验证每轮 Stop 事件都触发通知，人类可逐步控制执行方向。

**Agent 执行：**

```bash
CC_PROJECT_DIR=~/.openclaw/skills/cc-supervisor \
CLAUDE_WORKDIR="$TEST_DIR" \
CC_MODE=relay \
  ~/.openclaw/skills/cc-supervisor/scripts/supervisor_run.sh
```

**⚠ 人类操作（如出现目录信任提示）：**
> Agent 通知人类："Claude Code 正在请求信任目录，请执行 `tmux attach -t cc-supervise`，输入 `y` 确认，然后 Ctrl-B D 退出。"

**Agent 执行：**

```bash
~/.openclaw/skills/cc-supervisor/scripts/cc_send.sh \
  "制作一个网页向中学生展示量子计算机的工作原理，要求具备充分的文档和测试，并具有一定的可交互性"
```

**验证要点：**
- 每轮 Stop 事件必须触发通知（不能静默跳过）
- 通知摘要非空，包含 Claude Code 本轮实际输出
- Agent 收到通知后转达人类，等待人类指令后才发送下一轮 `cc-send`
- Agent 不得自行决策继续

---

## 测试 B — autonomous 模式

验证 OpenClaw 能自主驱动 Claude Code 完成任务，仅在需要判断时通知人类。

**Agent 执行：**

```bash
CC_PROJECT_DIR=~/.openclaw/skills/cc-supervisor \
CLAUDE_WORKDIR="$TEST_DIR" \
CC_MODE=autonomous \
  ~/.openclaw/skills/cc-supervisor/scripts/supervisor_run.sh
```

**⚠ 人类操作（如出现目录信任提示）：** 同测试 A。

**Agent 执行：**

```bash
~/.openclaw/skills/cc-supervisor/scripts/cc_send.sh \
  "制作一个网页向中学生展示量子计算机的工作原理，要求具备充分的文档和测试，并具有一定的可交互性"
```

**验证要点：**
- Stop 通知包含 `ACTION_REQUIRED: decide_and_continue` 标记
- Agent 按 SKILL.md 中的决策逻辑自主发送后续指令
- 仅在错误重复出现、需要人类判断、或超过 10 轮时通知人类
- 任务完成后 Agent 主动通知人类并报告结果

---

## 产物验证

两种模式共用：

```bash
[ -f "$TEST_DIR/index.html" ] && echo "✓ index.html" || echo "✗ 缺失"
([ -f "$TEST_DIR/README.md" ] || [ -d "$TEST_DIR/docs" ]) && echo "✓ 文档" || echo "✗ 缺失"
find "$TEST_DIR" \( -name "*.test.*" -o -name "*.spec.*" -o -name "test_*" \) \
  | grep -q . && echo "✓ 测试文件" || echo "✗ 缺失"

tail -5 ~/.openclaw/skills/cc-supervisor/logs/events.ndjson \
  | jq -r '"[\(.ts)] \(.event_type): \(.summary | .[0:80])"'
```

| 检查项 | 要求 |
|--------|------|
| `index.html` 或等效入口 | 必须存在 |
| 文档文件 | 必须存在 |
| 测试文件 | 必须存在 |
| events.ndjson 有 Stop 记录 | 至少 2 条 |

---

## 清理

```bash
tmux kill-session -t cc-supervise 2>/dev/null || true
rm -rf "$TEST_DIR"
```
