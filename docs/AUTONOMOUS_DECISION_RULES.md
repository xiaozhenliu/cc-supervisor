# 自主决策规则（Autonomous Mode Decision Rules）

本文档定义 `CC_MODE=autonomous` 模式下 OpenClaw Agent 的自主决策规则。目标是让 agent 能够完全自主地推进任务，只在真正无法继续的情况下才升级。

---

## 核心原则

1. **完全自主**：所有编程相关的决策都自动完成，不问人
2. **默认推进**：遇到任何选择，优先选择让任务继续推进的选项
3. **信任 Claude Code**：Claude Code 提出的操作都是为了完成任务，直接批准
4. **失败可重试**：如果决策错误，可以通过后续操作修正，不需要提前确认
5. **只在卡住时升级**：只有在真正无法继续（需要外部信息、无法解决的错误）时才升级

**关键理念**：安全问题通过沙箱、备份、版本控制等机制解决，不通过交互确认解决。在自主模式下，人类已经选择完全信任 agent，agent 应该大胆执行。

---

## Stop 事件分类决策规则

### 1. Task Complete（任务完成）

**识别标准**：
- 输出明确表示"任务完成"、"所有工作已完成"、"没有待办项"
- 输出包含总结性语句，列出了完成的所有内容
- 没有任何待办事项或后续问题

**决策**：
- 自动进入 Phase 6（验证和报告）
- 通知人类任务完成

**无需升级**

---

### 2. Yes/No Confirmation（是/否确认）

**识别标准**：
- 输出末尾有明确的二选一问题
- 可能的格式：
  - `(y/n)` 或 `(yes/no)`
  - `1) Yes 2) No` 或 `1) Continue 2) Abort`
  - `a) Approve b) Reject`
  - 任何其他二选一的确认格式

**决策规则**：

**第一步：解析提示格式**
- 识别可用的选项（y/n, 1/2, a/b, yes/no, continue/abort 等）
- 判断哪个选项代表"同意/继续/批准"
- 判断哪个选项代表"拒绝/取消/中止"

**第二步：选择正确的选项**

所有编程相关的操作都选择"同意/继续"选项：

| 提示格式示例 | 应发送 | 说明 |
|------------|--------|------|
| `Continue? (y/n)` | `y` | y 代表 yes/继续 |
| `Proceed? (yes/no)` | `yes` | yes 代表同意 |
| `1) Continue 2) Abort` | `1` | 1 代表继续 |
| `1) Abort 2) Continue` | `2` | 2 代表继续 |
| `a) Approve b) Reject` | `a` | a 代表批准 |
| `Select: [Y/n]` | `Y` | Y 代表 yes（大写是默认） |
| `Overwrite? (y/n)` | `y` | y 代表同意覆盖 |
| `Delete file? (y/n)` | `y` | y 代表同意删除 |
| `Commit changes? (y/n)` | `y` | y 代表同意提交 |
| `Push to remote? (y/n)` | `y` | y 代表同意推送 |

**唯一例外**：
- 如果问题明确是"是否放弃/取消/停止当前任务"，选择"不放弃"选项
  - `Abort task? (y/n)` → `n`
  - `1) Continue 2) Abort` → `1`

**第三步：使用正确的 cc-send 命令**

根据选项格式使用对应的命令：
- 单字符选项（y, n, 1, 2, a, b）：`cc-send --key <字符>`
- 完整单词（yes, no, continue, abort）：`cc-send "<单词>"`

**示例**：
```bash
# 提示: Continue? (y/n)
cc-send --key y

# 提示: Proceed? (yes/no)
cc-send "yes"

# 提示: 1) Continue 2) Abort
cc-send --key 1

# 提示: Select: [Y/n]
cc-send --key Y
```

**理由**：
- 在自主模式下，人类已经选择信任 agent 完成任务
- 所有操作都是为了完成任务目标
- 文件系统有版本控制（git）保护
- 依赖安装是可逆的
- 外部 API 调用是任务必需的
- 安全问题通过沙箱环境解决，不通过交互确认

**无需升级**

---

### 3. Multiple Choice（多项选择）

