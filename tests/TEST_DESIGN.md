# 测试设计文档

## 测试目标

验证 cc-supervisor 的核心行为：Hook 事件正确触发通知、通知路由到正确目标、agent 行为符合 SKILL.md 规范。

---

## 测试分层

```
层次 3: Agent 行为测试     ← 最难，依赖真实 OpenClaw 环境
层次 2: Hook 管道测试      ← 最有价值，可完全自动化
层次 1: 静态检查           ← 已有基础，可立即扩展
```

---

## 层次 1：静态检查（`tests/test_lint.sh`）

验证代码和配置的静态正确性，无需运行时环境。

### 1.1 Shell 脚本语法检查

| 测试 ID | 描述 | 方法 |
|---------|------|------|
| L1-01 | 所有 `.sh` 文件语法合法 | `bash -n <file>` |
| L1-02 | 所有 `.sh` 文件有执行权限 | `test -x <file>` |
| L1-03 | shebang 行存在且正确 | `head -1` 检查 `#!/usr/bin/env bash` |

### 1.2 SKILL.md 结构检查

| 测试 ID | 描述 | 验证内容 |
|---------|------|---------|
| L2-01 | YAML frontmatter 存在 | 文件以 `---` 开头，包含 `name`、`description`、`version` |
| L2-02 | 必要章节存在 | Phase 0–6 均存在 |
| L2-03 | 引用的脚本文件存在 | `cc-supervise`、`cc-send`、`cc-install-hooks` 等 |
| L2-04 | 版本号与 VERSION 文件一致 | SKILL.md frontmatter `version` == `VERSION` 文件内容 |

### 1.3 配置文件检查

| 测试 ID | 描述 | 方法 |
|---------|------|------|
| L3-01 | `config/claude-hooks.json` 是合法 JSON | `jq . <file>` |
| L3-02 | hooks 包含四个必要事件 | Stop、PostToolUse、Notification、SessionEnd |

---

## 层次 2：Hook 管道测试（`tests/test_hook_pipeline.sh`）

用 mock `openclaw` 替换真实命令，直接向 `on-cc-event.sh` 注入 Hook JSON，验证通知行为。

### 测试基础设施

```
tests/
├── fixtures/          # 预制 Hook JSON 输入
│   ├── stop_event.json
│   ├── posttooluse_error_403.json
│   ├── posttooluse_error_no_http.json
│   ├── posttooluse_success.json
│   ├── notification_event.json
│   └── session_end_event.json
└── mock/
    └── openclaw        # mock 脚本，记录调用参数到临时文件
```

**mock openclaw 行为：**
- 将收到的所有参数写入 `$MOCK_CALL_LOG`（临时文件）
- 退出码 0（模拟成功）
- 支持 `MOCK_OPENCLAW_FAIL=1` 环境变量模拟失败

### 2.1 Stop 事件

| 测试 ID | 描述 | 输入条件 | 期望结果 |
|---------|------|---------|---------|
| H1-01 | relay 模式 Stop 触发通知 | `CC_MODE=relay`，Stop JSON，`OPENCLAW_SESSION_ID` 已设置 | openclaw 被调用，`--session-id` 参数正确 |
| H1-02 | relay 模式消息格式 | 同上 | `--message` 包含 `[cc-supervisor][relay] Stop:` |
| H1-03 | auto 模式消息格式 | `CC_MODE=auto` | `--message` 包含 `[cc-supervisor][auto] Stop:` |
| H1-04 | 有 OPENCLAW_TARGET 时附加 deliver 参数 | `OPENCLAW_TARGET=123456` | openclaw 调用包含 `--deliver --reply-to 123456` |
| H1-05 | 无 OPENCLAW_TARGET 时不附加 deliver 参数 | `OPENCLAW_TARGET` 未设置 | openclaw 调用不含 `--deliver` |
| H1-06 | 无 OPENCLAW_SESSION_ID 时入队 | `OPENCLAW_SESSION_ID` 未设置 | openclaw 未被调用，`notification.queue` 有新记录 |

### 2.2 PostToolUse 错误事件

| 测试 ID | 描述 | 输入条件 | 期望结果 |
|---------|------|---------|---------|
| H2-01 | 工具错误触发通知 | `isError: true` | openclaw 被调用 |
| H2-02 | HTTP 403 错误格式 | 错误文本含 `403` | 消息包含 `API error 403` |
| H2-03 | HTTP 500 错误格式 | 错误文本含 `500` | 消息包含 `API error 500` |
| H2-04 | 无 HTTP 状态码的错误格式 | 错误文本不含 HTTP 码 | 消息包含 `Tool error —` |
| H2-05 | 工具成功不触发通知 | `isError: false` | openclaw 未被调用 |
| H2-06 | 错误消息包含工具名 | `tool_name: WebFetch` | 消息包含 `WebFetch` |

