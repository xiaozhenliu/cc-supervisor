# PRD: Code Supervisor（OpenClaw Agent 监督 Claude Code）

## 1. 背景
当前监督 Claude Code 的方式主要是人工盯终端或定时轮询，存在：
- 无进展时也持续消耗注意力与 token
- 卡住/等待确认/完成等关键状态不够及时
- 监督行为依赖个人习惯，难复制

## 2. 问题定义
我们需要的不是"更多日志"，而是一个可复用的监督产品能力：
- 由 OpenClaw Agent 承担默认监督责任，通过多轮 prompt 推动 Claude Code 持续工作直到目标达成
- 人类无需全程盯屏，但保留随时 tmux attach 观察和手动介入的能力
- 用 Hooks 事件驱动代替轮询，降低监督成本，等待期 token 消耗为 0
- 监督工具须区分两种截然不同的使用意图：**人类主导、OpenClaw 仅作传声筒**（高控制）vs **人类委托目标、OpenClaw 自主推进**（高信任）；当前工具混淆了两者，角色定位模糊
- Hook 事件须携带充分上下文，使 OpenClaw 无论处于何种监督模式均能基于事件内容做出有效决策；当前事件信息不完整，OpenClaw 缺乏足够上下文
- **Stop 事件须分类处理**：Claude Code 停下来的原因多种多样（任务完成、等待确认、提出问题、遇到阻塞等），当前统一作为自由文本转发，OpenClaw 和人类均无法快速判断应如何响应；须由 OpenClaw 在收到通知后先对输出内容分类，再按类型决定处理方式
- **Hook 事件存在盲区**：Claude Code 在长时间执行工具（如 bash 命令、大文件写入）期间不会触发任何 Hook 事件，agent 完全失去对会话状态的感知；watchdog 仅在超时（默认 30 分钟）后告警，无法提供中间状态可见性；需要一种主动查询机制作为事件驱动的补充，让 agent 能定期感知 Claude Code 的实时状态

## 3. 产品目标
1. 建立 Agent 主导的多轮监督模式：OpenClaw 发送 prompt 推动 Claude Code 持续工作，直到目标达成
2. 把监督从"轮询"升级为"事件驱动"（以 Claude Code Hooks 为核心触发机制）
3. Claude Code 运行在 tmux 交互式会话中，OpenClaw 通过 tmux send-keys 发送后续指令
4. 人类可随时通过 tmux attach 观察 Claude Code 实际终端
5. 以 **ClawHub Skill** 形式分发，一行命令安装，开箱即用于任意本地项目
6. 定义两种监督模式，通过 `CC_MODE` 配置切换，满足不同控制偏好：**转发模式**（人类主导决策）和**自主模式**（OpenClaw 自主推进，仅终态通知人类）
7. 确保每类 Hook 事件携带充分上下文信息，使 OpenClaw 在任意模式下均可基于事件内容做出有效决策
8. **Stop 事件分类处理**：OpenClaw 收到 Stop 通知后，先对 Claude Code 输出内容进行分类，再按类型决定处理方式，而非统一转发自由文本
9. **主动查询机制**：agent 定期通过 `cc-capture` 抓取 Claude Code 终端输出，主动感知会话状态并决定是否需要干预，作为事件驱动的补充；查询间隔可配置（`CC_POLL_INTERVAL`，单位分钟，范围 3–1440，默认 15），设为 `0` 禁用

## 4. 成功指标（MVP）
- Claude Code 状态变化后 OpenClaw 在秒级内收到 Hook 通知（延迟 < 3s）
- OpenClaw 等待 Claude Code 响应期间 token 消耗为 0（不轮询，事件驱动）
- OpenClaw 能根据通知内容决策并发送后续 prompt，形成"指令 → 执行 → 通知 → 下一步指令"多轮闭环
- 任务卡住超过阈值（默认 30 分钟）后 OpenClaw 收到超时告警
- 人类可随时 tmux attach 查看 Claude Code 实际终端，观察进度或手动介入
- 主动查询机制启用时（`CC_POLL_INTERVAL > 0`），agent 能在 Hook 事件间隙感知 Claude Code 实时状态，发现异常（卡住、报错、等待输入）后主动干预
- 支持同时监督多个不同本地项目（通过 `CLAUDE_WORKDIR` 区分工作目录）

