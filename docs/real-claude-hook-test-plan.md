# Real Claude Hook 集成测试计划

## 1. 目标

1.1 建立一条专门验证 `Claude Code + tmux + Hook` 的集成测试路径。  
1.2 将最容易出错的 Hook 集成从“真实 OpenClaw 全链路手测”中拆出来单独验证。  
1.3 保留少量真实 OpenClaw smoke test，但不再让其承担大部分回归验证职责。  

## 2. 范围

2.1 本计划覆盖以下对象：

1. `scripts/install-hooks.sh`
2. `scripts/supervisor_run.sh`
3. `scripts/cc_send.sh`
4. `scripts/cc_capture.sh`
5. `scripts/on-cc-event.sh`
6. `config/claude-hooks.json`

2.2 本计划优先验证以下集成链路：

1. Hook 是否正确安装到目标项目
2. Claude Code 是否真实触发 Hook
3. Hook JSON 是否能被 `on-cc-event.sh` 正确解析
4. 事件是否正确写入 `logs/events.ndjson`
5. 通知层是否被调用

2.3 本计划暂不把以下内容作为第一阶段主目标：

1. Skill 被 OpenClaw 真实发现与加载
2. 真实消息路由回 Discord / Telegram / WhatsApp
3. 目录 trust prompt 的自动化常规回归
4. 复杂业务项目上的端到端任务执行

## 3. 核心原则

3.1 真实 Claude 只用在最需要它的地方：Hook 集成层。  
3.2 真实 OpenClaw 不进入主测试路径，先用 stub 或受控替身隔离。  
3.3 所有测试都应尽量检查机器可判定结果，不依赖人工观察 tmux pane。  
3.4 测试工程应保持极小、无网络依赖、无额外安装依赖。  
3.5 先跑通稳定主路径，再补异常分支和 smoke test。  

## 4. 分层测试策略

### 4.1 第一层：现有脚本逻辑测试

1. 继续保留现有 `scripts/test-*.sh`
2. 这一层负责验证解析逻辑、状态文件、副作用、fallback、通知模板等
3. 这一层不依赖真实 Claude

### 4.2 第二层：真实 Claude Hook 集成测试

1. 使用真实 `claude`
2. 使用真实 `tmux`
3. 使用真实 Hook 安装
4. 使用最小 `example-project`
5. 使用 stub `openclaw`

这一层是本计划的重点。

### 4.3 第三层：真实 OpenClaw smoke test

1. 仅保留极少数场景
2. 目标是验证最终真实路由闭环仍然有效
3. 不承担主要回归职责

## 5. 目录与夹具规划

### 5.1 新增最小测试工程

新增目录：

1. `example-project/README.md`
2. `example-project/.gitignore`
3. `example-project/app.txt`
4. `example-project/expected/`

约束：

1. 不引入 npm / pip / 数据库依赖
2. 文件内容极少，便于 Claude 快速理解
3. 任务应可在数秒到数十秒内完成

### 5.2 新增 OpenClaw 替身

新增目录与文件：

1. `tests/fixtures/bin/openclaw`

职责：

1. 接收 `openclaw agent ...` 调用
2. 记录所有参数到测试日志
3. 返回退出码 `0`

必要时再补充：

1. `--json` 固定输出
2. 假 session store 配合路由测试

### 5.3 新增测试脚本

第一批建议新增：

1. `scripts/test-real-claude-hook-stop.sh`
2. `scripts/test-real-claude-hook-session-end.sh`
3. `scripts/test-install-layout.sh`

第二批再补：

1. `scripts/test-real-claude-hook-notification.sh`

## 6. 第一阶段主路径实施步骤

### 6.1 步骤 1：建立 `example-project`

1. 创建最小文件结构
2. 在 `app.txt` 中写入固定文本
3. 确保目录适合作为 Claude 工作目录
4. 不在此目录中放置任何运行时依赖

### 6.2 步骤 2：建立 `openclaw` stub

1. 在测试目录下提供同名可执行文件
2. 将测试时的 `PATH` 指向该 stub 优先于真实 `openclaw`
3. 将命令参数写入临时日志文件
4. 保证返回值为成功

### 6.3 步骤 3：编写 `Stop` 集成测试

测试流程：

1. 创建临时 `HOME`
2. 设置测试专用环境变量
3. 安装 Hook 到 `example-project`
4. 启动 `supervisor_run.sh`
5. 通过 `cc_send.sh` 向 Claude 发送极简单任务
6. 等待 `logs/events.ndjson` 中出现 `Stop`
7. 验证 stub `openclaw` 收到通知
8. 清理 tmux session 和临时目录

建议任务：

1. 让 Claude 读取 `app.txt`
2. 让 Claude 只输出固定短句
3. 不要求联网
4. 不要求运行额外命令

### 6.4 步骤 4：编写 `SessionEnd` 集成测试

测试流程：

1. 复用 `Stop` 场景的启动流程
2. 在 Claude 完成一轮后主动退出
3. 等待 `events.ndjson` 出现 `SessionEnd`
4. 验证通知层被调用

### 6.5 步骤 5：编写安装产物测试

测试流程：

1. 将 skill 安装到临时目录，而不是 `~/.openclaw/skills/cc-supervisor`
2. 检查安装后的关键运行时文件是否存在
3. 检查 `SKILL.md` 中引用的脚本路径在安装产物中是否可达
4. 检查开发文件是否被排除

目标：

1. 提前发现源码树与安装树漂移
2. 提前发现“源码能跑，安装后失效”的问题

## 7. 第二阶段补充步骤

### 7.1 步骤 6：补充 `Notification` 场景

前提：

1. `Stop` 场景已稳定
2. `SessionEnd` 场景已稳定

目标：

