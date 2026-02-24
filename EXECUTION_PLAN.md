# Execution Plan: Code Supervisor（OpenClaw Agent 视角）

> 本文档仅描述实施步骤；产品目标看 `PRD.md`。

## 0. 目标

打造一个以 **ClawHub Skill** 形式分发的 OpenClaw Agent 多轮监督 Claude Code 工具：

- 用户通过 `clawhub install cc-supervisor` 一键安装到 `~/.openclaw/skills/cc-supervisor/`
- 安装后无需额外配置，可在任意本地项目中使用
- 用 Hooks 事件驱动代替轮询，等待期 token 消耗为 0

---

## 1. 现状替代映射

| 当前方式（As-Is） | 问题 | 目标替代（To-Be） |
|---|---|---|
| 人工盯终端等 Claude Code 跑完 | 消耗注意力 | OpenClaw 通过 Hook 通知自动感知状态 |
| 人工手动追问 | 依赖人盯屏 | OpenClaw 通过 `cc_send.sh` 发后续 prompt |
| `tmux capture-pane` 轮询 | 高 token 消耗 | Hooks 事件驱动，等待期 token = 0 |
| 不知道卡没卡住 | 状态不透明 | watchdog 超时主动告警 |
| 需手动配置工具路径 | 安装繁琐 | ClawHub 一键安装，路径固定 |
| 首次进入新目录卡在信任提示 | 脚本无法自动处理，会话卡住 | 操作者在脚本终端明确确认，脚本转发或报警 |
| Hook 事件信息不完整 | OpenClaw 缺乏上下文，无法有效决策 | 每类事件携带摘要/工具名/错误详情 |
| 无法区分"人类主导"与"委托自主"两种监督意图 | 工具角色模糊，行为不可预期 | `CC_MODE` 配置切换转发模式与自主模式 |

---

## 2. 架构

```
OpenClaw ── cc_send.sh (tmux send-keys) ──→ Claude Code（交互模式，tmux 内）
    ↑                                             │
    │                                        Hook 触发
    │                                        (Stop / PostToolUse / Notification / SessionEnd)
    │                                             │
    └───── openclaw send ←──── on-cc-event.sh ←───┘
                                    │
                               logs/events.ndjson（追加写入）

人类 ── tmux attach -t cc-supervise ──→ 随时观察/介入
```

核心组件：
1. **tmux 会话**：Claude Code 运行环境，人类可观察窗口
2. **Hooks → on-cc-event.sh**：事件驱动通知，替代轮询
3. **cc_send.sh**：OpenClaw 向 Claude Code 发送后续指令的通道
4. **openclaw send**：Hook 回调通知 OpenClaw 的通道

---

## 3. Phase 0 — 仓库初始化 ✅ 已完成（v0.1.0）

### 任务
1. 确认路径，建立目录：`scripts/ config/ logs/`
2. 补充 `.gitignore`（logs、tmp、env、ref/）
3. OpenClaw 调用方式已确认：`openclaw send "消息"` 命令行调用

---

## 4. Phase 1 — tmux 会话 + 指令发送 ✅ 已完成（v0.1.0 / 持续完善）

### 目标
建立 Claude Code 的托管运行环境和指令通道，人类可随时观察。

### 任务
1. `scripts/supervisor_run.sh`：创建/复用 tmux session `cc-supervise`，启动 Claude Code 交互模式
2. `scripts/cc_send.sh`：通过 `tmux send-keys -t cc-supervise` 发送文本 + Enter
3. `scripts/cc_capture.sh`：快照 tmux pane 最近 N 行输出（诊断用）
4. **目录信任提示处理**（事后补全）：`supervisor_run.sh` 启动 Claude Code 后轮询 pane 内容，检测到信任确认提示时在操作者终端明确询问（`read -r -p`），操作者回 `y` 才转发；回 `n` 或无 TTY（非交互模式）则打印警告，提示操作者手动 `tmux attach` 处理。避免脚本自动代为授权陌生目录。

---

## 5. Phase 2 — Hook 事件管道 ✅ 已完成（v0.1.0）

### 目标
让 Claude Code 的状态变化通过 Hook 主动通知 OpenClaw，替代轮询。

### 任务
1. `scripts/on-cc-event.sh`：统一 Hook 回调，写 events.ndjson，调用 openclaw send
2. `scripts/install-hooks.sh`：合并 Hook 配置到目标项目的 `.claude/settings.local.json`
3. `config/claude-hooks.json`：Hook 注册模板

