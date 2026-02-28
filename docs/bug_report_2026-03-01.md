# Bug Report — cc-supervisor 错误处理缺口分析

**报告时间：** 2026-03-01T00:00:00Z
**分析版本：** v1.3.0
**分析范围：** SKILL.md 工作流 + 所有 scripts/*.sh
**严重级别：** P0（阻断）/ P1（高）/ P2（中）/ P3（低）

---

## 摘要

通过对 SKILL.md 全流程和所有脚本的深度审查，发现 **8 个错误处理缺口**，其中 1 个 P0 级别（静默失败导致流程继续执行），3 个 P1 级别（超时/崩溃场景无恢复路径），4 个 P2/P3 级别（文档缺失、边界条件）。

---

## BUG-001 [P0] cc-start.sh Step 4：Hook 安装失败被静默忽略

**文件：** `scripts/cc-start.sh:111-124`
**发现时间：** 2026-03-01T00:00:00Z
**状态：** 待修复

### 问题描述

```bash
# 当前代码（第 111-112 行）
CC_PROJECT_DIR="$CC_PROJECT_DIR" CLAUDE_WORKDIR="$PROJECT_DIR" \
  bash "${CC_PROJECT_DIR}/scripts/install-hooks.sh" 2>&1 | sed 's/^/  /'
```

`install-hooks.sh` 的输出通过管道传给 `sed` 做缩进格式化。在 bash 中，管道的退出码是**最后一个命令**（`sed`）的退出码，而不是 `install-hooks.sh` 的退出码。即使 `install-hooks.sh` 以 `exit 1` 退出，`sed` 仍然成功，整个管道返回 0。

`set -uo pipefail` 中的 `pipefail` 本应捕获这种情况，但 `cc-start.sh` 第 21 行是 `set -uo pipefail`（**缺少 `-e`**），所以即使 pipefail 触发，脚本也不会自动退出。

### 影响

Hook 安装失败 → 脚本静默继续 → Step 7 等待 Hook 回调 → 30 秒超时 → 用户困惑，不知道根本原因是 Step 4 失败。

### 复现步骤

1. 故意破坏 `config/claude-hooks.json`（使其 JSON 无效）
2. 运行 `cc-start <project-dir>`
3. 观察：Step 4 显示错误但脚本继续，Step 7 超时

### 修复方向

使用临时文件捕获退出码，或使用 `{ ... } | sed` + `PIPESTATUS` 检查：

```bash
INSTALL_EXIT=0
{ CC_PROJECT_DIR="$CC_PROJECT_DIR" CLAUDE_WORKDIR="$PROJECT_DIR" \
    bash "${CC_PROJECT_DIR}/scripts/install-hooks.sh"; INSTALL_EXIT=$?; } 2>&1 | sed 's/^/  /'
if [[ $INSTALL_EXIT -ne 0 ]]; then
  echo "ERROR: Hook installation failed (exit $INSTALL_EXIT)"
  exit 1
fi
```

---

## BUG-002 [P1] cc-start.sh Step 4：PROJECT_DIR 不存在时错误信息不友好

**文件：** `scripts/cc-start.sh:44`
**发现时间：** 2026-03-01T00:00:00Z
**状态：** 待修复

### 问题描述

```bash
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
```

如果 `$PROJECT_DIR` 不存在，`cd` 失败，bash 输出原始错误：
```
bash: cd: /nonexistent/path: No such file or directory
```

由于 `set -uo pipefail`（无 `-e`），脚本不会自动退出，`PROJECT_DIR` 变量会被设为空字符串，后续操作在错误路径上继续。

### 修复方向

在 `cd` 之前显式检查目录存在性：

```bash
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: project-dir does not exist: $PROJECT_DIR"
  exit 1
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
```

---

## BUG-003 [P1] cc-start.sh：缺少 `-e` 导致错误不中断执行

**文件：** `scripts/cc-start.sh:21`
**发现时间：** 2026-03-01T00:00:00Z
**状态：** 待修复

### 问题描述

```bash
set -uo pipefail   # 第 21 行，缺少 -e
```

其他所有脚本（`supervisor_run.sh`, `on-cc-event.sh`, `install-hooks.sh` 等）都使用 `set -euo pipefail`，但 `cc-start.sh` 缺少 `-e`。这意味着命令失败不会自动终止脚本，需要每个命令都手动检查退出码。

### 影响

BUG-001 和 BUG-002 的根本原因之一。

### 修复方向

将第 21 行改为 `set -euo pipefail`，并审查所有已有 `|| true` 的地方确保仍然正确。

---

## BUG-004 [P1] on-cc-event.sh：磁盘满时事件写入失败无告警

**文件：** `scripts/on-cc-event.sh:132-141`
**发现时间：** 2026-03-01T00:00:00Z
**状态：** 待修复

### 问题描述

```bash
jq -cn \
  --arg ts "$TS" \
  ... \
  >> "$EVENTS_FILE"
```

如果磁盘满或 `$EVENTS_FILE` 所在目录权限不足，`>>` 写入失败。由于 `set -euo pipefail`，脚本会 exit 1，但：
1. 事件被丢失（未记录）
2. 没有任何告警发送给 OpenClaw
3. Claude Code 可能将 Hook exit 1 显示为警告，但 OpenClaw 不会收到通知

### 修复方向

在写入前检查磁盘空间，写入失败时尝试发送告警通知：

```bash
if ! jq -cn ... >> "$EVENTS_FILE" 2>/dev/null; then
  log_error "Failed to write to events.ndjson (disk full or permission error)"
  # 尝试通知 OpenClaw（即使无法记录事件）
  _enqueue_notification "[cc-supervisor] CRITICAL: event logging failed for $EVENT_TYPE"
  exit 1
fi
```

---

## BUG-005 [P1] cc-start.sh Step 6：Claude Code 初始化等待时间硬编码

**文件：** `scripts/cc-start.sh:151-155`
**发现时间：** 2026-03-01T00:00:00Z
**状态：** 待修复

### 问题描述

```bash
echo "[6/7] Waiting 3s for Claude Code to initialize..."
sleep 3
```

`sleep 3` 是硬编码等待，在以下情况下不足：
- 慢速机器或高负载系统
- 首次运行需要下载/初始化
- 网络延迟导致 Claude Code 启动慢

如果 Claude Code 还未就绪就发送验证消息，消息可能被丢失或触发意外行为。

### 修复方向

主动轮询 tmux pane 内容，等待 Claude Code REPL 提示符出现（最多等待 15 秒）：

```bash
READY=false
for _i in $(seq 1 30); do
  sleep 0.5
  PANE="$(tmux capture-pane -t cc-supervise -p 2>/dev/null || true)"
  if echo "$PANE" | grep -qE "^\s*>|✓|claude>|Human:"; then
    READY=true; break
  fi
done
if [[ "$READY" == "false" ]]; then
  log_warn "Claude Code may not be ready yet, proceeding anyway"
fi
```

---

## BUG-006 [P2] SKILL.md：watchdog 第二次告警的处理未定义

**文件：** `SKILL.md:195`
**发现时间：** 2026-03-01T00:00:00Z
**状态：** 待修复（文档）

### 问题描述

```
- `⏰ watchdog` → `cc-capture --tail 60`; relay: forward; autonomous: `cc-send "Please continue"`, escalate if fires again
```

"escalate if fires again" 没有说明：
1. escalate 的消息格式
2. escalate 之后是否继续发送 `cc-send "Please continue"`
3. 第三次、第四次 watchdog 告警怎么处理

### 修复方向

在 SKILL.md 中补充 watchdog 多次触发的处理规则。

---

## BUG-007 [P2] SKILL.md：Phase 4 escalate 格式未定义

**文件：** `SKILL.md:200-206`
**发现时间：** 2026-03-01T00:00:00Z
**状态：** 待修复（文档）

### 问题描述

```
3. 若输出为空或只有错误 → 不报告完成，escalate to human
```

没有定义 escalate 的消息格式，OpenClaw 可能发送格式不一致的消息，human 难以快速判断情况。

### 修复方向

补充格式：`[cc-supervisor] Phase 4 verification failed: <reason> | Last output: <cc-capture --tail 10>`

---

## BUG-008 [P3] flush-queue.sh：无 OPENCLAW_SESSION_ID 时静默跳过而非报错

**文件：** `scripts/flush-queue.sh:27-32`
**发现时间：** 2026-03-01T00:00:00Z
**状态：** 待修复

### 问题描述

```bash
if openclaw agent \
    ${OPENCLAW_SESSION_ID:+--session-id "$OPENCLAW_SESSION_ID"} \
    --message "$msg" \
```

当 `OPENCLAW_SESSION_ID` 未设置时，`${OPENCLAW_SESSION_ID:+--session-id "$OPENCLAW_SESSION_ID"}` 展开为空，`openclaw agent` 在没有 `--session-id` 的情况下被调用。这可能：
1. 发送到错误的 session
2. 静默失败
3. 消耗队列中的消息但实际未送达

### 修复方向

在 flush 开始时检查 `OPENCLAW_SESSION_ID`：

```bash
if [[ -z "${OPENCLAW_SESSION_ID:-}" ]]; then
  log_warn "OPENCLAW_SESSION_ID not set — cannot flush (messages remain queued)"
  log_warn "Set it with: export OPENCLAW_SESSION_ID=<uuid>"
  exit 1
fi
```

---

## 验收标准

| Bug ID | 验收条件 |
|--------|---------|
| BUG-001 | `install-hooks.sh` 失败时 `cc-start` 立即打印 ERROR 并 exit 1 |
| BUG-002 | 传入不存在的目录时打印友好错误并 exit 1 |
| BUG-003 | `cc-start.sh` 使用 `set -euo pipefail` |
| BUG-004 | 写入失败时发送告警通知并 exit 1 |
| BUG-005 | 等待 Claude Code 就绪而非硬编码 sleep |
| BUG-006 | SKILL.md 中 watchdog 多次触发有明确处理规则 |
| BUG-007 | SKILL.md 中 Phase 4 escalate 有格式定义 |
| BUG-008 | flush-queue.sh 无 SESSION_ID 时报错退出 |

---

## 修复优先级排序

1. BUG-003（根本原因，修复后 BUG-001 部分自愈）
2. BUG-001（最高影响，静默失败）
3. BUG-002（用户体验，友好错误）
4. BUG-004（数据完整性）
5. BUG-005（可靠性）
6. BUG-008（正确性）
7. BUG-006（文档）
8. BUG-007（文档）
