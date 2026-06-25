<!-- markdownlint-disable MD041 first-line-h1 -->
<p align="center">
  <a href="README.zh-CN.md">
    <img src="assets/banner.svg" alt="atelier — 一个隔离、可丢弃的 Linux 开发沙箱" width="820">
  </a>
</p>

<p align="center">
  <strong>macOS + Claude Code，隔离在一个一次性的 Linux 虚拟机里。宿主机保持干净。</strong>
</p>

<p align="center">
  <a href="README.md">English</a>
  ·
  <a href="README.zh-CN.md"><b>中文</b></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://orbstack.dev"><img src="https://img.shields.io/badge/VM-OrbStack-blueviolet" alt="VM: OrbStack"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey" alt="Platform: macOS 13+">
  <img src="https://img.shields.io/badge/powered_by-Claude%20Code-D97757" alt="Powered by Claude Code">
</p>

---

*atelier*（法语：**工坊**）是一个**自包含、可丢弃的 Linux 开发沙箱**，
用来跑 Claude Code 干活。整套流程——代码、构建、测试、依赖——都装在
OrbStack 的 Linux 虚拟机里。宿主机只承担真正必须承担的：终端、浏览器
标签页、OrbStack 本身。Node、Python、Go、Rust、各路 MCP 全在 VM 里，
跟 VM 一起活、跟 VM 一起死，5 分钟就能从零重建。