## 5. 用户与场景
### 目标用户
- 安装了 OpenClaw 的开发者，需要监督 Claude Code 完成长任务
- 通过 ClawHub 安装后，可在本机任意项目中使用，无需重复配置

### 典型场景

#### 转发模式（`CC_MODE=relay`，默认）
人类是决策主体，全程掌控执行方向。OpenClaw 将每个关键 Hook 事件转达给人类；人类据此判断下一步，通过 OpenClaw 将指令发送给 Claude Code。
适用于：敏感任务、高风险操作、人类不完全信任 Claude 输出的场景。

#### 自主模式（`CC_MODE=autonomous`）
人类定义目标后完全委托。OpenClaw 自动批准所有编程相关的操作（创建/删除文件、安装依赖、修改配置、提交代码、调用 API 等），自动发送下一条 prompt 形成闭环，直至任务完成或真正卡住（缺少外部信息、重复失败、系统级错误）时才通知人类。
适用于：长周期重构/测试修复、开发环境任务、人类完全信任 Claude 输出的场景。
安全保障：通过沙箱、版本控制、备份机制保证安全，而非交互确认。

#### 通用场景（两种模式共有）
- 人类随时可通过 tmux attach 观察终端、手动介入，不受模式限制
- **首次在新目录启动监督**：Claude Code 弹出目录信任确认提示，操作者须在脚本终端明确回 `y` 授权，避免意外信任陌生目录
- **自主模式下的升级**：只在真正卡住时升级（缺少外部信息、重复失败 3 次、系统级错误），不因"风险"升级

## 6. 产品范围
### In Scope（本期）
- Claude Code 在 tmux 交互式会话中运行
- OpenClaw Agent 作为监督主体，通过 tmux send-keys 向 Claude Code 发送 prompt
- 基于 Claude Code Hooks（Stop / PostToolUse / Notification / SessionEnd）的事件感知
- **事件信息完整化**：Stop 事件携带 Claude 本轮回复摘要；PostToolUse 错误携带工具名和 stderr 摘要；Notification 携带完整内容
- **`CC_MODE` 监督模式配置**：`relay`（转发模式，默认）或 `autonomous`（自主模式），控制 `on-cc-event.sh` 的通知策略和 OpenClaw 决策行为
- **Stop 事件分类处理**：OpenClaw 收到 Stop 通知后，先对 Claude Code 输出内容分类，再按类型响应：

  | 类型 | 判断依据 | relay 处理 | autonomous 处理 |
  |------|---------|-----------|----------------|
  | 任务完成 | 输出表明所有工作已完成，无待办项 | 告知人类，进入 Phase 6 | 告知人类，进入 Phase 6 |
  | 等待确认 | 输出末尾有 yes/no 或二选一问题 | 告知人类，等待回复后 `cc-send --key y/n` | 根据上下文 `cc-send --key y/n` |
  | 多项选择 | 输出列出编号选项供选择 | 告知人类，等待回复后 `cc-send --key <数字>` | 根据任务目标 `cc-send --key <数字>` |
  | 光标导航 | 输出显示需移动光标的菜单/列表 | 告知人类，等待回复后 `cc-send --key Up/Down` + `cc-send --key Enter` | 自主导航选择 |
  | 开放性问题 | 输出提出需要具体信息的问题 | 告知人类，等待回复后 `cc-send "<答案>"` | 若能自主回答则 `cc-send "<答案>"`，否则升级人类 |
  | 遇到阻塞 | 输出表明错误、权限不足或无法继续 | 告知人类，等待指令后 `cc-send "<指令>"` | 尝试自修复一次，失败则升级人类 |
  | 中间状态 | 输出表明任务仍在进行中，无需输入 | 告知人类（仅告知进度） | `cc-send "Please continue."` |

  **relay 模式**：所有类型均告知人类，等待人类回复后才发送 cc-send，OpenClaw 不自主决策。
  **autonomous 模式**：所有类型由 OpenClaw 自主处理；仅在无法自主处理或任务全部完成时通知人类。详细决策规则见 `docs/AUTONOMOUS_DECISION_RULES.md`。
  分类由 OpenClaw agent 基于输出内容判断，脚本层不参与分类逻辑。回复不明确时 OpenClaw 须追问，不得猜测。
