# cc-supervisor 端到端测试指南

本文档供 **OpenClaw Agent** 阅读执行，验证 cc-supervisor 的完整监督流程。

提供两种测试模式：
- **模式 A（自动模式）**：OpenClaw 自主驱动 Claude Code 完成任务，无需人类介入
- **模式 B（手动模式）**：每轮由人类决策下一步，OpenClaw 仅负责转发通知

---

## 前置检查

```bash
# cc-supervisor 已安装
ls ~/.openclaw/skills/cc-supervisor/scripts/supervisor_run.sh

# 依赖工具可用
command -v tmux && command -v jq && command -v claude && echo "依赖检查通过"

# 通知路由变量（OpenClaw 自动注入；手动测试时需 export）
echo "OPENCLAW_CHANNEL=${OPENCLAW_CHANNEL:-未设置}"
echo "OPENCLAW_TARGET=${OPENCLAW_TARGET:-未设置}"
```

任何检查失败则停止，报告给人类。

---

## Step 1 — 复制测试项目到临时目录

**不要在 cc-supervisor 仓库内直接运行**，需复制到独立目录模拟真实项目。

```bash
TEST_DIR="/tmp/cc-e2e-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEST_DIR"
cp -r ~/.openclaw/skills/cc-supervisor/example-project/. "$TEST_DIR/"
echo "测试目录：$TEST_DIR"
```

**成功条件**：`$TEST_DIR` 存在且包含 `E2E_TEST.md`。

---

## Step 2 — 注册 Hooks

```bash
CC_PROJECT_DIR=~/.openclaw/skills/cc-supervisor \
CLAUDE_WORKDIR="$TEST_DIR" \
  ~/.openclaw/skills/cc-supervisor/scripts/install-hooks.sh
```

**验证**：

```bash
cat "$TEST_DIR/.claude/settings.local.json" | jq '.hooks | keys'
# 预期：["Notification", "PostToolUse", "SessionEnd", "Stop"]
```

**成功条件**：4 个 Hook 类型全部出现。

---

## 模式 A — 自动模式测试（OpenClaw 自主驱动）

适用场景：验证 OpenClaw 能否在无人介入的情况下，驱动 Claude Code 完成完整任务。

### A-1 启动会话

```bash
CC_PROJECT_DIR=~/.openclaw/skills/cc-supervisor \
CLAUDE_WORKDIR="$TEST_DIR" \
CC_MODE=autonomous \
OPENCLAW_CHANNEL="${OPENCLAW_CHANNEL}" \
OPENCLAW_TARGET="${OPENCLAW_TARGET}" \
  ~/.openclaw/skills/cc-supervisor/scripts/supervisor_run.sh
```

> 若 Claude Code 弹出目录信任确认，在终端输入 `y` 确认。

**验证**：

```bash
tmux has-session -t cc-supervise && echo "会话已建立"
```

### A-2 发送初始任务

```bash
~/.openclaw/skills/cc-supervisor/scripts/cc_send.sh \
  "制作一个网页向中学生展示量子计算机的工作原理，要求具备充分的文档和测试，并具有一定的可交互性"
```

### A-3 自主驱动循环

等待 `openclaw message send` 通知到达，**不要轮询**。

每次收到 `[cc-supervisor][autonomous] Stop:` 通知，按以下逻辑决策：

```
读取通知中的 <summary>

if summary 表明任务未完成（还在规划 / 文件未创建 / 提到"继续"）:
    ~/.openclaw/skills/cc-supervisor/scripts/cc_send.sh "请继续，完成所有文件的创建"

elif summary 表明遇到错误:
    ~/.openclaw/skills/cc-supervisor/scripts/cc_send.sh "遇到错误，请修复后继续：<错误描述>"

elif summary 表明任务已完成（文件已创建 / 测试通过 / 提到完成）:
    停止循环，进入 Step 3 验证产物
```

收到 `PostToolUse: Tool error` 通知时：

```bash
~/.openclaw/skills/cc-supervisor/scripts/cc_send.sh "工具调用出错，请检查并修复后继续"
```

收到 `⏰ watchdog` 超时通知时：