**识别标准**：
- 输出列出多个选项（通常 2 个以上）
- 选项通常有编号或字母标识
- 格式示例：
  - `1) Option A  2) Option B  3) Option C`
  - `a. First choice  b. Second choice  c. Third choice`
  - `[1] React  [2] Vue  [3] Angular`

**决策规则**：

**第一步：解析所有选项**
- 识别选项的编号/字母（1, 2, 3 或 a, b, c）
- 提取每个选项的描述文本
- 识别是否有标注（recommended, default, suggested）

**第二步：按优先级选择**

1. **检查是否有推荐选项**：
   - 选项中标注 "recommended"、"default"、"suggested"、"(default)" → 选择它
   - 示例：`1) TypeScript (recommended)  2) JavaScript` → 选择 `1`

2. **检查任务描述**：
   - 任务描述中明确提到的技术栈/工具 → 选择它
   - 示例：任务说"用 React 实现"，选项有 React → 选择 React

3. **选择代表"继续/推进"的选项**：
   - 如果选项是"继续 vs 中止"类型 → 选择"继续"
   - 示例：`1) Continue  2) Skip  3) Abort` → 选择 `1`

4. **选择最流行/稳定的选项**：
   - 技术栈：React > Vue > Angular
   - 包管理器：npm > yarn > pnpm
   - 测试框架：Jest > Vitest > Mocha
   - 数据库：PostgreSQL > MySQL > SQLite
   - 语言：TypeScript > JavaScript

5. **选择最保守/安全的选项**：
   - 安装位置：Local > Global
   - 配置方式：Manual > Automatic（如果涉及重要配置）
   - 更新策略：Minor updates > Major updates

6. **选择第一个选项**：
   - 如果以上规则都无法判断，选择第一个选项

**第三步：发送对应的选项**

使用 `cc-send --key <编号/字母>` 发送选择：

```bash
# 提示: 1) TypeScript  2) JavaScript
cc-send --key 1

# 提示: a. React  b. Vue  c. Angular
cc-send --key a

# 提示: [1] Continue  [2] Abort
cc-send --key 1
```

**示例决策**：

```
提示: Choose a framework:
  1) React (recommended)
  2) Vue
  3) Angular
决策: cc-send --key 1
理由: 有 recommended 标注

提示: Install location:
  1) Local (project-specific)
  2) Global (system-wide)
决策: cc-send --key 1
理由: 本地安装更安全

提示: What to do with existing file?
  1) Overwrite
  2) Create backup
  3) Skip
决策: cc-send --key 1
理由: 直接覆盖，版本控制会保护

提示: Select database:
  1) SQLite
  2) PostgreSQL
  3) MySQL
决策: cc-send --key 2
理由: PostgreSQL 更稳定强大

提示: Next step:
  1) Continue with tests
  2) Skip tests
  3) Abort
决策: cc-send --key 1
理由: 选择继续推进的选项
```

**无需升级**

---

### 4. Cursor Navigation（光标导航）

**识别标准**：
- 输出显示一个菜单或列表
- 需要用方向键移动光标选择

**决策规则**：
- 按照多项选择的规则选择目标项
- 使用 `cc-send --key Up/Down` 导航到目标
- 使用 `cc-send --key Enter` 确认

**无需升级**

---

### 5. Open Question（开放性问题）

**识别标准**：
- 输出提出一个需要具体信息的问题
- 不是 yes/no，也不是多选

**决策规则**：

| 问题类型 | 决策 | 示例 |
|---------|------|------|
| 项目名称 | 从任务描述中提取，或生成描述性名称 | "quantum-demo"、"user-auth-system" |
| 文件路径 | 基于项目结构推断标准路径 | `src/components/`、`tests/` |
| 端口号 | 使用常见默认值 | 3000, 8080, 5000, 8000 |
| 依赖版本 | 使用 "latest" 或不指定版本 | `"react": "latest"` |
| 配置参数 | 使用合理默认值 | timeout: 30000, maxRetries: 3 |
| 颜色/样式 | 使用中性/专业配色 | 蓝色系、灰色系 |
| 数据库名称 | 基于项目名称生成 | `projectname_db` |
| API endpoint | 遵循 RESTful 约定 | `/api/users`, `/api/posts` |
| 变量/函数名 | 遵循语言约定 | camelCase (JS), snake_case (Python) |
| 用户名/密码（开发环境） | 使用标准测试值 | admin/admin, test/test123 |
| 业务逻辑细节 | 基于常见实践推断 | 用户认证用 JWT，分页默认 20 条 |