---

## 6. Phase 3 — 稳健性：超时 + 技能定义 ✅ 已完成（v0.1.0）

### 任务
1. `scripts/cc-watchdog.sh`：监控 events.ndjson 修改时间，超时后 openclaw send 告警
2. `scripts/demo.sh`：端到端演示脚本（不需要真实 Claude Code）
3. `config/cc-supervisor-skill.md`：OpenClaw 技能定义（初版）

---

## 7. Phase 4 — 文档与多项目支持 ✅ 已完成（v0.2.0 / v0.3.0）

### 任务
1. `CLAUDE_WORKDIR` 环境变量：分离 skill 安装目录（`CC_PROJECT_DIR`）与目标项目目录
2. `docs/ARCHITECTURE.md` / `docs/SCRIPTS.md`：完整技术文档
3. `README.md` / `README_en.md`：面向多项目使用场景的用户文档
4. `CHANGELOG.md` / `VERSION`：版本管理

---

## 8. Phase 5 — 事件信息完整化 ✅ 已完成（v0.5.0）

### 目标

确保每类 Hook 事件携带充分上下文，使 OpenClaw 在任意监督模式下均可基于事件内容做出有效决策，无需额外轮询补全信息。

### 任务

1. **`on-cc-event.sh` — Stop 事件**：从 Hook 传入的 stdin JSON 中提取 Claude 本轮回复摘要（`response` 字段），附加到 `openclaw send` 通知正文；摘要为空时标注 `[no content]`
2. **`on-cc-event.sh` — PostToolUse 错误**：检测 `toolResult.isError == true`，提取工具名（`toolName`）和 stderr 摘要，触发通知（当前仅写日志，不通知）
3. **`on-cc-event.sh` — Notification**：提取 `notification` 字段完整内容附加到通知正文（当前可能截断）
4. **事件 payload 格式统一**：所有通知正文采用结构化格式，包含 `event_type`、`summary`、`timestamp`、`session_id`（如有）

### 验收标准

- [ ] Stop 通知正文含 Claude 本轮回复摘要
- [ ] PostToolUse 出错时触发通知，含工具名和 stderr 摘要
- [ ] Notification 通知正文含完整通知内容
- [ ] `logs/events.ndjson` 中对应字段有值（不为空或 null）

---

## 9. Phase 6 — 监督模式配置 ✅ 已完成（v0.5.0）

### 目标

通过 `CC_MODE` 环境变量区分两种监督模式，脚本层只负责信息传递，策略逻辑通过配置定义，无需修改脚本。

### 两种模式定义

| 模式 | `CC_MODE` 值 | OpenClaw 行为 | 适用场景 |
|------|-------------|--------------|---------|
| 转发模式 | `relay`（默认） | 每个关键事件通知人类，等待外部指令 | 敏感任务、人类主导决策 |
| 自主模式 | `autonomous` | Stop 后自主决策是否继续，仅终态通知人类 | 长周期任务、高度信任 Claude |

### 任务

1. **`on-cc-event.sh` — 读取 `CC_MODE`**：新增模式判断逻辑；`relay` 模式下所有关键事件均触发 `openclaw send`；`autonomous` 模式下 Stop 事件附加"请自主决策是否继续"标记，PostToolUse 错误和超时仍强制通知
2. **`supervisor_run.sh`**：将 `CC_MODE` 传入 tmux 会话环境变量，使 Hook 回调可继承
3. **`SKILL.md` 更新**：在操作指南中说明两种模式的调用方式和适用场景
4. **`config/claude-hooks.json` 注释**：补充 `CC_MODE` 说明

### 验收标准

- [ ] `CC_MODE=relay` 时，Stop / PostToolUse 错误 / Notification 事件均触发 `openclaw send`
- [ ] `CC_MODE=autonomous` 时，Stop 通知携带"自主推进"标记；PostToolUse 错误和超时仍强制通知人类
- [ ] `CC_MODE` 未设置时默认 `relay`
- [ ] 两种模式切换仅需修改环境变量，无需改脚本

---

## 10. Phase 7 — ClawHub Skill 打包 🚧 待完成（v0.4.0）

### 目标

将项目改造为标准 ClawHub Skill，满足以下条件：
- `clawhub install cc-supervisor` 一键安装
- 安装落地于 `~/.openclaw/skills/cc-supervisor/`（整个 repo 即 skill）
- SKILL.md 在 repo 根目录，含标准 frontmatter

