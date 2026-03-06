# cc-supervisor

[![version](https://img.shields.io/badge/version-1.0.3-blue)](CHANGELOG.md)

**让 OpenClaw Agent 通过 Hooks 事件驱动监督任意本地项目中的 Claude Code**

cc-supervisor 是一个 **ClawHub Skill**，一行命令安装，之后即可用 `@cc-supervisor` 技能驱动 Claude Code 完成多轮任务——等待期间 token 消耗为零。

---

## Quick Start

```bash
# ── 步骤一：一键安装（本机只需一次）──────────────────────────
curl -fsSL https://raw.githubusercontent.com/OWNER/cc-supervisor/main/install.sh | bash

# 安装完成后重新加载 shell
source ~/.zshrc

# ── 步骤二：为目标项目注册 Hooks（每个项目只需一次）──────
cc-install-hooks ~/Projects/my-app

# ── 步骤三：启动监督 ──────────────────────────────────────
cc-supervise ~/Projects/my-app

# 然后发送任务
cc-send "实现登录 API"
```

> 在 OpenClaw 中直接使用 `@cc-supervisor` 技能可驱动完整监督流程。

---

## 架构

```
OpenClaw ── cc_send.sh (tmux send-keys) ──→ Claude Code（tmux 内，交互模式）
    ↑                                               │
    │                                          Hook 触发
    │                              (Stop / PostToolUse / Notification / SessionEnd)
    │                                               │
    └───── openclaw agent        ←──── on-cc-event.sh ←────┘
                                     │
                            logs/events.ndjson（追加写入）

人类 ── tmux attach -t cc-supervise ──→ 随时观察 / 手动介入
```

核心优势：等待期间 OpenClaw **token 消耗 = 0**（不轮询，事件驱动）。

### 监督模式

cc-supervisor 支持两种监督模式：

| 模式 | 控制者 | 适用场景 | 人类消息处理 |
|------|--------|---------|-------------|
| **relay** | 人类 | 敏感任务、完全控制 | 只有 `cc` 开头才转发给 Claude |
| **auto** | OpenClaw | 长任务、少打扰监督 | `cc` 转发任务；`y/n/1/2` 可直接作为按键回复 |

**relay 模式**：每次 Claude Code 停下来，OpenClaw 都会通知人类，等待人类决定下一步。

**auto 模式**：OpenClaw 只自动处理低风险确认和推荐选项；遇到需要判断、真实环境验证、凭据或完成态不明确时升级给人类。

**重要**：无论 `relay` 还是 `auto` 模式，只有以 `cc` 开头的消息才会转发给 Claude Code；其他消息默认都给 OpenClaw 自己，用于调整监督策略或执行显式 `cmd...` 命令。

支持的转发写法：

```text
cc 修复登录超时
cc: 修复登录超时
cc：修复登录超时
cc
修复登录超时
```

常见 supervisor 命令：

```text
cmd继续
cmd停止
cmd检查
cmd退出
```

也支持直接按键回复：

```text
y
n
1
2
Enter
```

Hook 通知会重复提示这套回复约定，避免在 Discord 或手机上回到自然语言猜测。

详见 [docs/DESIGN_DECISIONS.md](docs/DESIGN_DECISIONS.md)

---

### 两种使用方式

| 方式 | 启动者 | 通知配置 |
|------|--------|---------|
| **Agent 自动** | OpenClaw Agent | 自动注入 `OPENCLAW_CHANNEL` / `OPENCLAW_TARGET` |
| **人类手动** | 人类在终端 | `export OPENCLAW_CHANNEL=discord OPENCLAW_TARGET=<id>` |

---

## 前置条件

| 工具 | 安装 |
|------|------|
| `tmux` | `brew install tmux` |
| `jq` | `brew install jq` |
| `claude` | Anthropic 文档 |
| `openclaw` | OpenClaw 文档 |

---

## 一次性安装

### 安装 Skill

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/cc-supervisor/main/install.sh | bash
```

或者预览安装步骤（不做任何修改）：

```bash
bash install.sh --dry-run
```

安装后 skill 位于 `~/.openclaw/skills/cc-supervisor/`，shell 别名自动注入到 `~/.zshrc` 或 `~/.bashrc`。

安装相关文档见 [docs/README.md](docs/README.md) 和 [install.sh](install.sh)。

---

## 在项目中注册 Hooks

每个需要监督的项目执行一次：

```bash
cc-install-hooks ~/Projects/my-app
```

验证：

```bash
cat ~/Projects/my-app/.claude/settings.local.json | jq .hooks
```

> Hooks 写入目标项目的 `.claude/settings.local.json`（项目本地、全局 gitignore，
> 不提交、不影响其他开发者）。

---

## 使用方式

### 方式 A — 通过 OpenClaw 技能（推荐）

安装 skill 后，OpenClaw 可全自动驱动：

```
@cc-supervisor 监督 ~/Projects/my-app：任务是"实现登录 API"
```

OpenClaw 会自动完成：启动会话 → 发送指令 → 等待 Hook 通知 → 多轮驱动到完成。

### 方式 B — 手动控制

**第一步：启动监督会话**

```bash
cc-supervise ~/Projects/my-app
```

创建（或复用）tmux 会话 `cc-supervise`，在 `~/Projects/my-app` 中启动 Claude Code，
并在后台启动 watchdog（默认超时 30 分钟）。

**第二步：发送任务指令**

```bash
cc-send "实现登录 API"
```

**第三步：等待 Hook 通知**

Claude Code 完成一轮响应后，Hook 触发 `on-cc-event.sh`，调用 `openclaw agent --session-id ... --deliver` 通知。
收到通知后：

- **任务未完成** → 发送下一轮指令
- **任务已完成** → 结束循环
- **出现错误** → 分析后发送修正指令

**随时观察 / 介入**

```bash
tmux attach -t cc-supervise
# 退出观察但不关闭会话：Ctrl-B, D
```

---

## Hook 事件说明

| 事件 | 含义 | 通知策略 |
|------|------|----------|
| `Stop` | Claude Code 完成当前轮响应 | **通知** OpenClaw，附带输出摘要 |
| `PostToolUse` | 工具调用完成 | 仅写日志；**工具报错时通知** |
| `Notification` | Claude Code 发出等待通知 | **通知** OpenClaw |
| `SessionEnd` | 会话结束 | **通知** OpenClaw |

超时告警（watchdog）：超过 `CC_TIMEOUT`（默认 1800 秒）无新事件，
watchdog 通过 `openclaw agent --session-id ... --deliver` 发送 `⏰ watchdog: no activity...` 告警。

---

## 常用命令

```bash
# 快照最近 50 行输出（诊断用）
cc-capture --tail 50

# 查看事件日志
cat "$CC_SUPERVISOR_HOME/logs/events.ndjson" | jq .

# 实时追踪运行日志
tail -f "$CC_SUPERVISOR_HOME/logs/supervisor.log" | jq .

# 测试超时（将阈值改为 1 分钟）
CC_TIMEOUT=60 cc-supervise ~/Projects/my-app

# 运行完整 Demo（无需真实 Claude Code）
"$CC_SUPERVISOR_HOME/scripts/demo.sh"
```

---

## 测试

当前稳定回归入口：

```bash
"$CC_SUPERVISOR_HOME/scripts/test-regression.sh"
```

仓库内直接运行：

```bash
bash scripts/test-regression.sh
```

该入口会顺序执行当前稳定、无需额外人工参数的测试，包括：

- 脚本逻辑测试（命令解析、回复执行、hook.env 生命周期、通知模板）
- 安装产物测试与安装失败测试
- 通知队列 fallback 测试
- 真实 `claude + tmux + hook` 的 `Notification` / `Stop` / `SessionEnd` 集成测试

当前 `Notification` 集成测试使用项目级权限规则强制触发：目标项目的 `.claude/settings.local.json` 会临时设置 `permissions.ask: ["Bash"]`，然后让 Claude 请求执行 `Bash`，从而稳定触发 `Notification` Hook。

参考：

- [docs/real-claude-hook-test-plan.md](docs/real-claude-hook-test-plan.md)
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

---

## 目录结构

```
~/.openclaw/skills/cc-supervisor/   （skill 安装根目录）
├── SKILL.md                # ClawHub skill 定义（frontmatter + 操作指南）
├── scripts/
│   ├── supervisor_run.sh   # 创建/复用 tmux 会话，启动 Claude Code 和 watchdog
│   ├── cc_send.sh          # 向 Claude Code 发送文本指令或特殊按键（--key 模式）
│   ├── cc_capture.sh       # 快照 tmux pane 最近输出
│   ├── on-cc-event.sh      # 统一 Hook 回调：写日志 + 通知 OpenClaw
│   ├── install-hooks.sh    # 合并 Hook 配置到目标项目的 .claude/settings.local.json
│   ├── cc-watchdog.sh      # 超时监控守护进程
│   ├── flush-queue.sh      # 重试积压通知队列
│   ├── demo.sh             # 完整多轮监督演示脚本
│   └── lib/log.sh          # 结构化日志工具函数
├── config/
│   └── claude-hooks.json   # Hook 注册模板（含占位符）
└── logs/                   # 运行时数据（gitignored）
    ├── events.ndjson       # Hook 事件追加日志
    ├── supervisor.log      # 脚本运行日志（结构化 JSON）
    ├── notification.queue  # 发送失败的通知队列（可选）
    └── watchdog.pid        # watchdog 进程 PID
```

---

## 故障排查

**没有收到通知：**
1. 确认环境变量已设置：`echo $OPENCLAW_CHANNEL $OPENCLAW_TARGET`
2. 检查队列：`cat "$CC_SUPERVISOR_HOME/logs/notification.queue"`
3. 手动重试：`cc-flush-queue`
4. 检查事件日志：`cat "$CC_SUPERVISOR_HOME/logs/events.ndjson" | jq .`
5. 检查脚本日志：`cat "$CC_SUPERVISOR_HOME/logs/supervisor.log" | jq .`

**会话已存在：**
`cc-supervise` 会直接复用已有会话（幂等）。若需强制重建：
```bash
tmux kill-session -t cc-supervise && cc-supervise ~/Projects/my-app
```

**`openclaw` 不在 PATH：**
通知会写入 `logs/notification.queue`，等 `openclaw` 可用后执行 `cc-flush-queue` 重试。

---

## 卸载

**移除某个项目的 Hooks：**

```bash
jq 'del(.hooks)' ~/Projects/my-app/.claude/settings.local.json \
  > /tmp/settings.tmp && mv /tmp/settings.tmp \
  ~/Projects/my-app/.claude/settings.local.json
```

**卸载 skill：**

```bash
rm -rf ~/.openclaw/skills/cc-supervisor
# ClawHub 上架后也可用：clawhub uninstall cc-supervisor
```

---

## 文档

| 文件 | 说明 |
|------|------|
| [README_en.md](README_en.md) | English README |
| [SKILL.md](SKILL.md) | ClawHub skill 定义（英文） |
| [docs/README.md](docs/README.md) | docs 目录与安装包含关系说明 |
| [docs/openclaw-reference.md](docs/openclaw-reference.md) | OpenClaw CLI 与路由参数参考 |
| [docs/real-claude-hook-test-plan.md](docs/real-claude-hook-test-plan.md) | 真实 Claude Hook 测试计划与当前状态 |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | 常见故障排查 |
| [docs/DESIGN_DECISIONS.md](docs/DESIGN_DECISIONS.md) | 监督模式与状态机设计决策 |
| [CHANGELOG.md](CHANGELOG.md) | 版本历史 |