**决策流程**：
1. 检查任务描述中是否已提供答案 → 使用它
2. 检查项目现有文件中是否有类似配置 → 参考它
3. 使用行业标准实践或合理默认值
4. 如果是技术实现细节，自主决定
5. **只有在缺少关键外部信息时才升级**（如 API 密钥、生产环境配置）

**升级条件**（极少）：
- 需要真实的 API 密钥/凭证（生产环境）
- 需要连接到真实的外部服务（生产数据库地址）
- 需要人类提供的特定业务数据（真实用户列表、产品价格）

**无需升级的情况**：
- 开发环境的配置（使用 mock 数据）
- 技术实现细节（代码结构、算法选择）
- 样式和 UI 细节（颜色、布局）
- 测试数据（使用假数据）

---

### 6. Blocked（遇到阻塞）

**识别标准**：
- 输出报告错误
- 输出表明权限不足
- 输出表明无法继续

**决策规则**：

| 阻塞类型 | 第一次遇到 | 第二次遇到 | 第三次遇到 |
|---------|-----------|-----------|-----------|
| 文件不存在 | 创建文件或调整路径 | 检查路径拼写，重试 | 升级 |
| 依赖缺失 | 安装依赖 | 检查依赖名称，重试 | 升级 |
| 语法错误 | 修复语法 | 重新检查代码，修复 | 升级 |
| 类型错误 | 修复类型 | 添加类型转换 | 升级 |
| 权限错误 | 修改权限（chmod/chown） | 使用 sudo 重试 | 升级 |
| 网络错误 | 重试一次 | 检查 URL，重试 | 升级 |
| API 错误 | 检查调用方式并修正 | 查看文档，调整参数 | 升级 |
| 配置错误 | 修正配置 | 重新生成配置 | 升级 |
| 端口占用 | 换一个端口 | 杀掉占用进程 | 升级 |
| 磁盘空间不足 | 清理临时文件 | 升级 | — |

**自修复策略**：
- 每种错误最多尝试 2 次修复
- 第 3 次遇到同一错误 → 升级
- 不要尝试过于复杂的修复，保持简单直接

**立即升级的阻塞**（极少）：
- 系统级错误（内核错误、硬件故障）
- 外部服务完全不可用（GitHub down、npm registry down）
- 需要人类提供的信息（真实的 API 密钥）

---

### 7. In Progress（进行中）

**识别标准**：
- 输出描述正在进行的工作
- 没有提出问题
- 没有报告错误
- 没有表示完成

**决策**：
- 发送 `cc-send "Please continue."`
- 不通知人类

**无需升级**

---

## 升级决策规则

### 必须升级的情况（极少）

1. **缺少关键外部信息**：
   - 真实的 API 密钥/凭证（生产环境）
   - 真实的外部服务地址（生产数据库、第三方 API）
   - 人类才知道的业务数据

2. **重复失败无法解决**：
   - 同一错误出现 3 次
   - 尝试了所有可能的修复方案仍然失败

3. **系统级问题**：
   - 硬件故障
   - 操作系统错误
   - 外部服务完全不可用

4. **任务目标不明确**：
   - 任务描述过于模糊，无法推断意图
   - 存在多种完全不同的实现方向

### 不应该升级的情况（大多数）

1. **所有编程操作**：
   - 创建/修改/删除文件
   - 安装/卸载依赖
   - 修改配置
   - 运行测试
   - 提交/推送代码

2. **技术决策**：
   - 选择技术栈
   - 选择架构模式
   - 选择算法实现
   - 选择代码结构

3. **可恢复的错误**：
   - 语法错误（可以修复）
   - 类型错误（可以修复）
   - 配置错误（可以修正）
   - 依赖问题（可以重新安装）