### 当前问题

| 问题 | 现状 | 目标 |
|------|------|------|
| SKILL.md 位置错误 | `config/cc-supervisor-skill.md`，需手动 cp | repo 根目录 `SKILL.md` |
| SKILL.md 缺少 frontmatter | 无 name/version/metadata | 含完整 ClawHub 元数据 |
| 安装路径错误 | 文档写 `workspace-forge/skills/`（路径不存在） | `~/.openclaw/skills/cc-supervisor/` |
| 脚本引用路径 | SKILL.md 内使用相对路径 `./scripts/` | 使用绝对路径 `~/.openclaw/skills/cc-supervisor/scripts/` |
| 无法声明依赖 | 用户需手动安装 tmux、jq | frontmatter `install` 数组声明 brew 依赖 |

### 任务

1. **创建 `SKILL.md`（repo 根目录）**
   - YAML frontmatter：
     ```yaml
     ---
     name: cc-supervisor
     description: ...
     version: 0.4.0
     metadata:
       openclaw:
         emoji: 🦾
         requires:
           bins: [tmux, jq, claude]
         install:
           - kind: brew
             formula: jq
             bins: [jq]
           - kind: brew
             formula: tmux
             bins: [tmux]
         os: [macos]
     ---
     ```
   - 正文：完整工作流指南，所有脚本路径使用 `~/.openclaw/skills/cc-supervisor/scripts/`
   - 包含：启动会话、发送任务、等待 Hook 通知、决策逻辑、超时处理

2. **删除 `config/cc-supervisor-skill.md`**（被 SKILL.md 取代）

3. **更新 `README.md` / `README_en.md`**
   - 主安装方式改为 `clawhub install cc-supervisor`（或手动 `git clone <repo> ~/.openclaw/skills/cc-supervisor`）
   - 所有路径示例改为 `~/.openclaw/skills/cc-supervisor`
   - Shell alias 中 `CC_PROJECT_DIR` 改为 `~/.openclaw/skills/cc-supervisor`
   - 文档表中 `config/cc-supervisor-skill.md` 改为 `SKILL.md`

4. **更新 `docs/SCRIPTS.md`**：示例路径统一改为 `~/.openclaw/skills/cc-supervisor/`

5. **更新 `CHANGELOG.md` / `VERSION`** → v0.4.0

### 验收标准

- [ ] `~/.openclaw/skills/cc-supervisor/SKILL.md` 存在，frontmatter 通过 ClawHub 格式校验
- [ ] README 中所有脚本路径指向 `~/.openclaw/skills/cc-supervisor/`
- [ ] `config/cc-supervisor-skill.md` 已删除
- [ ] 文档中不再出现 `workspace-forge` 路径
- [ ] 手动 `git clone <repo> ~/.openclaw/skills/cc-supervisor` 后可直接调用脚本

---

## 11. Phase 8 — ClawHub 发布（后续）

### 任务
1. `clawhub publish . --slug cc-supervisor --name "cc-supervisor" --version 0.5.0`
2. 验证 `clawhub install cc-supervisor` 可正常安装
3. 在 `SKILL.md` 中添加 `metadata.openclaw.homepage` 指向 GitHub repo

---

## 12. KPI / DoD

### KPI
- Hook 触发到 OpenClaw 收到通知 < 3s
- OpenClaw 等待 Claude Code 响应期间 token 消耗 = 0
- 多轮监督可形成闭环（指令 → 响应 → 通知 → 下一步指令）

### Definition of Done
1. Claude Code 在 tmux 交互式会话中运行，人类可随时 `tmux attach` 观察
2. OpenClaw 通过 `cc_send.sh` 发送 prompt，Claude Code 正常响应
3. Claude Code 每轮响应后 Hook 触发，OpenClaw 收到含充分上下文的通知（摘要、工具结果、错误详情）
4. OpenClaw 能据此决策并发送后续 prompt，形成多轮推进闭环
5. 长时间无事件时 watchdog 主动告警
6. 系统不依赖轮询
7. `CC_MODE=relay`（转发模式）：每个关键事件通知人类，等待外部指令
8. `CC_MODE=autonomous`（自主模式）：Stop 后 OpenClaw 自主推进，仅终态通知人类
9. `clawhub install cc-supervisor` 或手动 git clone 后无需额外配置即可使用
10. 同一 skill 安装支持监督多个不同本地项目（`CLAUDE_WORKDIR` 区分）
