# atelier

一个**隔离、可丢弃的 Linux 开发沙箱**，让 Claude Code（和你）真正干活而不碰宿主机。
整个构建、测试、运行循环都在 OrbStack 的 Ubuntu 虚拟机里；Mac 只承担 Claude Code 本身
和那些必须留在宿主的 MCP（`open-design`、`weixin-reader`）。

## TL;DR

```bash
# 1. 安装 OrbStack（一次性）
brew install --cask orbstack
open /Applications/OrbStack.app        # 走完首次设置

# 2. 拉起 VM 并初始化
./setup/provision.sh                  # 约 5 分钟，幂等（默认走国内镜像）
# 如果你在国际网络下：
# CN_MIRROR=0 ./setup/provision.sh
./setup/host-passthrough.sh           # 把宿主的 API token 推过去

# 3. 日常用法
bin/devbox shell                      # 进入 VM shell
bin/devbox run pnpm test              # 在 VM 里跑任意命令
bin/devbox run claude                 # 在 VM 里跑 Claude Code
bin/devbox doctor                     # 自检
bin/devbox reset                      # 推倒重建 VM
```

> 用 `make` 的话同样：`make setup` / `make doctor` / `make reset`

## 为什么需要镜像

`provision.sh` 默认走**国内镜像**——国际 CDN（deb.nodesource.com、static.rust-lang.org 等）
对来自国内出口的 IP 会限速到几十 KB/s，VM 里装大点的包能卡半小时。脚本里：

| 资源 | 国内走 | 国际走 |
|------|--------|--------|
| apt | mirrors.tuna.tsinghua.edu.cn | ports.ubuntu.com（默认）|
| Node.js 二进制 | npmmirror | nodejs.org 官方 |
| npm registry | npmmirror | registry.npmjs.org |
| crates.io | rsproxy.cn 替换 | 官方源 |
| PyPI | pypi.tuna.tsinghua.edu.cn | pypi.org 官方 |
| GitHub releases | ghfast.top 代理 | 官方源 |
| Go、Rust、Docker 官方源 | **官方即可**（dl.google.com 走 20 MB/s，static.rust-lang.org 正常）| 同上 |

设置 `CN_MIRROR=0 ./setup/provision.sh` 切到国际源。

## 四大支柱方法论

这个项目落地的是你提出的四个诉求。每一根支柱都映射到环境里现成的能力，沙箱只是让循环跑得更快、更安全。

| # | 诉求 | 怎么落地 |
|---|------|----------|
| 1 | 少参与 | `everything-claude-code:autonomous-agent-harness` · `autonomous-loops` · `continuous-agent-loop` · `multi-plan` → `multi-execute` → `council` 多 agent 互相评审打多数票 · `quality-gate` / `verification-loop` / `gateguard` 做阶段关卡 |
| 2 | 设计审美对齐 Open Design | `mcp__open-design__get_artifact` 拉你的设计项目当 spec · `mcp__plugin_lazyweb_lazyweb__lazyweb_search` 加真实产品参考 · `everything-claude-code:frontend-design` / `ui-ux-pro-max` / `design-system` 出前端 |
| 3 | 自测通过了还有漏网之鱼 | `verify` skill 真起浏览器点一遍 · `everything-claude-code:e2e-runner` 走关键路径 · `council` 让 N 个 agent 用不同 lens（功能 / 视觉 / a11y / 边界 / 安全）独立评审 · `mcp__plugin_everything-claude-code_playwright__browser_take_screenshot` 截图跟 Open Design 参考图肉眼比对 |
| 4 | 自己的虚拟机随便折腾 | OrbStack Ubuntu 24.04 VM（`atelier`）· 宿主机文件系统挂到 VM 内的 `/mnt/mac` · `bin/devbox` 把每条命令都圈在沙箱里 · `bin/devbox reset` 10 分钟内从零重建 |

## 文件结构

```
.
├── CLAUDE.md                  # 给 Claude Code 看的工作规约
├── CLAUDE.zh-CN.md            # 同上，中文版
├── README.md                  # 本文件（英文）
├── README.zh-CN.md            # 本文件（中文）
├── LICENSE                    # MIT
├── CONTRIBUTING.md            # 贡献指南（英中双语）
├── .gitignore
├── Makefile                   # make setup / doctor / reset / passthrough
├── bin/
│   └── devbox                 # 宿主端的 `orbctl` 包装器
├── docs/
│   └── design.md              # 设计理由：为什么是这四根支柱
└── setup/
    ├── install-orbstack.sh    # 装 OrbStack（兜底 brew 不可用的情况）
    ├── provision.sh           # 一次性把 VM 配置好
    ├── host-passthrough.sh    # 把宿主 env（ANTHROPIC_*、GITHUB_TOKEN）推过去
    └── uninstall.sh           # 干净卸载
```