4. **开发环境配置**：
   - 端口号
   - 数据库名称
   - 测试数据
   - Mock 配置

---

## 轮次限制

为避免无限循环，设置以下限制：

| 情况 | 限制 | 超出后动作 |
|------|------|-----------|
| 总轮次 | 30 轮 | 升级，报告进度和剩余工作 |
| 连续 "Please continue" | 8 次 | 升级，可能卡在长时间操作 |
| 连续自修复 | 3 次（同一错误） | 升级，修复策略无效 |
| Watchdog 触发 | 3 次 | 升级，任务可能无法完成 |

---

## 升级消息格式

当需要升级时，发送给人类的消息应简洁明确：

```
[cc-supervisor][autonomous] Escalation required:

Type: <Stop 类型>
Reason: <为什么需要升级>
Rounds: <已完成轮次>
Progress: <已完成的工作>
Remaining: <剩余工作>
Blocker: <具体的阻塞问题>

Claude Code output:
<实际输出>

What I need:
<需要人类提供的具体信息>
```

示例：
```
[cc-supervisor][autonomous] Escalation required:

Type: Open Question
Reason: Requires production API credentials
Rounds: 12
Progress: Built authentication system, created user database, implemented JWT
Remaining: Connect to production email service
Blocker: Need SendGrid API key for production email sending

Claude Code output:
I need a SendGrid API key to send verification emails.
Please provide the API key or set it in the .env file.

What I need:
SendGrid API key for production environment
```

---

## 决策记录格式

每次自主决策后，agent 应在内部记录（不发送给人类）：

```
[autonomous-decision]
Round: <轮次>
Type: <Stop 类型>
Question: <Claude Code 的问题>
Decision: <做出的决策>
Reason: <决策理由>
```

示例：
```
[autonomous-decision]
Round: 5
Type: Yes/No Confirmation
Question: "Delete old migration files? (y/n)"
Decision: y
Reason: Cleaning up old files is part of task progression, git will preserve history
```

---

## 实施检查清单

Agent 在 autonomous 模式下收到 Stop 通知时，应按以下流程处理：

1. ✅ 分类 Stop 类型
2. ✅ 按决策规则自动做出决策（不考虑"风险"）
3. ✅ 记录决策（内部）
4. ✅ 执行 `cc-send` 命令
5. ✅ 更新轮次计数器
6. ✅ 检查是否超出轮次限制
7. ✅ 只在真正无法继续时才升级
8. ✅ 等待下一个通知

---

## 关键要点总结

1. **默认答案是 `y`**：所有 yes/no 问题都回答 `y`，除非是"是否放弃任务"
2. **选择推荐选项**：多选题选择 recommended/default/第一个选项
3. **使用合理默认值**：开放性问题使用标准实践和合理默认值
4. **自动修复错误**：遇到错误先尝试修复，同一错误 3 次才升级
5. **持续推进**：进行中状态发送 "Please continue."
6. **极少升级**：只在缺少外部信息、重复失败、系统级问题时升级
7. **不考虑"安全风险"**：所有编程操作都自动批准，安全通过沙箱保证

---

## 版本历史

- v1.0 (2026-02-28): 初始版本
- v1.1 (2026-02-28): 修改为完全自主模式，移除不必要的升级条件

---

## Stop 事件分类决策规则

### 1. Task Complete（任务完成）

**识别标准**：
- 输出明确表示"任务完成"、"所有工作已完成"、"没有待办项"
- 输出包含总结性语句，列出了完成的所有内容
- 没有任何待办事项或后续问题

**决策**：
- 自动进入 Phase 6（验证和报告）
- 通知人类任务完成

**无需升级**

---

### 2. Yes/No Confirmation（是/否确认）

**识别标准**：
- 输出末尾有明确的 yes/no 问题
- 或者是二选一的确认问题（如 "Continue? (y/n)"）

**决策规则**：

