# BUG-009: cc_send.sh --key 模式功能键被当作文本发送

- **日期:** 2026-03-01
- **严重程度:** P0 — 致命
- **影响范围:** cc_send.sh, SKILL.md, docs/SCRIPTS.md
- **修复版本:** v1.7.0

## 现象

当通过 `cc_send.sh --key Esc` 发送 Escape 键时，tmux 终端中出现的是字面文字 "Esc"（三个字符 E、s、c），而非实际的 Escape 按键（0x1B）。

同类问题影响所有常见按键别名：`Return`、`Backspace`、`Delete` 等。

组合修饰键同样受影响：`Ctrl+c`、`Alt+x` 等人类常用写法不被 tmux 识别（tmux 要求 `C-c`、`M-x`），会被逐字符发送。

## 根本原因

### 直接原因

`cc_send.sh` key 模式将 `$INPUT` 直接传递给 `tmux send-keys`：

```bash
tmux send-keys -t "$SESSION_NAME" "$INPUT"
```

tmux `send-keys` 只识别特定的键名（如 `Escape`、`Enter`、`BSpace`）。当传入不被识别的名称（如 `Esc`），tmux 将其拆解为单个字符逐一发送。

### 别名映射缺失

| 用户输入 | tmux 要求 | 实际行为 |
|---------|----------|---------|
| `Esc` | `Escape` | 发送 "E" "s" "c" |
| `Return` | `Enter` | 发送 "R" "e" "t" "u" "r" "n" |
| `Backspace` | `BSpace` | 发送 "B" "a" "c" "k" ... |
| `Delete` / `Del` | `DC` | 发送 "D" "e" "l" ... |
| `Ctrl+c` | `C-c` | 发送 "C" "t" "r" "l" "+" "c" |
| `Alt+x` | `M-x` | 发送 "A" "l" "t" "+" "x" |

### 文档缺失加剧问题

1. **SKILL.md** cc-send 参考仅列出 `--key y`、`--key Up`、`--key Enter`，未提及 `--key Escape`
2. **docs/SCRIPTS.md** cc_send.sh 章节完全没有记录 `--key` 模式
3. LLM agent 按照 SKILL.md 行事时，没有明确指导如何发送 Escape 键，可能尝试 `cc-send "Escape"`（文本模式）或 `cc-send --key Esc`（无效别名）

## 复现步骤

```bash
# 前置：启动 tmux session
tmux new-session -d -s test-keys

# 错误：发送 "Esc" 别名
./scripts/cc_send.sh --key Esc
tmux capture-pane -t test-keys -p | tail -1
# 输出: "Esc"（字面文字，非 Escape 按键）

# 正确：发送 tmux 认可的 "Escape"
./scripts/cc_send.sh --key Escape
# 终端收到实际 Escape 按键

tmux kill-session -t test-keys
```

## 修复方案

1. **cc_send.sh** — key 模式添加 `normalize_key()` 规范化函数：
   - 独立键别名：`Esc`→`Escape`、`Return`→`Enter`、`Backspace`/`BS`→`BSpace`、`Delete`/`Del`→`DC`
   - 组合修饰键：`Ctrl+c`→`C-c`、`Alt+x`→`M-x`、`Ctrl+Shift+u`→`C-S-u`（支持 `+` 和 `-` 分隔、任意大小写）
   - 已是 tmux 格式的（如 `C-c`）：直接透传

2. **SKILL.md** — cc-send 参考补充 `--key Escape`、`--key Ctrl+c`，列出所有支持的键名和修饰键语法

3. **docs/SCRIPTS.md** — cc_send.sh 章节添加 `--key` 模式文档，含修饰键说明

## 验收标准

- [ ] `cc_send.sh --key Esc` 发送实际 Escape 按键（0x1B）
- [ ] `cc_send.sh --key Return` 发送实际 Enter 按键
- [ ] `cc_send.sh --key Backspace` 发送实际退格按键
- [ ] `cc_send.sh --key Delete` 发送实际删除按键
- [ ] `cc_send.sh --key Ctrl+c` 发送实际 Ctrl+C（规范化为 `C-c`）
- [ ] `cc_send.sh --key Alt+x` 发送实际 Alt+X（规范化为 `M-x`）
- [ ] `cc_send.sh --key Ctrl+Shift+u` 发送实际 Ctrl+Shift+U（规范化为 `C-S-u`）
- [ ] SKILL.md 包含 `Escape` 和修饰键组合的使用说明
- [ ] docs/SCRIPTS.md 包含 `--key` 模式完整文档（含修饰键）