> **前置条件（先看这条）：** atelier **只在 macOS 上跑**（13+，
> 推荐 Apple Silicon；Intel 也能用）。你需要装
> [OrbStack](https://orbstack.dev) —— 这是宿主上唯一装的依赖。
> 别的什么都不会装到你的 Mac 上。**Linux 和 Windows 不支持**
> （"宿主保持惰性"这套架构只在宿主跟开发环境是分开的两台机器时
> 才有意义）。原因见
> [docs/comparison.zh-CN.md § "如果我不是 macOS？"](docs/comparison.zh-CN.md#如果我不是-macos)。

## 给 AI agent（先看这条）

如果是你（或跑你的 runtime）发现这个仓库是因为人类说"做 X"、
"审 Y"、"修 Z"——欢迎。**你是这个项目的主要消费者**。宿主 Mac
只是个显示终端，重活跑在 Linux VM 里。`bin/devbox` 这个 wrapper
存在的意义就是给你一个隔离的地方跑真实的代码、构建、测试、浏览
器——而不污染宿主。人类敲一次 `bin/devbox claude` 把你拉起来；
之后你的契约就是 agent-facing 的文档。

按针对性从高到低，你的入口：

| 文档 | 适用 | 内容 |
|---|---|---|
| **[`AGENTS.md`](AGENTS.md)** | 任何 agent（Hermes、Aider、Codex、Cline、Continue、Roo……） | 通用规则 + 完整的 `bin/devbox` 命令集 + host/VM 契约。从这里开始。 |
| **[`CLAUDE.md`](CLAUDE.md)** | Claude Code 专用 | harness 触发词、项目约定、yolo 默认配置。读完 `AGENTS.md` 后看。 |
| **[`docs/agent-quickstart.md`](docs/agent-quickstart.md)** | 所有 agent | 一页式契约：TL;DR、host/VM 矩阵、score card schema、规范的 Python orchestrator 配方、MCP tool 参考。 |
| **[`docs/workflow.md`](docs/workflow.md)** | 所有 agent | 5 阶段 harness 循环、三种隔离机制、score card 设计。 |
| **[`examples/harness-demo/`](examples/harness-demo/)** | 所有 agent | 可跑的最小循环——`bin/devbox run python examples/harness-demo/orchestrate.py`。 |

如果 runtime 支持 MCP，不要 shell，优先用 atelier 自带的 **stdio MCP
server**（[`bin/mcp-atelier.py`](bin/mcp-atelier.py)，Python stdlib 实现，
零依赖），它暴露了 `mcp__atelier__run / status / doctor / run_claude /
version`。已经在 [`.mcp.json`](.mcp.json) 里挂好了。需要稳定可解析
输出时，也可以直接用 `bin/devbox --json <subcmd>`。

第一次 tool call 之前先把四条刻进脑子：

1. **重活走 `Bash(bin/devbox run …)`。** 不要在宿主上跑 `pnpm
   test`、`npm install`、`cargo build`、`pytest`、`playwright`、
   任何 toolchain——宿主上没有。宿主唯一的职责是显示你和把你的
   调用转进 VM。见
   [`docs/agent-quickstart.md` §3](docs/agent-quickstart.md#3-host-vs-vm--where-each-operation-belongs)。
2. **Generator 和 reviewer 是不同的 agent。** 不要审自己的代码。
   并行 reviewer 用 `Agent` 工具，每个 lens 一份 prompt；要完整
   隔离的子进程，用
   `Bash(bin/devbox run claude -p "<自包含的 prompt>")`。
3. **Gate 不可商量。** 每个 reviewer 必须 score ≥ 0.8 且无
   blocker 才能 commit。"等会儿再说"是工程腐化的起点。
4. **只在 gate 失败、stuck escalation、`bin/devbox reset` 时
   问人。** 其他时候让循环自己跑。人是仲裁者，不是操作员。

宿主上的 `.claude/settings.json` 已经放行你需要的调用
（`Bash(bin/devbox*)`、`Bash(git*)`、`Read`、`Edit`、`Glob`、
`Grep`、`Agent`、`TodoWrite`……），并 deny 掉了灾难性的
（`rm -rf /`、`sudo`、`curl|bash`、`~/.ssh/**`、`~/.aws/**`……）。
你可以跑 yolo（`--dangerously-skip-permissions`），爆炸半径
有限。

如果只能读两份文档，读
[`AGENTS.md`](AGENTS.md) 和
[`docs/agent-quickstart.md`](docs/agent-quickstart.md)。

## 快速开始

```bash
# 1. 装 OrbStack（一次性）
brew install --cask orbstack
open /Applications/OrbStack.app        # 走完首次设置

# 2. 拉起 VM 并初始化（~5 分钟，幂等）
./setup/provision.sh
./setup/host-passthrough.sh           # 把宿主的 API token 推过去

# 3. 日常用法
bin/devbox claude                     # 在 VM 里跑 Claude Code
bin/devbox gui                        # open-design 的 web UI 转回宿主浏览器
bin/devbox run pnpm test              # 在 VM 里跑任意命令
bin/devbox shell                      # 进入 VM shell
bin/devbox doctor                     # 自检
bin/devbox reset                      # 推倒重建
```

宿主机保持惰性：不装任何开发工具，不改 shell rc，不动任何配置文件。

### 镜像说明

`provision.sh` 默认走**国内镜像**——国际 CDN（`deb.nodesource.com`、
`download.docker.com` 等）对来自国内出口的 IP 会限速到几十 KB/s，VM
里装大点的包能卡半小时。脚本里用到：TUNA（apt）、npmmirror（Node /
npm / 二进制分发）、goproxy.cn（Go 模块代理）、rsproxy.cn
（crates.io）、ghfast.top（GitHub releases）。设置
`CN_MIRROR=0 ./setup/provision.sh` 切到国际源。

## 主要特点

- **yolo 但爆炸半径有限。** 跑 Claude Code 时加
  `--dangerously-skip-permissions`；架构本身就是那堵墙，allow/deny
  列表只是兜底。
- **宿主机保持惰性。** 不装开发工具，不改 shell rc，不动配置文件。
  `bin/devbox reset` 在 5 分钟内重建 VM。
- **国内网络友好。** `provision.sh` 默认走国内镜像，CN 出口下不卡。
  设 `CN_MIRROR=0` 切到国际源。
- **一个 wrapper 调所有命令。** `bin/devbox run` / `shell` / `claude` /
  `gui` / `doctor` / `reset`——整套工具链都装在这一层壳后面。

## 全部装在 VM 里的架构

```
宿主（Mac）—— 瘦客户端
├── 终端（你在这里敲）
├── 浏览器标签页：http://localhost:7456（open-design 的 web UI）
└── OrbStack（hypervisor）
                │
                │ orb run atelier -- <cmd>      ← stdio 转发
                │ ssh atelier@orb -L 7456:...  ← 浏览器标签页的隧道
                ↓
VM（atelier）—— 其它所有东西
├── Claude Code（通过 `bin/devbox claude` 启动）
├── open-design 守护进程（HTTP 127.0.0.1:7456，MCP 用 `od mcp`）
├── open-design MCP（stdio；跟本地守护进程通信；CC 通过 .mcp.json 发现）
├── open-design web UI（守护进程起，宿主浏览器通过 SSH 隧道访问）
├── Node 24 / pnpm / Python 3.12 / Go / Rust / uv / gh / starship
└── 网络型 MCP（lazyweb, context7, exa, playwright, github, sequential-thinking）
```

项目目录在宿主上（`/Users/you/Code/crack/atelier/`），通过 OrbStack
的 auto-share 挂到 VM 内的 `/mnt/mac/...`。两边都能编辑，但执行路径
始终在 VM 内。

## 什么跑在宿主、什么跑在 VM

| 关注点                       | 宿主 | VM | 备注 |
|-------------------------------|------|----|------|
| 终端、浏览器、显示            |  ✓   |    | 操作系统自带 |
| OrbStack hypervisor           |  ✓   |    | 在 Apple Silicon 上跑 Linux VM |
| Claude Code                   |      |  ✓ | 跟本地 open-design MCP 通信；宿主无需任何配置 |
| open-design 守护进程          |      |  ✓ | Node 服务；只绑 127.0.0.1；通过 SSH 隧道访问 |
| open-design MCP               |      |  ✓ | CC ↔ 守护进程的 stdio 桥 |
| open-design web UI            |      |  ✓ | VM 内起在 127.0.0.1:7456；宿主访问 localhost:7456 |
| Node 24 / pnpm / Python / Go / Rust / uv / gh / starship |  | ✓ | 按项目隔离；`bin/devbox reset` 一次性清理 |
| 项目文件                      |  ✓   |    | 宿主上 `/Users/you/Code/crack/atelier/`，VM 内挂 `/mnt/mac/...` |

## 四大支柱方法论

这个项目落地的是你提出的四个诉求。每一根支柱都映射到环境里现成的能
力，沙箱只是让循环跑得更快、更安全。

| # | 诉求                                         | 怎么落地                                                                                                                                                                                                                            |
|---|----------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1 | 少参与                                       | `everything-claude-code:autonomous-agent-harness` · `autonomous-loops` · `continuous-agent-loop` · `multi-plan` → `multi-execute` → `council` 多 agent 互相评审打多数票 · `quality-gate` / `verification-loop` / `gateguard` 做阶段关卡 |
| 2 | 设计审美对齐 Open Design                     | `mcp__open-design__*` 工具（由本地守护进程提供）拉取实时设计项目当 spec · `mcp__plugin_lazyweb_lazyweb__lazyweb_search` 补真实产品参考 · `everything-claude-code:frontend-design` / `ui-ux-pro-max` / `design-system` 出前端            |
| 3 | 自测通过了还有漏网之鱼                       | `verify` skill 真起浏览器点一遍 · `everything-claude-code:e2e-runner` 走关键路径 · `council` 让 N 个 agent 用不同 lens（功能 / 视觉 / a11y / 边界 / 安全）独立评审 · `mcp__plugin_everything-claude-code_playwright__browser_take_screenshot` 截图跟 Open Design 参考图肉眼比对 |
| 4 | 自己的虚拟机随便折腾，宿主不受影响           | OrbStack Ubuntu 24.04 VM（`atelier`）· 宿主机文件系统挂到 VM 内的 `/mnt/mac` · `bin/devbox` 把每条命令都圈在沙箱里 · `bin/devbox reset` 10 分钟内从零重建                                                                          |

## 文件结构

```
.
├── CLAUDE.md                  # 给 Claude Code 看的工作规约
├── CLAUDE.zh-CN.md            # 同上，中文版
├── README.md                  # 本文件（英文）
├── README.zh-CN.md            # 本文件（中文）
├── CONTRIBUTING.md            # 贡献指南（英中双语）
├── LICENSE                    # MIT
├── Makefile                   # make setup / doctor / reset / passthrough
├── .gitignore
├── assets/
│   ├── logo.svg               # monogram（用于社交卡片等）
│   └── banner.svg             # banner（用于本 README 顶部）
├── .claude/
│   └── settings.json          # 项目级沙箱配置（allow 列表 + yolo 兜底 deny）
├── .mcp.json                  # open-design MCP 桥配置（VM 内的 CC 读取）
├── docs/
│   └── design.md              # 设计理由：为什么是这四根支柱
├── bin/
│   └── devbox                 # 宿主端的 `orbctl` 包装器
└── setup/
    ├── install-orbstack.sh    # 装 OrbStack（兜底 brew 不可用的情况）
    ├── provision.sh           # 一次性把 VM 配置好
    ├── host-passthrough.sh    # 把宿主 env（ANTHROPIC_*、GITHUB_TOKEN）推过去
    └── uninstall.sh           # 干净卸载
```

## 日常用法

```bash
# 会话开始
bin/devbox claude              # 在 VM 里跑 Claude Code（yolo）
# 另开一个终端标签：
bin/devbox gui                 # open-design 的 web UI 通过隧道回到宿主浏览器
# 宿主浏览器里：
open http://localhost:7456
```

收工时把两个终端 Ctrl-C 掉就行。没有任何东西会泄漏到宿主。

## yolo 的安全模型

这个项目的核心是**yolo 但爆炸半径有限**。架构本身就是那堵墙——
deny 列表只是 `--dangerously-skip-permissions` 下的最后一道兜底。

**架构（真正的墙）。** 宿主应该保持惰性。所有需要 CPU / 内存 / 磁盘
的修改型操作都通过 `bin/devbox run` 路由到 VM 里。宿主除了 Claude
Code 的显示终端和浏览器里的 open-design web UI 之外什么都不跑。
本项目里的 `.claude/settings.json` 维护着一份很小的 allow 列表（沙箱
驱动 + 观察工具）——其它任何东西都要用户显式授权。

**最后一道 deny 列表（yolo 兜底）。** 当你给 CC 加上
`--dangerously-skip-permissions` 时，只有 deny 列表还管用。它只包含那
些一旦出岔子几秒钟之内也救不回来的操作：`rm -rf /`、`sudo`、
`curl|bash`、凭据目录（`~/.ssh/**`、`~/.aws/**` 等等）。shell rc 和宿
主配置目录**故意**不在 deny 列表里——架构规定 CC 只写项目树。架构真
的破了的时候，用户把对应路径加进 allow 列表；deny 列表是给「不可恢
复的失误」那类问题留的，不是给「暂时不想要」用的。

完整模型见 `CLAUDE.md`。

## 为什么是 OrbStack 不是 Docker

OrbStack 给的是**真 Linux VM**（完整 init、内核隔离、磁盘镜像），
顺手在 macOS 上通过 Apple Virtualization 框架跑了一个 Docker 守护
进程。跟 Docker Desktop 比，它在 Apple Silicon 上更快、更省资源、并
且支持一次性 VM（`bin/devbox reset` 几秒就重建）。代价是 Linux VM
比纯容器重——但对一个需要共享文件、起开发服务、随时 reset 的真开发
环境，这笔账划算。

## 排错

| 现象                                            | 处理                                                                                                  |
|--------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| `orb: command not found`                         | `export PATH="/opt/homebrew/bin:$PATH"` 或 `ln -sf $(pwd)/bin/devbox /usr/local/bin/devbox`           |
| `atelier` 没起                                   | `bin/devbox provision`（拉起 + 装）                                                                   |
| VM 里的 `claude` 没鉴权                         | `./setup/host-passthrough.sh` 然后重启 `bin/devbox claude`                                            |
| `od` 守护进程没起                                | `bin/devbox gui`（自动起守护进程）或 `bin/devbox claude`                                              |
| 浏览器访问 localhost:7456 被拒                   | `bin/devbox gui` 没起；起一下                                                                          |
| 想要干净状态                                    | `bin/devbox reset`（破坏性，VM 推倒重建）                                                             |
| 宿主 8000 端口被占                               | VM 有自己的网络命名空间，VM 里随便用；真要转发时再处理                                                |
| VM 里某状态可疑                                  | `bin/devbox run bash -c "rm -rf ~/*"` —— 是 VM，爆炸半径有限                                          |

## 推倒沙箱

```bash
bin/devbox reset
```

这会要你确认一次，删掉 `atelier` VM 并从零重建。耗时约 5–10 分钟
（主要在拉 apt 包和语言运行时）。宿主机文件不动。

## 贡献 / 二次开发

贡献流程（issue、PR）见 [CONTRIBUTING.md](CONTRIBUTING.md)。四大支柱
背后的设计理由写在 [`docs/design.md`](docs/design.md) 里。

## 许可证

[MIT](LICENSE)