| 问题类型 | 决策 | 理由 |
|---------|------|------|
| 是否继续当前操作 | `y` | 默认推进原则 |
| 是否创建/修改文件 | `y` | 文件操作可恢复 |
| 是否安装依赖 | `y` | 依赖安装是任务推进必需 |
| 是否运行测试 | `y` | 测试是验证必需 |
| 是否提交代码 | `n` → 升级 | 涉及版本控制，需人类确认 |
| 是否删除文件/目录 | `n` → 升级 | 数据删除不可逆 |
| 是否授予权限 | `n` → 升级 | 安全相关，需人类确认 |
| 是否调用外部 API | `n` → 升级 | 可能产生费用或副作用 |
| 是否覆盖现有配置 | 查看内容 → 决策 | 如果是临时配置则 `y`，如果是关键配置则升级 |

**默认规则**：
- 如果问题是"是否继续"类型，且不涉及上述高风险操作 → `y`
- 如果无法判断风险级别 → 升级

---

### 3. Multiple Choice（多项选择）

**识别标准**：
- 输出列出编号选项（1, 2, 3...）
- 要求选择其中一个

**决策规则**：

| 选择类型 | 决策 | 理由 |
|---------|------|------|
| 技术栈选择（框架/库） | 选择最流行/稳定的选项 | 基于生态成熟度 |
| 配置选项 | 选择默认/推荐选项 | 通常标注为 "recommended" 或排在第一位 |
| 错误处理方式 | 选择最保守的选项 | 避免数据丢失 |
| 文件位置选择 | 选择符合项目结构的选项 | 基于现有目录结构 |
| 版本选择 | 选择最新稳定版 | 除非任务明确要求特定版本 |

**决策流程**：
1. 检查选项中是否有标注 "recommended"、"default"、"suggested" → 选择它
2. 检查任务描述中是否有相关偏好 → 按偏好选择
3. 选择最保守/最安全的选项
4. 如果所有选项风险相当且无明确偏好 → 选择第一个选项

**升级条件**：
- 选项涉及不可逆操作（如数据迁移方式）
- 选项会显著影响项目架构
- 无法判断哪个选项更合适

---

### 4. Cursor Navigation（光标导航）

**识别标准**：
- 输出显示一个菜单或列表
- 需要用方向键移动光标选择

**决策规则**：
- 按照多项选择的规则选择目标项
- 使用 `cc-send --key Up/Down` 导航到目标
- 使用 `cc-send --key Enter` 确认

**无需升级**（除非选择本身需要升级）

---

### 5. Open Question（开放性问题）

**识别标准**：
- 输出提出一个需要具体信息的问题
- 不是 yes/no，也不是多选

**决策规则**：

| 问题类型 | 决策 | 理由 |
|---------|------|------|
| 项目名称 | 从任务描述中提取或生成合理名称 | 可后续修改 |
| 文件路径 | 基于项目结构推断合理路径 | 遵循现有约定 |
| 端口号 | 使用常见默认值（3000, 8080 等） | 标准实践 |
| 依赖版本 | 使用 "latest" 或不指定 | 让包管理器决定 |
| 配置参数 | 使用合理默认值 | 可后续调整 |
| 用户偏好（颜色/样式） | 使用中性/通用选择 | 避免主观判断 |
| 业务逻辑细节 | 升级 | 需要领域知识 |
| 数据格式/Schema | 升级 | 影响数据结构 |
| API 密钥/凭证 | 升级 | 安全相关 |

**决策流程**：
1. 检查任务描述中是否已提供答案 → 使用它
2. 检查项目现有文件中是否有类似配置 → 参考它
3. 如果是技术性问题且有标准实践 → 使用标准实践
4. 如果是业务性问题或需要领域知识 → 升级

---

### 6. Blocked（遇到阻塞）

**识别标准**：
- 输出报告错误
- 输出表明权限不足
- 输出表明无法继续

**决策规则**：

| 阻塞类型 | 第一次遇到 | 第二次遇到 |
|---------|-----------|-----------|
| 文件不存在 | 创建文件或调整路径 | 升级 |
| 依赖缺失 | 安装依赖 | 升级 |
| 语法错误 | 修复语法 | 升级 |
| 类型错误 | 修复类型 | 升级 |
| 权限错误 | 升级 | — |
| 网络错误 | 重试一次 | 升级 |
| API 错误 | 检查调用方式并修正 | 升级 |
| 配置错误 | 修正配置 | 升级 |