```bash
~/.openclaw/skills/cc-supervisor/scripts/cc_capture.sh --tail 60
# 根据输出判断：仍在运行则等待；卡住则发送 "请继续"；无响应则报告人类
```

**循环终止条件**（满足任一即停止）：

- Stop 通知摘要包含"完成"、"已创建"、"done"、"finished"
- `$TEST_DIR/index.html` 文件存在
- 已发送超过 **10 轮**指令（防止无限循环，此时报告人类）

---

## 模式 B — 手动模式测试（人类决策，OpenClaw 转发）

适用场景：验证 relay 模式下，每轮 Stop 事件都能正确通知，人类可逐步控制执行方向。

### B-1 启动会话

```bash
CC_PROJECT_DIR=~/.openclaw/skills/cc-supervisor \
CLAUDE_WORKDIR="$TEST_DIR" \
CC_MODE=relay \
OPENCLAW_CHANNEL="${OPENCLAW_CHANNEL}" \
OPENCLAW_TARGET="${OPENCLAW_TARGET}" \
  ~/.openclaw/skills/cc-supervisor/scripts/supervisor_run.sh
```

**验证**：

```bash
tmux has-session -t cc-supervise && echo "会话已建立"
```

### B-2 发送初始任务

```bash
~/.openclaw/skills/cc-supervisor/scripts/cc_send.sh \
  "制作一个网页向中学生展示量子计算机的工作原理，要求具备充分的文档和测试，并具有一定的可交互性"
```

### B-3 转发循环

每次收到 `[cc-supervisor][relay] Stop:` 通知：

1. 将通知摘要转达给人类
2. 等待人类指令
3. 将人类指令发送给 Claude Code：

```bash
~/.openclaw/skills/cc-supervisor/scripts/cc_send.sh "<人类指令>"
```

**relay 模式验证要点**：

- 每轮 Stop 事件都应触发通知（不能静默跳过）
- 通知摘要应包含 Claude Code 本轮的实际输出内容（非空）
- OpenClaw 不应自行决策继续，必须等待人类指令

**循环终止条件**：人类明确表示任务完成，或 `$TEST_DIR/index.html` 存在。

---

## Step 3 — 验证产物

两种模式共用同一验证步骤。

```bash
echo "=== 目录内容 ==="
ls -la "$TEST_DIR"

echo "=== 必要文件检查 ==="
[ -f "$TEST_DIR/index.html" ] \
  && echo "✓ index.html" || echo "✗ index.html 缺失"

([ -f "$TEST_DIR/README.md" ] || [ -d "$TEST_DIR/docs" ]) \
  && echo "✓ 文档存在" || echo "✗ 文档缺失"

find "$TEST_DIR" \( -name "*.test.*" -o -name "test_*" -o -name "*_test.*" -o -name "*.spec.*" \) \
  | grep -q . && echo "✓ 测试文件存在" || echo "✗ 测试文件缺失"

echo "=== 事件日志（最近 10 条）==="
tail -10 ~/.openclaw/skills/cc-supervisor/logs/events.ndjson \
  | jq -r '"[\(.ts)] \(.event_type): \(.summary | .[0:100])"'
```

**通过标准**：

| 检查项 | 要求 |
|--------|------|
| `index.html` 或等效入口 | 必须存在 |
| 文档文件 | 必须存在 |
| 测试文件 | 必须存在 |
| `events.ndjson` 有 Stop 记录 | 至少 2 条 |

---

## Step 4 — 清理

```bash
tmux kill-session -t cc-supervise 2>/dev/null || true
rm -rf "$TEST_DIR"
echo "清理完成"
```

---

## 测试结果上报

测试完成后，向人类报告：

```
cc-supervisor 端到端测试结果
==============================
测试模式：自动（autonomous）/ 手动（relay）
测试目录：$TEST_DIR
总轮次：<N> 轮
产物验证：
  - index.html：✓/✗
  - 文档：✓/✗
  - 测试文件：✓/✗
事件日志 Stop 条数：<N>
结论：PASS / FAIL
失败原因（如有）：<描述>
```
