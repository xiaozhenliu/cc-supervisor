# Bug Report: API Error 后通知静默丢失

**发现时间**：2026-02-28T06:41:49Z（从 `logs/events.ndjson` 首次观测到问题事件）
**严重程度**：中（通知链路完全失效，但 Claude Code 本身正常运行）
**状态**：已完全修复（启动时 WARN + 入队机制均已实现）

---

## 问题描述

Claude Code 遇到 API 500 错误，经过内置重试（最多 10 次）后触发了 Stop Hook。`on-cc-event.sh` 正确执行，事件也写入了 `events.ndjson`，但 OpenClaw 始终**没有收到任何通知**。

用户误以为自动响应生效（或测试通过），实际上通知在脚本层被静默跳过，没有任何显眼的报错。

---

## 触发场景

- 从 **webchat（claude.ai）** 发起监督任务，而非从 Discord 发起
- `supervisor_run.sh` 启动时 `OPENCLAW_SESSION_ID` 为空（webchat 没有可用于异步回调的会话 ID）
- Claude Code 执行过程中遭遇 API 500 错误，重试完毕后 Stop Hook 触发

---

## 日志证据

### 相关日志文件

| 文件 | 路径 | 说明 |
|------|------|------|
| 事件日志 | `logs/events.ndjson` | 包含 Stop 事件记录及终端截图内容 |
| 运行日志 | `logs/supervisor.log` | 包含 Hook 接收、跳过通知的 WARN 行 |

### 关键日志片段

**`logs/events.ndjson`**（Stop 事件，06:41:49Z）：
```json
{
  "ts": "2026-02-28T06:41:49Z",
  "event_type": "Stop",
  "session_id": "8464630a-54fc-4e93-9c26-6f0cf9716c06",
  "summary": " API 500 error. Please retry from the current step\n  and continue implementation.\n  ⎿  500 请求错误(状态码: 500)\n\n     Retrying in 12 seconds… (attempt 7/10)\n\n✽ Creating physics module… (1m 36s)\n..."
}
```

Stop 触发时终端截图中可见 `Retrying in 12 seconds… (attempt 7/10)`，说明 Stop 在**所有重试结束后**才触发（截图是 viewport 快照，非触发瞬间的精确状态）。

**`logs/supervisor.log`**（06:41:49Z 前后）：
```
{"ts":"2026-02-28T06:41:49Z","level":"INFO","script":"on-cc-event.sh","msg":"Received: type=Stop session=8464630a..."}
{"ts":"2026-02-28T06:41:49Z","level":"INFO","script":"cc_capture.sh","msg":"Capturing last 30 lines from 'cc-supervise'"}
{"ts":"2026-02-28T06:41:49Z","level":"INFO","script":"on-cc-event.sh","msg":"Logged to events.ndjson: Stop"}
{"ts":"2026-02-28T06:41:49Z","level":"WARN","script":"on-cc-event.sh","msg":"OPENCLAW_SESSION_ID not set — notification skipped (event=Stop)"}
```

WARN 出现在事件写入日志之后、`openclaw agent` 调用之前，意味着通知在这里被静默丢弃，没有入队，无法重放。

---

## 根因分析

### 1. webchat 无法支持异步回调

`openclaw agent --session-id` 是**异步推送机制**：Hook 回调触发后，将消息投递到指定 session 的 inbox。Discord 有持久频道，满足这个条件；webchat 对话是临时的，外部系统无法异步写入。

| 发起平台 | OPENCLAW_SESSION_ID | OPENCLAW_CHANNEL | OPENCLAW_TARGET | 结果 |
|---------|--------------------|-----------------|-----------------|----|
| Discord | ✓ 有效会话 ID | `discord` | Channel ID | 通知成功 |
| Webchat | ✗ 空 | 空 | 空 | 全链路静默失败 |

### 2. 启动时无预警（已修复）

`supervisor_run.sh` 原本在启动时不检查 `OPENCLAW_SESSION_ID`，只有等到 Hook 触发、进入 `on-cc-event.sh` 时才出现 WARN。用户在启动阶段无法察觉通知路径已断开。

**修复**：已在 `supervisor_run.sh` 中加入启动时检查（commit 见下方）。

### 3. SESSION_ID 为空时不入队（待修复）

`on-cc-event.sh` 中，`OPENCLAW_SESSION_ID` 为空时直接跳过，不进入 `notification.queue`：

```bash
# scripts/on-cc-event.sh:164
if [[ -z "${OPENCLAW_SESSION_ID:-}" ]]; then
  log_warn "OPENCLAW_SESSION_ID not set — notification skipped"
  # ← 消息永久丢失，未入队
fi
```

而其他失败情况（如 `openclaw` 命令不在 PATH、`openclaw agent` 返回非零）则会入队，留有重放机会。SESSION_ID 为空是唯一一个会永久丢失消息的路径。

---

## API Error 触发 Stop 的行为确认

此次测试也**确认了一个重要事实**：API 500 错误在重试耗尽后**确实会触发 Stop Hook**。

```
06:40:06Z - 06:40:48Z  PostToolUse × 5（Claude 在使用工具）
                         ↓ API 500 error，进入内置重试（最多 10 次）
06:41:49Z              Stop Hook 触发（约 61 秒后）
```

Hook 盲区约为 61 秒（重试窗口），在 watchdog 默认阈值（1800s）内，属于可接受范围。

---

## 已修复

| # | 描述 | 状态 |
|---|------|------|
| 1 | `supervisor_run.sh` 启动时若 `OPENCLAW_SESSION_ID` 为空，立即打印 WARN | ✅ 已修复 |
| 2 | `supervisor_run.sh` 启动时若 `OPENCLAW_SESSION_ID` 有值但 `OPENCLAW_TARGET` 为空，打印 WARN | ✅ 已修复 |
| 3 | `on-cc-event.sh` / `cc-watchdog.sh` / `cc-poll.sh`：SESSION_ID 为空时将通知入队，而非永久丢弃 | ✅ 已修复 |

## 待处理

| # | 描述 | 优先级 |
|---|------|--------|
| 4 | webchat 替代通知手段已通过入队机制覆盖：`on-cc-event.sh`/`cc-watchdog.sh`/`cc-poll.sh` SESSION_ID 为空时均入队，`flush-queue.sh` 可重放 | ✅ 已关闭 |
