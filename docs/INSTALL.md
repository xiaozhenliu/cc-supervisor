# 安装指南

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/cc-supervisor/main/install.sh | bash
```

或者克隆后本地安装：

```bash
git clone https://github.com/OWNER/cc-supervisor
bash cc-supervisor/install.sh
```

## 安装选项

```bash
# 预览模式（不做任何修改）
bash install.sh --dry-run

# 查看帮助
bash install.sh --help
```

## 前置条件

install.sh 会自动检测以下工具是否已安装，缺失时给出安装提示：

| 工具 | macOS | Linux (apt) | Linux (yum) |
|------|-------|-------------|-------------|
| `tmux` | `brew install tmux` | `sudo apt-get install -y tmux` | `sudo yum install -y tmux` |
| `jq` | `brew install jq` | `sudo apt-get install -y jq` | `sudo yum install -y jq` |
| `claude` | [Anthropic 文档](https://docs.anthropic.com/claude-code) | 同左 | 同左 |
| `openclaw` | [OpenClaw 文档](https://openclaw.ai/docs/install) | 同左 | 同左 |

> Linux 上 install.sh **不会自动执行 sudo 命令**，仅打印提示，由用户手动安装。

## 安装内容

install.sh 完成以下操作：

1. 检测前置条件（缺失则 exit 1，不破坏已有安装）
2. 将 skill 文件安装到 `~/.openclaw/skills/cc-supervisor/`
   - git 可用：`git clone --depth=1`
   - git 不可用：`curl` 下载 tarball 解压
   - 目录已存在：交互式询问覆盖；pipe 调用直接 rsync 更新
3. 向 `~/.zshrc` 或 `~/.bashrc` 注入 shell 别名（幂等，不重复追加）
4. 打印 `source` 命令和后续步骤

## 安装后

```bash
# 重新加载 shell 配置
source ~/.zshrc   # 或 ~/.bashrc

# 验证别名可用
type cc-supervise

# 为目标项目注册 Hooks（每个项目只需一次）
cc-install-hooks ~/Projects/my-app

# 启动监督
cc-supervise ~/Projects/my-app
```

## 幂等性

install.sh 可以安全地重复执行：

- 别名块通过唯一标记行 `# cc-supervisor aliases — managed by install.sh` 检测，不会重复追加
- 目录已存在时，交互模式询问确认，pipe 模式直接 rsync 更新

验证：

```bash
bash install.sh
bash install.sh  # 第二次不应重复追加别名
grep -c "cc-supervisor aliases" ~/.zshrc  # 应输出 1
```

## Channel 配置

通知 channel 通过环境变量控制：

```bash
# Discord（默认）
export OPENCLAW_CHANNEL=discord

# 飞书（占位实现，当前入队等待）
export OPENCLAW_CHANNEL=feishu
export FEISHU_WEBHOOK_URL=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
```

## 卸载

```bash
# 移除 skill 文件
rm -rf ~/.openclaw/skills/cc-supervisor

# 手动从 ~/.zshrc 删除别名块
# 删除从 "# cc-supervisor aliases" 到 "# end cc-supervisor aliases" 的内容
```
