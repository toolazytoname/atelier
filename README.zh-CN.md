<!-- markdownlint-disable MD041 first-line-h1 -->
<p align="center">
  <a href="README.md">
    <img src="assets/banner.svg" alt="atelier — a Linux dev sandbox for Claude Code" width="820">
  </a>
</p>

<p align="center">
  <strong>macOS + Claude Code，隔离在一个 Linux 虚拟机里。宿主机保持干净。</strong>
</p>

<p align="center">
  <a href="README.md">English</a>
  ·
  <a href="README.zh-CN.md"><b>中文</b></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://orbstack.dev"><img src="https://img.shields.io/badge/VM-OrbStack-blueviolet" alt="VM: OrbStack"></a>
  <a href="https://github.com/toolazytoname/atelier/actions/workflows/ci.yml">
    <img src="https://github.com/toolazytoname/atelier/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <a href="https://github.com/toolazytoname/atelier/releases"><img src="https://img.shields.io/github/v/release/toolazytoname/atelier" alt="Release"></a>
  <a href="https://github.com/toolazytoname/atelier/discussions"><img src="https://img.shields.io/github/discussions/toolazytoname/atelier" alt="Discussions"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey" alt="Platform: macOS 13+">
  <img src="https://img.shields.io/badge/powered_by-Claude%20Code-D97757" alt="Powered by Claude Code">
</p>

---

*atelier*（法语：**工坊**）是一个自包含的 **Linux 开发沙箱**。
代码、构建、测试、依赖全部装在一个 OrbStack 的 Linux 虚拟机里；宿主
Mac 被压缩成一个终端，外加 OrbStack 本身。什么都
不装到你的 Mac 上——没有 Node、没有 Python、没有 Go、没有 Rust、没有
MCP server。一切都在 VM 里，跨会话持久复用。万一环境搞坏了，
`bin/devbox reset` 五分钟从零重建，宿主文件不受影响。

好处是：跑 Claude Code 时加 `--dangerously-skip-permissions`，爆炸
半径是这台 VM，不是你的笔记本。