### 2.3 Notification 事件

| 测试 ID | 描述 | 期望结果 |
|---------|------|---------|
| H3-01 | Notification 触发通知 | openclaw 被调用 |
| H3-02 | 消息内容正确传递 | `--message` 包含原始 message 字段内容 |

### 2.4 SessionEnd 事件

| 测试 ID | 描述 | 期望结果 |
|---------|------|---------|
| H4-01 | SessionEnd 触发通知 | openclaw 被调用 |
| H4-02 | 消息包含 session_id | `--message` 包含 `Session ended` 和 session_id |

### 2.5 去重逻辑

| 测试 ID | 描述 | 期望结果 |
|---------|------|---------|
| H5-01 | 相同 session_id + event_id 第二次跳过 | 第一次调用 openclaw，第二次不调用 |
| H5-02 | 不同 event_id 不跳过 | 两次都调用 openclaw |

### 2.6 events.ndjson 日志

| 测试 ID | 描述 | 期望结果 |
|---------|------|---------|
| H6-01 | 每个事件都写入日志 | `events.ndjson` 新增一行 |
| H6-02 | 日志行是合法 JSON | `jq .` 解析成功 |
| H6-03 | 日志包含必要字段 | `ts`、`event_type`、`session_id`、`event_id`、`summary` 均存在 |

### 2.7 openclaw 失败时入队

| 测试 ID | 描述 | 期望结果 |
|---------|------|---------|
| H7-01 | openclaw 调用失败时入队 | `MOCK_OPENCLAW_FAIL=1`，`notification.queue` 有新记录 |
| H7-02 | 队列记录格式正确 | 包含 timestamp、channel、target、event_type、message，`|` 分隔 |

---

## 层次 3：Agent 行为测试（手动 + 半自动）

验证 SKILL.md 中定义的 agent 决策逻辑。由于依赖真实 OpenClaw 环境，这一层以**检查清单**形式记录，每次发布前手动执行。

### 3.1 Phase 0–3 启动流程

| 检查项 | 验证方法 |
|--------|---------|
| Session ID 获取为 UUID 格式 | 观察 agent 输出的 `echo $OPENCLAW_SESSION_ID` |
| OPENCLAW_TARGET 未设置时 agent 上报 | 清空 OPENCLAW_TARGET，观察 agent 是否 escalate |
| Phase 3 启动命令包含三个变量 | 观察 agent 执行的 `cc-supervise` 命令 |

### 3.2 Phase 3.5 Hook 验证

| 检查项 | 验证方法 |
|--------|---------|
| 测试消息在 30 秒内收到回调 | 观察 `[cc-supervisor]` 消息是否到达 |
| 超时时 agent 执行诊断步骤 | 手动阻断通知，观察 agent 行为 |

### 3.3 relay 模式决策

| 检查项 | 验证方法 |
|--------|---------|
| 每个 Stop 事件都转发给 human | 触发 Stop，观察 agent 是否发消息 |
| agent 不自行决策 | 观察 agent 是否等待 human 回复 |

### 3.4 auto 模式决策

| 检查项 | 验证方法 |
|--------|---------|
| Yes/No 提示自动回复 y | 触发需要确认的操作 |
| 连续 continue 不超过 8 次 | 观察计数器 |
| 同一错误 3 次后 escalate | 注入重复错误 |

---

## 测试执行方式

```bash
# 层次 1：静态检查
./tests/test_lint.sh

# 层次 2：Hook 管道（需要 jq、bash）
./tests/test_hook_pipeline.sh

# 层次 1+2 合并运行
./tests/run_all.sh

# 层次 3：手动检查清单
# 参考本文档 3.x 章节，在真实 OpenClaw 会话中逐项验证
```

---

## CI 集成建议

层次 1 和层次 2 可加入 pre-commit hook 或 GitHub Actions：

```yaml
- name: Run tests
  run: |
    ./tests/test_lint.sh
    ./tests/test_hook_pipeline.sh
```

层次 3 在每次 SKILL.md 有实质性修改后手动执行。

---

## 覆盖的历史 Bug

| Bug | 对应测试 |
|-----|---------|
| 通知路由到 webchat（缺少 OPENCLAW_TARGET） | H1-04、H1-05 |
| API 错误未上报（PostToolUse 未通知） | H2-01 至 H2-06 |
| Session ID 使用路由格式而非 UUID | L2-01（SKILL.md 版本一致性） |
| openclaw 失败时消息丢失 | H7-01、H7-02 |
