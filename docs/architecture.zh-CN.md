# 架构

> 想扩展或修改 atelier 时读这个。README 讲的是"是什么"，本文讲的是"怎么搭"。

## 分层

```
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 1: Display                                                    │
│  ───────────────                                                     │
│  macOS 终端（你在这里输入）                                          │
│  macOS 浏览器（http://localhost:7456 → open-design web UI）          │
│  宿主上不跑任何其他东西。                                             │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                │  SSH / orbctl stdio
                                ↓
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 2: 沙箱驱动（宿主上唯一的东西）                               │
│  ───────────────                                                     │
│  bin/devbox —— bash 脚本，约 250 行                                  │
│    • run     → orbctl run -m atelier -- <cmd>                        │
│    • shell   → orbctl shell atelier                                  │
│    • claude  → orbctl run ... bash -lc '...'（把 CC 包进 VM）        │
│    • gui     → SSH -L 7456:127.0.0.1:7456 atelier@orb                │
│    • reset   → orbctl delete + create + provision                    │
│    • doctor  → orbctl info + check mounts + env passthrough          │
│                                                                      │
│  在 .claude/settings.json 白名单里。除此无他。                       │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                │  OrbStack 自动共享
                                ↓
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 3: VM（atelier）                                              │
│  ───────────────                                                     │
│  Ubuntu 24.04，4 CPU / 8G RAM / 64G 磁盘                             │
│  由 setup/provision.sh 一次性 provision（~5 分钟，幂等）             │
│                                                                      │
│  • Claude Code（用 bin/devbox claude 跑，yolo 友好）                 │
│  • open-design daemon（HTTP 127.0.0.1:7456，stdio MCP）               │
│  • Node 24 / pnpm / Python 3.12 / uv / Go 1.23 / Rust 1.96 / gh     │
│  • starship / zsh / fzf / ripgrep / fd / bat / lazygit               │
│  • 网络型 MCP：lazyweb、context7、exa、github、                       │
│                  sequential-thinking、playwright                     │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                │  宿主文件系统自动共享
                                ↓
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 4: 项目文件                                                   │
│  ───────────────                                                     │
│  /Users/you/Code/crack/<project>（宿主）                            │
│  ↕ OrbStack 自动共享                                                 │
│  /mnt/mac/Users/you/Code/crack/<project>（VM）                      │
│                                                                      │
│  两边都能编辑，字节相同，survives bin/devbox reset。                  │
└──────────────────────────────────────────────────────────────────────┘
```

## 数据流

### 宿主上的命令在 VM 里执行

```
$ bin/devbox run pnpm test
        │
        │  (1) bin/devbox 解析 argv
        ↓
ensure_vm   (2) —— 如果 atelier 没在跑就先启
        │
        ↓
orbctl run -m atelier -- pnpm test   (3) —— exec 进 VM shell
        │
        ↓
VM bash:  PATH=~/.local/bin:/usr/local/node-v24.11.0/bin:$PATH
          pnpm test                       (4) —— 在 /mnt/mac/... 下运行
        │
        ↓
stdout/stderr 通过 orbctl 管道回宿主终端
        │
        ↓
$  (你看到输出，exit code 一并传回)
```

### CC 在 VM 里，MCP 在 VM 里，浏览器在宿主上

```
$ bin/devbox claude
        │
        ↓
ensure_vm → 启动 atelier
        │
        ↓
od start &   (daemon 在 VM 内 bind 127.0.0.1:7456)
        │
        ↓
claude   (5) —— 发现 cwd 下的 .mcp.json → 加载 open-design MCP
        │       MCP 是 stdio 桥，所以 agent ↔ MCP 这段不需要端口转发
        ↓
用户输入："show me the design system tokens"
        │
        ↓
CC → mcp__open-design__get_artifact → daemon → response → CC
        │
        ↓
用户想看可视化界面：
$ bin/devbox gui   (另一个终端)
        │
        ↓
SSH -L 7456:127.0.0.1:7456 atelier@orb   (6) —— 把浏览器隧道到 daemon
        │
        ↓
浏览器打开 http://localhost:7456 → 触达 daemon 的 127.0.0.1:7456
```

上面 6 个步骤的注释对应 [`bin/devbox`](../bin/devbox) 里
`cmd_claude()` 和 `cmd_gui()` 的注释——想跟代码对照就看那里。

## 为什么每一块都存在

### `bin/devbox` 是个薄薄的 shell 脚本

纯 bash，没有 Node 依赖，不用编译，装也就 `chmod +x`（或 `ln -sf` 到 `~/bin`）。
它存在的理由是让宿主 shell 只用知道一件事：**这个二进制把命令路由到 VM**。
项目里的其他东西要么是观察类（`Read`、`Glob`、`Grep`），要么就是改文件。

### VM 选 Ubuntu 24.04

LTS 支持到 2029，Node / Python / Go / Rust 工具链兼容性都很好，OrbStack 镜像启动
不到 4 秒。不用 Alpine（musl libc 把太多预编译 wheel 弄坏了），不用 Arch
（滚动发布破坏可复现性）。

### `setup/provision.sh` 是单个幂等大脚本