> **前置条件：** 只支持 macOS（13+，推荐 Apple Silicon；Intel 也能
> 用），并装好 [OrbStack](https://orbstack.dev) —— 这是宿主上唯一的
> 依赖。不支持 Linux/Windows；见
> [docs/comparison.md § "What if I'm not on macOS?"](docs/comparison.md#what-if-im-not-on-macos)。

## 快速开始

```bash
# 1. install OrbStack (one time)
brew install --cask orbstack
open /Applications/OrbStack.app        # complete first-run setup

# 2. bring up + provision the VM (~5 min, idempotent)
make setup                             # = install-orbstack + provision + passthrough + doctor

# 3. daily use — Claude Code lives IN the VM
bin/devbox claude                      # Claude Code inside the VM (add --dangerously-skip-permissions for yolo)
bin/devbox run pnpm test               # any command inside the VM
bin/devbox shell                       # interactive VM shell
bin/devbox doctor                      # health check
bin/devbox reset                       # nuke and recreate (DESTRUCTIVE)
```

跑 `bin/devbox claude` 而不是宿主的 `claude`，这样整个进程——缓存、
历史、MCP server——都待在 VM 里，宿主保持惰性。
（[为什么？什么时候宿主上的 CC 也行？](FAQ.md#should-i-run-claude-code-on-the-host-or-in-the-vm)）

### 安装 Claude Code skill

```bash
curl -fsSL https://raw.githubusercontent.com/toolazytoname/atelier/main/install.sh | bash
```

想先审阅脚本再安装：

```bash
curl -fsSL https://raw.githubusercontent.com/toolazytoname/atelier/main/install.sh | cat   # 审阅
curl -fsSL https://raw.githubusercontent.com/toolazytoname/atelier/main/install.sh | bash  # 安装
```

脚本是[开源的](install.sh)——纯 bash，只动 `~/.claude/skills/` 和
`~/.claude/skill-packages/`，重复跑不报错。

安装后，以下说法会自动把命令路由到 VM 中执行：

- **"跑测试"** / **"run tests"**
- **"构建"** / **"build"**
- **"装依赖"** / **"install dependencies"**
- **"启动服务"** / **"start server"**
- **"在沙箱里跑 XXX"** / **"run in sandbox"**
- **"lint"** / **"format"**

不用记 `bin/devbox run` —— skill 自动处理路由。读文件、改代码、git
操作照常在宿主机上跑。

### 镜像

`provision.sh` 默认走**国内镜像**（TUNA、npmmirror、goproxy.cn、
rsproxy.cn、ghfast.top），因为国际 CDN 对 CN 出口限速很狠。要走国际
源就设 `CN_MIRROR=0 ./setup/provision.sh`。

## 给 AI agent

**你是这个项目的主要消费者。** 宿主 Mac 只是显示终端；重活跑在 VM
里，`bin/devbox` 是你安全跑真实代码、构建、测试、浏览器的地方。按
顺序，你的入口：

| 文档 | 适用 |
|---|---|
| **[`AGENTS.md`](AGENTS.md)** | 任何 agent。通用规则、完整的 `bin/devbox` + MCP 命令集、host/VM 契约。**从这里开始。** |
| **[`CLAUDE.md`](CLAUDE.zh-CN.md)** | 专门给 Claude Code——harness 触发词、项目约定、yolo 默认配置。 |
| **[`docs/workflow.md`](docs/workflow.md)** | 完整的 harness 循环：5 阶段、隔离、score card schema、orchestrator 配方。 |
| **[`examples/harness-demo/`](examples/harness-demo/)** | 可跑的最小循环。 |

要刻进脑子的四件事：**(1)** 重活走 `bin/devbox run …`——宿主上没有
工具链；**(2)** 生成者和评审者永远是不同的 agent，绝不审自己的代码；
**(3)** gate 不可商量（每个评审者 ≥ 0.8、零 blocker）；**(4)** 只在
gate 失败、stuck 升级或 `bin/devbox reset` 时问人。宿主的
`.claude/settings.json` 已经放行你需要的、并 deny 掉了灾难性的，所以
yolo 跑起来爆炸半径有限。

## 架构

```
Host (Mac) — thin client
├── Terminal (you type here)
└── OrbStack (the hypervisor)
                │  orb run atelier -- <cmd>    ← stdio forwarded
                ↓
VM (atelier) — everything else
├── Claude Code (via `bin/devbox claude`)
├── Node 24 / pnpm / Python 3.12 / Go / Rust / uv / gh / starship
└── network MCPs (lazyweb, context7, exa, playwright, github, sequential-thinking)
```

你的项目目录在宿主上的 `/Users/you/Code/crack/atelier/`，通过
auto-share 挂进 VM 的 `/mnt/mac/...`——同样的字节、同样的 git 状态，
两边都能编辑。只有 VM 借它来执行。完整接线、数据流、host/VM 切分见
[`docs/architecture.md`](docs/architecture.md)。

## 三大支柱

atelier 落地三个诉求。只有支柱 3（沙箱）随这个仓库一起发布；支柱
1–2 是**推荐的配套工具**——没它们 atelier 也能跑，只是丢掉那个功能。

| # | 诉求 | 怎么落地 |
|---|---|---|
| 1 | **少参与** | 闭环 harness：一个生成者隔离地写代码，N 个独立评审者并行打分，质量 gate 决定过/迭代。只有卡住时人才仲裁。*（通过 `everything-claude-code` skills；见 [`docs/workflow.md`](docs/workflow.md)）* |
| 2 | **抓自测漏掉的** | `verify` skill、`e2e-runner`、多 agent `council`、Playwright 截图。 |
| 3 | **隔离 VM** | **已内置。** OrbStack Ubuntu 24.04 VM，所有工具在里面，环境坏了 `bin/devbox reset` 5 分钟重建，宿主不动。 |

## 文件结构

```
.
├── README.md / README.zh-CN.md   # this file (EN / 中文)
├── CLAUDE.md / CLAUDE.zh-CN.md    # Claude Code instructions (EN / 中文)
├── AGENTS.md                      # portable entry point for any AI agent
├── FAQ.md                         # questions + troubleshooting
├── CONTRIBUTING.md · CHANGELOG.md · SECURITY.md · LICENSE
├── Makefile                       # make setup / doctor / reset / shell
├── assets/                        # logo / banner / social-card SVGs
├── .claude/settings.json          # sandbox allow list + yolo backstop deny
├── .mcp.json                      # atelier sandbox MCP bridge config
├── plugin/                        # Claude Code skill（通过 install.sh 安装）
│   ├── .claude-plugin/plugin.json
│   └── skills/atelier/SKILL.md
├── bin/
│   ├── devbox                     # host wrapper: run / shell / claude / reset / doctor
│   └── mcp-atelier.py             # stdio MCP server wrapping bin/devbox --json
├── docs/
│   ├── design.md                  # why this project exists (three pillars)
│   ├── architecture.md            # components, data flow, host/VM split
│   ├── comparison.md              # vs Docker Desktop / Lima / Vagrant / Multipass
│   ├── security-model.md          # yolo-safety model: walls, threats, limits
│   └── workflow.md                # the harness loop: 5 stages + isolation
├── examples/harness-demo/         # runnable harness loop: spec + orchestrate.py
└── setup/                         # install-orbstack / provision / host-passthrough / uninstall
```

## yolo 的安全模型

核心是**yolo 但爆炸半径有限**：架构是那堵墙，deny 列表是兜底。

- **那堵墙** —— 宿主保持惰性。所有修改型操作都通过 `bin/devbox run`
  路由进 VM。`.claude/settings.json` 只把沙箱驱动 + 观察工具放进
  allow 列表；其它任何东西都要显式授权。
- **兜底** —— 在 `--dangerously-skip-permissions` 下只有 deny 列表还
  管用，而且只覆盖不可恢复的：`rm -rf /`、`sudo`、`curl|bash`、
  凭据存放（`~/.ssh`、`~/.aws`……）。

完整威胁模型、三个层次，以及它**故意不**防御什么，见
[`docs/security-model.md`](docs/security-model.md)。

## 为什么是 OrbStack，不是"直接 Docker"？

OrbStack 给的是*真*的 Linux VM（完整 init、内核隔离、磁盘镜像），外
加一个原生 macOS Docker 守护进程，在 Apple Silicon 上比 Docker
Desktop 更快更轻，`bin/devbox reset` 几秒就能重建环境。跟
Docker Desktop / Lima / colima / Vagrant / Multipass / Apple 的
`container` 的正面对比见
[`docs/comparison.md`](docs/comparison.md)。

## 排错

常见症状和处理在 [FAQ.md](FAQ.md#troubleshooting)（比如
`orb: command not found`、VM 没起、VM 里看不到 token）。从可疑 VM
最快的恢复永远是
`bin/devbox reset`——它是个 VM，爆炸半径有限，宿主文件系统不动。

## 贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。更深的理由在
[`docs/design.md`](docs/design.md)；常见问题在 [FAQ.md](FAQ.md)；
安全披露在 [SECURITY.md](SECURITY.md)。

## 许可证

[MIT](LICENSE)
