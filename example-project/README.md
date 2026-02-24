# example-project

本目录是 **cc-supervisor 端到端验证项目**。

用于验证以下完整监督流程：启动会话 → 发送任务 → Hook 事件触发 → 模式切换 → 任务完成通知。

---

## 标准任务提示词

```
制作一个网页向中学生展示量子计算机的工作原理，要求具备充分的文档和测试，并具有一定的可交互性
```

---

## 验证步骤

```bash
# 1. 以本目录作为工作目录启动监督会话
CLAUDE_WORKDIR="$(pwd)" ~/.openclaw/skills/cc-supervisor/scripts/supervisor_run.sh

# 2. 发送标准任务提示词
~/.openclaw/skills/cc-supervisor/scripts/cc_send.sh \
  "制作一个网页向中学生展示量子计算机的工作原理，要求具备充分的文档和测试，并具有一定的可交互性"

# 3. 观察 Hook 事件流
tail -f ~/.openclaw/skills/cc-supervisor/logs/events.ndjson

# 4. （可选）人类观察终端
tmux attach -t cc-supervise
```

---

## 预期产物

Claude Code 执行完成后，本目录应包含：

| 文件/目录 | 说明 |
|-----------|------|
| `index.html` 或同等入口 | 可在浏览器直接打开的量子计算机科普网页 |
| 文档文件（README 或 docs/） | 介绍页面结构、使用方式、内容来源 |
| 测试文件 | 对页面逻辑或交互组件的测试 |

---

## 监督模式对比

| 命令 | 模式 | 行为 |
|------|------|------|
| `CC_MODE=relay supervisor_run.sh` | 转发模式（默认） | 每次 Stop 事件通知 OpenClaw，等待人类下一步指令 |
| `CC_MODE=autonomous supervisor_run.sh` | 自主模式 | OpenClaw 持续推进，完成后通知人类 |

---

> 本目录由 cc-supervisor 管理，Claude Code 的输出产物均落于此处。
> `.gitignore` 已排除 Claude Code 生成的构建产物，仅保留任务定义文件。