我们选"一个脚本、一把跑到底、幂等"而不是更模块化的配置管理（Ansible / Chef / Nix），
理由：

- 重新 provision 的目标是**一台全新的空 VM**——没有"选择性更新"这种工作流
- 脚本 300 行，5 分钟能从头读到尾
- 重跑是安全的（apt reinstall 是 no-op，`pip install -U` 对钉死版本的包幂等）
- 维护者用 `git log` + `git checkout` + `make reset` 就能二分 provisioning regression

### 白名单故意做得很小

`.claude/settings.json` **只**允许架构需要的：

- `bin/devbox*` —— 宿主上唯一的变更类操作
- `setup/*` —— provisioning（用户自己跑，不是 CC）
- `make*`、`git*` —— 纯文件操作
- `orb*`、`orbctl*` —— VM 控制
- `Read`、`Glob`、`Grep`、`WebFetch`、`WebSearch` —— 观察
- Claude Code 内建（`TodoWrite`、`Task`、`Agent` 等）

其他的——包括项目目录外的 `Write` / `Edit`——都要显式授权。这就是为什么
`--dangerously-skip-permissions` 在 yolo harness 循环里是安全的。

### deny 名单是最后兜底

它只装"哪怕秒级发现都救不回来"的那类操作：

- `rm -rf /`、`rm -rf ~`、`rm -rf $HOME/Code/crack/!(atelier)/**`
- `sudo *`、`doas *`
- `curl *|bash`、`wget *|bash`、`eval *`、`exec *`
- `Write` / `Edit` 指向 `~/.ssh/**`、`~/.aws/**`、`~/.gnupg/**`、
  `~/.kube/**`、`~/.docker/**`

shell rc 文件和宿主配置目录**故意不在 deny 名单里**——架构契约是 CC 只写
项目目录。如果将来某个 feature 真的需要碰宿主配置，那是**往白名单里加**，
不是去松 deny。deny 是"不可恢复事故"用的，不是"现在不想要"用的。

## 状态住哪儿

| 东西 | 在哪儿 | `bin/devbox reset` 后还在吗？ |
|------|-------|------------------------------|
| 项目源码 | `/Users/you/Code/crack/<project>`（宿主）↔ `/mnt/mac/...`（VM） | ✅ |
| 项目的 `.env`、`.git/`、`node_modules/`、`.venv/`、`target/` | 同上 | ✅ |
| Anthropic token | `/etc/environment.d/host-proxy.conf`（VM），由 `setup/host-passthrough.sh` 写入 | ❌（重跑 passthrough） |
| Claude Code session 历史 | `~/.claude/session-data/`（VM） | ❌ |
| open-design design project | `~/.local/share/open-design/`（VM） | ❌（重新导入 spec） |
| open-design daemon PID / logs | `~/.local/share/open-design/daemon.log`（VM） | ❌ |
| 全局 npm 包 | `~/.npm-global/`（VM） | ❌ |
| Rust crates 缓存 | `~/.cargo/`（VM） | ❌ |
| Go module 缓存 | `~/go/pkg/`（VM） | ❌ |

分裂原则：**项目树是持久的，VM 里的其他东西都是一次性的**。如果你发现自己
把重要的东西放在 VM 里，就把它挪到项目树里（committed 或按需 gitignore），
或者挪进 `setup/provision.sh`，这样重新 provision 时会重建。

## Reset 和契约

`bin/devbox reset`：

1. 让用户输入 `yes`（没有 `--force`）
2. `orbctl delete atelier --force`（DESTRUCTIVE —— 把 VM 镜像删掉）
3. `orbctl create ...`（从 `ubuntu:24.04` 镜像重建，~30s）
4. 跑 `setup/provision.sh`（~5 分钟）

`bin/devbox reset` **永远不动宿主文件系统**。宿主上的项目树才是真相之源，
VM 是从大家都能用的同一份 `setup/provision.sh` 重建出来的。

## 扩展架构

常见的 fork / 扩展：

| 想…… | 看哪里 |
|----------|------------|
| 给 `bin/devbox` 加新子命令 | `bin/devbox` —— 加一个 `cmd_<name>()` 和一个 dispatch case |
| 给 VM 加新工具 | `setup/provision.sh` —— 加一行 apt，或一个新的 `curl \| tar` 块，或一个新的 `pip install` |
| 改 VM 大小 | `bin/devbox` 的 `VM_*` 默认值，或 `make setup CPUS=8 MEMORY=16G DISK=128G` |
| 换发行版 | `bin/devbox` 的 `VM_DISTRO`（默认 `ubuntu:24.04`）—— 必须是标准 OrbStack 镜像 |
| 用 Lima / Docker 替换 OrbStack | 重写 `bin/devbox`。8 个子命令对应 8 个小函数，这是 1 天工作量，不是 1 周 |
| 加新 MCP server | `.mcp.json` —— 指到二进制，重启 CC |

至于搭在这层沙箱之上的"多 agent harness"工作流，见 [`docs/workflow.md`](workflow.md)。
安全模型见 [`docs/security-model.md`](security-model.md)。为什么选 OrbStack 而不是别的，
见 [`docs/comparison.md`](comparison.md)。
