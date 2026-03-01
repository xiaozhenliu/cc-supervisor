# 升级指南 - 自主决策规则更新

本指南说明如何将现有的 cc-supervisor skill 升级到包含新自主决策规则的版本。

---

## 版本变化

- **旧版本**: v0.7.1 - 自主模式决策规则模糊，agent 容易过度升级
- **新版本**: v0.7.2 - 完全自主决策规则，明确所有编程操作自动批准

---

## 主要改进

### 1. 自主决策规则完全重写

**旧行为**：
- 遇到"风险"操作（删除、权限、commit）会升级
- 决策规则模糊，agent 不确定时倾向于问人
- 安全相关操作需要人类确认

**新行为**：
- 所有编程操作自动批准（包括删除、权限、commit、push、API 调用）
- 默认答案是 `y`，只在真正卡住时升级
- 安全通过沙箱保证，不通过交互确认

### 2. 触发规则加强

**旧行为**：
- 触发规则描述性，agent 可能忘记使用 skill

**新行为**：
- 触发规则强制性，使用 "MANDATORY"、"MUST"、"IMMEDIATELY"
- 明确说明不使用 skill 会失败
- 优先级高于默认 agent 行为

### 3. 新增文档

- `docs/AUTONOMOUS_DECISION_RULES.md` - 完整英文决策规则
- `docs/自主决策规则总结.md` - 中文快速参考

---

## 升级步骤

### 方案 A：已通过 ClawHub 安装

如果你是通过 `clawhub install cc-supervisor` 安装的：

```bash
# 1. 更新 skill
clawhub update cc-supervisor

# 2. 验证版本
cat ~/.openclaw/skills/cc-supervisor/SKILL.md | grep "version:"
# 应该显示: version: 0.7.2

# 3. 重新加载 shell 配置（如果有更新）
source ~/.zshrc
```

### 方案 B：手动 git clone 安装

如果你是手动 clone 到 `~/.openclaw/skills/cc-supervisor/` 的：

```bash
# 1. 进入 skill 目录
cd ~/.openclaw/skills/cc-supervisor

# 2. 拉取最新代码
git pull origin main

# 3. 验证版本
cat SKILL.md | grep "version:"
# 应该显示: version: 0.7.2

# 4. 检查新文档是否存在
ls -la docs/AUTONOMOUS_DECISION_RULES.md
ls -la docs/自主决策规则总结.md
```

### 方案 C：本地开发版本

如果你正在本地开发这个项目：

```bash
# 1. 确保在项目根目录
cd /path/to/cc-supervisor

# 2. 提交当前更改
git add .
git commit -m "feat: add comprehensive auto decision rules (v0.7.2)"

# 3. 如果需要推送到远程
git push origin main

# 4. 如果已安装到 ~/.openclaw/skills/，更新安装版本
cd ~/.openclaw/skills/cc-supervisor
git pull origin main
```

---

## 验证升级

### 1. 检查文件完整性

```bash
cd ~/.openclaw/skills/cc-supervisor

# 检查关键文件是否存在
ls -la SKILL.md
ls -la docs/AUTONOMOUS_DECISION_RULES.md
ls -la docs/自主决策规则总结.md

# 检查 SKILL.md 版本
grep "version:" SKILL.md
# 应该显示: version: 0.7.2

# 检查触发规则是否更新
grep "MANDATORY" SKILL.md
# 应该有输出
```

### 2. 测试触发规则

启动一个新的 OpenClaw 会话，测试 skill 是否正确触发：

```bash
# 测试 1: 明确请求
openclaw agent --message "请使用 Claude Code 实现一个简单的 web 服务器"
# agent 应该立即调用 cc-supervisor skill

# 测试 2: Hook 通知触发
openclaw agent --message "[cc-supervisor][Stop] Task completed"
# agent 应该立即调用 cc-supervisor skill
```

### 3. 测试自主决策

在 auto 模式下测试决策行为：

```bash
# 启动自主模式监督
OPENCLAW_SESSION_ID=<your-session-id> \
  CC_MODE=auto \
  cc-supervise /path/to/test-project

# 发送一个会触发多个确认的任务
cc-send "创建一个 React 项目，安装依赖，创建组件，运行测试，提交代码"

# 观察 agent 是否自动批准所有操作，不停下来问人
```

---

## 回滚步骤

如果升级后遇到问题，可以回滚到旧版本：

```bash
cd ~/.openclaw/skills/cc-supervisor

# 查看提交历史
git log --oneline

# 回滚到 v0.7.1
git checkout <v0.7.1-commit-hash>

# 或者回滚到上一个版本
git checkout HEAD~1
```

---

## 常见问题

### Q: 升级后 agent 还是会停下来问人？

**A**: 检查以下几点：

1. 确认版本是 v0.7.2：
   ```bash
   cat ~/.openclaw/skills/cc-supervisor/SKILL.md | grep "version:"
   ```

2. 确认使用了 auto 模式：
   ```bash
   # 启动时必须设置 CC_MODE=auto
   CC_MODE=auto cc-supervise /path/to/project
   ```

3. 确认 agent 读取了新的决策规则：
   - 在 agent 日志中查找 "AUTONOMOUS_DECISION_RULES.md"
   - 确认 agent 在处理 Stop 事件时引用了新规则

### Q: 如何确认 agent 使用了 skill？

**A**: 在 agent 响应中查找：

- 应该看到 skill 调用：`Skill: cc-supervisor`
- 应该看到 Phase 0-6 的执行流程
- 不应该看到 agent 尝试手动监督 Claude Code

### Q: 触发规则更新后，agent 还是忘记使用 skill？

**A**: 这可能是 OpenClaw 缓存问题：

1. 重启 OpenClaw agent
2. 清除 skill 缓存（如果有）
3. 在请求中明确提到 "使用 cc-supervisor skill"

### Q: 自主模式下，agent 在什么情况下会升级？

**A**: 只在以下情况升级（极少）：

- 缺少真实外部信息（生产环境 API 密钥）
- 同一错误重复 3 次
- 系统级问题（硬件故障、OS 错误）
- 任务目标不明确

所有编程操作（创建/删除文件、安装依赖、commit、push）都自动批准。

---

## 技术支持

如果遇到问题：

1. 查看 `docs/AUTONOMOUS_DECISION_RULES.md` 了解完整决策规则
2. 查看 `docs/自主决策规则总结.md` 了解快速参考
3. 查看 `logs/events.ndjson` 了解 Hook 事件历史
4. 在 GitHub 提交 issue: https://github.com/anthropics/claude-code/issues

---

## 更新日志

### v0.7.2 (2026-02-28)

**新增**：
- 完整的自主决策规则文档（英文 + 中文）
- 强制性触发规则，防止 agent 忘记使用 skill
- 明确的升级条件和自动批准操作列表

**改进**：
- 自主模式默认答案改为 `y`（所有编程操作自动批准）
- 移除不必要的"安全"升级条件
- 轮次限制从 20 提高到 30
- 连续 "Please continue" 限制从 5 提高到 8
- Watchdog 触发限制从 2 提高到 3

**文档**：
- `docs/AUTONOMOUS_DECISION_RULES.md` - 完整英文决策规则
- `docs/自主决策规则总结.md` - 中文快速参考
- `docs/UPGRADE_GUIDE.md` - 本升级指南

---

版本：v0.7.2 (2026-02-28)
