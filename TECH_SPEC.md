# TECH_SPEC: Code Supervisor（Implementation Spec）

## 1. 体系结构
- Supervisor: OpenClaw Agent（决策）
- Worker: Claude Code（执行）
- Runtime: tmux（托管交互会话）
- Event Bus: Claude hooks -> NDJSON

## 2. 运行模式（As-Is -> To-Be）
### As-Is
- one-shot: `claude -p "..."`
- interactive: `claude`
- external polling: `tmux capture-pane ...`

### To-Be
- `./scripts/supervisor_run.sh`
- `./scripts/cc_send.sh "..."`
- `./scripts/cc_events.sh --tail 50`

## 3. 数据契约
### 3.1 输入事件（给 OpenClaw Agent）
```json
{
  "ts": "ISO8601",
  "runId": "string",
  "event": "PostToolUse|Notification|Stop|...",
  "source": "claude-code",
  "severity": "info|warn|critical",
  "summary": "string",
  "needsAttention": true,
  "raw": {}
}
```

### 3.2 输出动作（OpenClaw Agent）
```json
{
  "ts": "ISO8601",
  "runId": "string",
  "action": "log_only|send_instruction|ask_human|mark_done|mark_blocked",
  "target": "tmux:cc-supervise:0.0",
  "payload": {},
  "reason": "string"
}
```

## 4. 状态机
状态：
- `idle`
- `running`
- `waiting_input`
- `blocked`
- `done`
- `error`

核心迁移：
- `idle -> running`
- `running -> waiting_input`
- `running -> blocked`
- `running -> done`
- `* -> error`

## 5. 自动干预规则（MVP）
1. 连续同类失败 N 次 -> `send_instruction`
2. 长时间无进展 -> `send_instruction`
3. Stop 但无摘要 -> `send_instruction`
4. 敏感/低置信场景 -> `ask_human`

## 6. tmux 约定
- session: `cc-supervise`
- pane `0.0`: Claude Code
- pane `0.1`: events + decisions

## 7. 目录结构
```text
cc-supervisor/
├── PRD.md
├── TECH_SPEC.md
├── EXECUTION_PLAN.md
├── scripts/
├── hooks/
├── bridge/
├── config/
└── logs/
```

## 8. 脚本职责
- `scripts/supervisor_run.sh`: 启动运行时
- `scripts/cc_send.sh`: 下发指令
- `scripts/cc_capture.sh`: 抓取执行输出
- `scripts/cc_events.sh`: 查看事件
- `hooks/hook_router.sh`: hooks 入口
- `hooks/parse_event.py`: 事件标准化
- `bridge/openclaw_supervisor_bridge.sh`: 事件->动作桥接