- OpenClaw 通过 openclaw send 接收 Hook 通知，据此决策下一步
- 人类通过 tmux attach 随时观察和介入
- 结构化事件日志（NDJSON）供事后查阅
- 以 ClawHub Skill 形式分发：`clawhub install cc-supervisor`
- 安装后整个 repo（含脚本）位于 `~/.openclaw/skills/cc-supervisor/`，无需额外配置工具路径
- 支持多项目：通过 `CLAUDE_WORKDIR` 指定目标项目，`CC_PROJECT_DIR` 固定指向 skill 安装目录
- **主动查询机制（Proactive Polling）**：agent 可配置定时通过 `cc-capture` 抓取 Claude Code 终端实时输出，主动感知会话状态并决定是否需要干预；作为事件驱动的补充，覆盖 Hook 事件盲区（长时间工具执行、未触发 Hook 的异常状态）：

  | 配置项 | 默认值 | 说明 |
  |--------|--------|------|
  | `CC_POLL_INTERVAL` | `15`（分钟） | 主动查询间隔（分钟）；范围 `3`–`1440`，设为 `0` 禁用 |
  | `CC_POLL_LINES` | `40` | 每次抓取的终端行数 |

  **查询结果处理**：agent 收到终端快照后，按与 Stop 事件相同的分类逻辑判断状态，决定是否需要干预（发送指令、通知人类、或忽略继续等待）。
  **与 watchdog 的关系**：watchdog 是"超时告警"（被动，仅在长时间无事件后触发一次），主动查询是"定期体检"（主动，按间隔持续感知）。两者互补，不替代。

### Out of Scope（本期不做）
- 完整 Web 控制台
- 分布式多机调度
- 复杂持久化分析平台

## 7. 关键原则
1. **监督主体明确**：OpenClaw Agent 负责默认监督，主动推进任务
2. **最小打扰**：Claude Code 正常推进时不打扰人类；仅在完成、失败、超时、需要人工判断时通知
3. **状态可感知**：Hook 事件驱动，完成/失败/卡住均有通知，不依赖轮询
4. **人工可接管**：人类随时 tmux attach 观察，随时手动发送指令，不受监督模式限制
5. **明确授权原则**：任何可能影响系统安全的交互式提示（如 Claude Code 目录信任确认）均须操作者明确回应，脚本不得自动代为确认；非交互模式下拒绝静默授权
6. **信息完整性**：每类 Hook 事件须携带充分上下文（摘要、工具结果、错误详情），确保 OpenClaw 在任意监督模式下均可基于事件内容做出有效决策，不依赖额外轮询补全信息
7. **模式分离**：监督行为策略通过 `CC_MODE` 配置定义；脚本层只负责信息传递，不硬编码决策逻辑；策略变更无需修改脚本
8. **Stop 分类优先**：OpenClaw 收到 Stop 通知后，必须先对输出内容分类，再按类型决定处理方式；禁止将所有 Stop 事件统一作为自由文本转发给人类，避免人类无法判断如何响应
9. **结果可追溯**：所有 Hook 事件写入 NDJSON 日志，可事后查阅
10. **开箱即用**：ClawHub 安装后路径固定，SKILL.md 中所有脚本引用使用绝对路径，无需用户手动配置
11. **主动感知补充事件驱动**：事件驱动为主、主动查询为辅；主动查询默认启用（`CC_POLL_INTERVAL=15` 分钟），设为 `0` 可禁用；查询结果复用 Stop 事件的分类逻辑，不引入新的决策路径；若 Hook 已在间隔内提供新信息则自动跳过

## 8. 验收标准

### 基础能力
- [ ] OpenClaw 能通过 tmux send-keys 向 Claude Code 发送 prompt 并推动工作
- [ ] Claude Code 每轮响应结束后 Hook 触发，OpenClaw 收到通知
- [ ] OpenClaw 能根据通知内容发送后续 prompt，形成多轮闭环
- [ ] Claude Code 卡住超过阈值后，OpenClaw 收到超时告警
- [ ] 人类可通过 tmux attach 随时观察 Claude Code 实际终端
- [ ] 首次在新目录启动时，脚本在操作者终端明确提示目录信任请求，须操作者显式确认后方可继续；非交互模式打印警告而非静默授权
- [ ] 等待期间 OpenClaw 无轮询、无 token 消耗
- [ ] 所有 Hook 事件写入 NDJSON 日志文件