1. 找到一个对当前 Claude 版本稳定的 Notification 触发方式
2. 记录其 Hook JSON 结构
3. 为后续版本升级回归提供样本

### 7.2 步骤 7：补充异常路径

优先补以下异常：

1. `openclaw` 不在 `PATH` 时写入 `logs/notification.queue`
2. Hook 环境变量缺失时 `logs/hook.env` fallback 生效
3. Hook 安装失败时脚本报错信息可读

## 8. 第三阶段 smoke test

### 8.1 步骤 8：保留最小真实 OpenClaw 测试

仅保留 1 到 2 条：

1. Skill 能被真实 OpenClaw 正确加载
2. Hook 产生的通知能回到正确 session / channel

要求：

1. 仅用于发布前验证
2. 不作为主回归手段

## 9. 断言标准

### 9.1 安装断言

1. `.claude/settings.local.json` 已生成或更新
2. `Stop` / `PostToolUse` / `Notification` / `SessionEnd` 四个事件键存在

### 9.2 运行断言

1. `cc-supervise` tmux session 存在
2. `cc_send.sh` 发出的内容能在 pane 中观察到效果

### 9.3 Hook 断言

1. `logs/events.ndjson` 中出现目标事件
2. 事件记录包含 `ts`
3. 事件记录包含 `event_type`
4. 事件记录包含 `event_id`
5. 事件记录的 `summary` 非空

### 9.4 通知断言

1. stub `openclaw` 被调用
2. 参数中包含 `--session-id`
3. 参数中包含 `--deliver`
4. 参数中消息体包含 `[cc-supervisor]`

## 10. 环境隔离要求

测试必须隔离以下状态：

1. `HOME`
2. `PATH`
3. `OPENCLAW_SESSION_ID`
4. `OPENCLAW_CHANNEL`
5. `OPENCLAW_TARGET`
6. `OPENCLAW_AGENT_ID`
7. `CC_PROJECT_DIR`
8. tmux session 生命周期

要求：

1. 每次测试开始前清理旧 session
2. 每次测试结束后回收临时目录
3. 不复用用户真实 `~/.openclaw` 状态

## 11. 风险与处理策略

### 11.1 高风险

1. Claude 当前版本 Hook 语义变化
2. tmux readiness 判断脆弱
3. 真实 Claude 输出波动导致测试不稳定

处理策略：

1. 先固定极简单任务
2. 先只做 `Stop` 主路径
3. 用日志与事件文件做断言，不依赖自然语言全文匹配

### 11.2 中风险

1. trust prompt 干扰启动流程
2. 本机目录信任状态残留
3. 旧 tmux session 污染测试

处理策略：

1. trust prompt 不纳入第一阶段主路径
2. 每次测试显式清理 tmux session
3. 通过独立测试目录减少状态污染

### 11.3 低风险

1. `example-project` 内容过于复杂
2. stub `openclaw` 行为定义不清

处理策略：

1. 将 `example-project` 保持最小
2. stub 第一阶段只做参数记录，不模拟复杂行为

## 12. 验收标准

### 12.1 第一阶段完成标准

以下条件全部满足即视为第一阶段完成：

1. `example-project` 已建立
2. `test-real-claude-hook-stop.sh` 稳定通过
3. `test-real-claude-hook-session-end.sh` 稳定通过
4. `test-install-layout.sh` 稳定通过

### 12.2 第二阶段完成标准

以下条件全部满足即视为第二阶段完成：

1. `Notification` 场景已补齐或明确记录为不稳定场景
2. 至少 2 条异常路径测试已落地
3. Hook 相关主风险已有自动化覆盖

### 12.3 第三阶段完成标准

以下条件全部满足即视为第三阶段完成：

1. 至少 1 条真实 OpenClaw smoke test 可运行
2. 发布前能验证真实路由闭环

## 13. 推荐实施顺序

1. 建立 `example-project`
2. 建立 `openclaw` stub
3. 落地 `Stop` 集成测试
4. 落地安装产物测试
5. 落地 `SessionEnd` 集成测试
6. 再评估 `Notification` 场景
7. 最后保留真实 OpenClaw smoke test

## 14. 当前状态说明

1. `example-project/` 已建立，可作为最小真实 Claude 工作目录
2. `tests/fixtures/bin/openclaw` 已建立，用于隔离真实 OpenClaw 路由
3. 第一阶段已落地：
   - `scripts/test-real-claude-hook-stop.sh`
   - `scripts/test-real-claude-hook-session-end.sh`
   - `scripts/test-install-layout.sh`
4. 第二阶段已补两条异常路径：
   - `scripts/test-notification-queue-fallback.sh`
   - `scripts/test-install-hooks-failure.sh`
5. 当前仓库已有统一回归入口：`scripts/test-regression.sh`
6. `Notification` 真实场景仍未纳入默认回归，因为在 Claude Code `v2.1.70` 本机实测下尚未找到稳定触发方式

## 15. Notification 现状记录

1. 已参考官方 Claude Code Hooks 文档记录的 `Notification` 触发条件：
   - 工具权限请求
   - 长时间等待用户输入
2. 当前本机实测结果：
   - 常规 `Bash` 工具调用未稳定触发权限类 `Notification`
   - 空闲等待超过 60 秒未稳定触发 `Notification`
3. 当前结论：
   - `Notification` 应保留为“待补稳定样本”的场景
   - 在未找到稳定触发方式前，不应纳入默认回归入口
## 16. 结论

1. Hook 集成测试应优先引入真实 Claude
2. 真实 OpenClaw 不应继续承担大部分日常回归职责
3. 后续应以“脚本逻辑测试 + 真实 Claude Hook 集成测试 + 少量真实 OpenClaw smoke test”的三层结构推进