## Claude Code 在这个项目里怎么工作

`CLAUDE.md` 会在 Claude Code 进入这个项目时自动加载。它把循环写死成五条：

1. **设计稿先从 Open Design 拉。** 永远不要凭空设计——`mcp__open-design__get_artifact` 返回
   当前激活的设计项目，把它当 token、组件、布局的事实源。
2. **重活在 VM 里跑。** 用 `bin/devbox run <cmd>` 把构建、测试、LSP 全圈在沙箱里。宿主
   文件系统在 VM 内挂到 `/mnt/mac`，两边都能编辑，但执行路径始终在 VM 内。
3. **多视角验证。** 单个 agent 的"看起来不错"一文不值。每次写完都：起 app 跑 `verify`、
   `e2e-runner` 走一遍关键路径、`council` 至少三个 agent 评审不同维度、截图肉眼跟设计稿比对。
4. **大活上 harness。** 不要亲手写大功能。编排 `autonomous-agent-harness` /
   `autonomous-loops`，让多 agent 议会先把方案吵明白，再让用户看。
5. **VM 是消耗品。** `bin/devbox reset` 10 分钟推倒重建。不在 `/mnt/mac` 里的东西都不算
   持久化。

## 什么跑在宿主、什么跑在 VM

| 关注点                       | 宿主 | VM | 备注 |
|------------------------------|------|----|------|
| Claude Code（你）            |  ✓   |    | 跑在这个终端里 |
| `open-design` MCP            |  ✓   |    | 跟 macOS 上的 Open Design app 通信 |
| `weixin-reader` MCP          |  ✓   |    | 路径绑死在宿主 skill |
| `playwright` MCP             |      |  ✓ | 浏览器跑在 VM 内（更快、隔离）|
| `context7` / `exa` / `lazyweb` |   |  ✓ | 纯网络、不动宿主状态 |
| `github` MCP                 |      |  ✓ | 用 VM 自己的 `gh` 鉴权 |
| `memory` MCP                 |      |  ✓ | 进程内图，按 VM 隔离 |
| Node / pnpm / uv / go / rust |      |  ✓ | 详见 `setup/provision.sh` |
| Docker 守护进程              |  ✓   |    | OrbStack 守护在宿主；VM 里的 CLI 通过 socket 通信 |

## 为什么是 OrbStack 不是 Docker

OrbStack 给的是**真 Linux VM**（完整 init、systemd、内核隔离、磁盘镜像），还顺手在
macOS 上通过 Apple Virtualization 框架跑了一个 Docker 守护进程。跟 Docker Desktop 比，
它在 Apple Silicon 上更快、更省资源，并且支持一次性 VM（`bin/devbox reset` 几秒就重建）。
代价是 Linux VM 比纯容器重——但对一个需要共享文件、起开发服务、随时 reset 的真开发环境，
这笔账划算。

## 排错

| 现象 | 处理 |
|------|------|
| `orb: command not found` | `export PATH="/opt/homebrew/bin:$PATH"` 或 `ln -sf $(pwd)/bin/devbox /usr/local/bin/devbox` |
| `atelier` 没起 | `bin/devbox provision`（拉起 + 装） |
| VM 里的 `claude` 没鉴权 | `./setup/host-passthrough.sh` 然后重启 VM shell |
| 想要干净状态 | `bin/devbox reset`（破坏性，VM 推倒重建）|
| 宿主 8000 端口被占 | VM 有自己的网络命名空间，VM 里随便用；真要转发时再处理 |
| VM 里某状态可疑 | `bin/devbox run bash -c "rm -rf ~/*"` —— 是 VM，爆炸半径有限 |

## 推倒沙箱

```bash
bin/devbox reset
```

这会要你确认一次，删掉 `atelier` VM 并从零重建。耗时约 5–10 分钟（主要在拉 apt
包和语言运行时）。宿主机文件不动。

## 贡献 / 二次开发

见 [CONTRIBUTING.md](CONTRIBUTING.md)。`docs/design.md` 里有这个方法论背后的设计理由。