### 事件信息完整性
- [ ] Stop 事件通知携带 Claude 本轮回复摘要（非空）
- [ ] PostToolUse 出错时通知携带工具名和 stderr 摘要
- [ ] Notification 事件通知携带完整通知内容

### Stop 事件分类处理
- [ ] relay 模式：OpenClaw 对每个 Stop 输出分类后，将分类结果和内容一并转达人类，等待人类回复
- [ ] autonomous 模式：OpenClaw 自主处理所有 Stop 类型，仅在无法处理或任务全部完成时通知人类
- [ ] 回复不明确时 OpenClaw 追问，不猜测意图

### 监督模式配置
- [ ] `CC_MODE=relay` 时，每个关键 Hook 事件均触发对 OpenClaw/人类的通知，OpenClaw 等待外部指令
- [ ] `CC_MODE=autonomous` 时，Stop 事件后 OpenClaw 自主决策是否继续推进，仅在任务完成/失败/超时时通知人类
- [ ] `CC_MODE` 未设置时默认使用 `relay` 模式
- [ ] 两种模式切换无需修改脚本，仅通过环境变量控制

### 主动查询机制
- [ ] `CC_POLL_INTERVAL` 设为 3–1440 分钟时，poll 守护进程按间隔定期抓取终端输出并发送给 agent
- [ ] `CC_POLL_INTERVAL=0` 时，poll 进程不启动，不消耗额外 token
- [ ] 默认 `CC_POLL_INTERVAL=15`（分钟），无需手动配置即可启用
- [ ] 若 `events.ndjson` 在上一个 poll 间隔内被更新过，跳过本次 poll（dedup）
- [ ] 主动查询与 Hook 事件驱动互补，不冲突、不重复触发

### 分发与兼容性
- [ ] `clawhub install cc-supervisor` 安装后，无需额外步骤即可调用 skill
- [ ] 同一 skill 安装可监督多个不同本地项目（CLAUDE_WORKDIR 区分）
- [ ] SKILL.md 通过 ClawHub 格式校验（含 frontmatter、依赖声明）

### 端到端场景验证
使用 `example-project/` 作为标准验证项目，完整走通监督流程：

**标准任务提示词**：
> 制作一个网页向中学生展示量子计算机的工作原理，要求具备充分的文档和测试，并具有一定的可交互性

- [ ] 以 `CLAUDE_WORKDIR=example-project/` 启动 `supervisor_run.sh`，会话正常建立
- [ ] 通过 `cc_send.sh` 发送标准任务提示词，Claude Code 开始执行
- [ ] 执行过程中 Hook 事件（Stop / PostToolUse / Notification）正常触发并写入 `events.ndjson`
- [ ] 转发模式（`CC_MODE=relay`）下，每次 Stop 事件 OpenClaw 收到含回复摘要的通知
- [ ] 自主模式（`CC_MODE=autonomous`）下，OpenClaw 持续推进直至 Claude Code 完成任务
- [ ] 任务完成后，`example-project/` 目录下存在：可在浏览器打开的网页、文档文件、测试文件
- [ ] watchdog 在整个过程中无误触发（未误报超时）

## 9. 交付物
- **PRD**（本文件）：产品目标与边界
- **SKILL.md**（repo 根目录）：ClawHub skill 定义，含 frontmatter 元数据和完整操作指南
- **脚本代码**：`scripts/` 目录下的会话管理、指令发送、Hook 回调、安装脚本
- **配置模板**：`config/claude-hooks.json`（Hook 注册模板）
- **README.md / README_en.md**：安装与使用文档
- **`example-project/`**：端到端验证项目，含标准任务提示词和验证说明；Claude Code 的输出产物也落于此目录

## 10. 关联文档
- `docs/ARCHITECTURE.md`：架构设计、数据流、环境变量、日志格式
- `docs/SCRIPTS.md`：脚本接口参考（入参、环境变量、退出码）
- `CHANGELOG.md`：版本历史