**自修复策略**：
- 尝试最直接的修复方式
- 不要尝试多种方案，只尝试一次
- 如果同一错误出现第二次 → 立即升级

**立即升级的阻塞**：
- 权限/认证问题
- 外部服务不可用
- 磁盘空间不足
- 系统级错误

---

### 7. In Progress（进行中）

**识别标准**：
- 输出描述正在进行的工作
- 没有提出问题
- 没有报告错误
- 没有表示完成

**决策**：
- 发送 `cc-send "Please continue."`
- 不通知人类

**无需升级**

---

## 升级决策规则

### 必须升级的情况

1. **安全相关**：
   - 删除文件/目录
   - 授予权限
   - 修改安全配置
   - 处理凭证/密钥

2. **不可逆操作**：
   - 数据迁移
   - 数据库 schema 变更
   - 版本控制操作（commit, push, merge）
   - 生产环境部署

3. **业务决策**：
   - 需要领域知识的问题
   - 影响产品功能的选择
   - 用户体验相关的决策

4. **重复失败**：
   - 同一错误出现第二次
   - 自修复失败

5. **超出范围**：
   - 任务描述中未提及的新需求
   - 需要访问外部资源
   - 需要人类提供信息

### 可以自主决策的情况

1. **技术实现细节**：
   - 代码结构
   - 变量命名
   - 文件组织

2. **标准实践**：
   - 使用常见默认值
   - 遵循项目现有约定
   - 应用行业最佳实践

3. **可恢复操作**：
   - 创建/修改文件
   - 安装依赖
   - 运行测试
   - 代码重构

4. **推进任务**：
   - 继续当前操作
   - 执行下一步
   - 完成剩余工作

---

## 决策记录格式

每次自主决策后，agent 应在内部记录（不发送给人类）：

```
[autonomous-decision]
Type: <Stop 类型>
Question: <Claude Code 的问题>
Decision: <做出的决策>
Reason: <决策理由>
Risk: <low|medium|high>
```

示例：
```
[autonomous-decision]
Type: Yes/No Confirmation
Question: "Continue with npm install? (y/n)"
Decision: y
Reason: Installing dependencies is necessary for task progression and is reversible
Risk: low
```

---

## 轮次限制

为避免无限循环，设置以下限制：

| 情况 | 限制 | 超出后动作 |
|------|------|-----------|
| 总轮次 | 20 轮 | 升级，报告进度 |
| 连续 "Please continue" | 5 次 | 升级，可能卡住 |
| 连续自修复 | 3 次 | 升级，修复策略无效 |
| Watchdog 触发 | 2 次 | 升级，任务可能无法完成 |

---

## 升级消息格式

当需要升级时，发送给人类的消息应简洁明确：

```
[cc-supervisor][autonomous] Escalation required:

Type: <Stop 类型>
Reason: <为什么需要升级>
Context: <当前任务进度>
Question: <需要人类回答的具体问题>

Claude Code output:
<实际输出>
```

示例：
```
[cc-supervisor][autonomous] Escalation required:

Type: Open Question
Reason: Requires business decision
Context: Building user authentication, 15 rounds completed
Question: Should we use OAuth or JWT for authentication?

Claude Code output:
I can implement authentication using either OAuth 2.0 or JWT tokens.
Which approach would you prefer for this project?
```

---

## 实施检查清单

Agent 在 autonomous 模式下收到 Stop 通知时，应按以下流程处理：

1. ✅ 分类 Stop 类型
2. ✅ 检查是否属于"必须升级"的情况
3. ✅ 如果不需要升级，按决策规则做出决策
4. ✅ 记录决策（内部）
5. ✅ 执行 `cc-send` 命令
6. ✅ 更新轮次计数器
7. ✅ 检查是否超出轮次限制
8. ✅ 等待下一个通知

---

## 版本历史

- v1.0 (2026-02-28): 初始版本，定义自主决策规则
