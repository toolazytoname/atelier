# CLAUDE.md — atelier 开发沙箱（中文版）

## 这个项目是什么
一个自包含、**隔离的 Linux 开发沙箱**，用来跑任何你想做的东西。整个工作流——代码、
构建、测试、依赖——都在一个叫 `atelier` 的 OrbStack Linux VM 里。宿主 Mac 只承担
Claude Code 本身。

## 东西在哪
**全部在 VM 里跑。** 宿主只是个瘦客户端：终端、浏览器、OrbStack。

- **宿主（Mac）**：终端显示、浏览器标签指向 `http://localhost:7456`（经 SSH
  隧道穿透到 VM 里的 open-design web UI）。仅此而已。没有 Node / MCP / dev 工具
  ——全在 VM 里。
- **VM（atelier）**：
  - Claude Code（用 `bin/devbox claude` 跑）
  - open-design daemon（HTTP 在 `127.0.0.1:7456`，MCP 用 `od mcp`）
  - open-design MCP 桥（stdio；通过项目下 `.mcp.json` 配置）
  - 全部 dev 工具：Node 24 / pnpm / Python 3.12 / Go 1.23 / Rust 1.96 /
    uv / gh / starship
  - 网络型 MCP：`playwright`、`context7`、`exa`、`github`、
    `lazyweb`、`sequential-thinking`
- **项目文件**（`/Users/lazy/Code/crack/atelier/`）在宿主上，通过 OrbStack
  自动挂载到 VM 的 `/mnt/mac/Users/lazy/Code/crack/atelier/`。两边都能编辑，
  执行始终在 VM 里。

## Yolo-安全模型

这个项目的整个目标就是**"yolo 但爆炸半径有限"**。架构本身就是墙，deny 名单
只是 `--dangerously-skip-permissions` 模式下的最后兜底。

**架构（真正的墙）。** 宿主应当是惰性的。所有变更类操作都通过 `bin/devbox run`
进 VM。宿主除了 Claude Code 本身什么都不跑。本项目没有合理理由去修改宿主——
所以白名单**故意做得很小**：

- `bin/devbox*`、`setup/*`、`make*`、`git*`、`orb*`、`orbctl*`——沙箱驱动面
- `Read`、`Glob`、`Grep`、`WebFetch`、`WebSearch`——观察类
- `TodoWrite`、`Task`、`Agent` 等——Claude Code 自身功能

不在白名单的，要么走 VM（重活），要么根本不需要发生。哪天真的需要一次，
用户授权加进白名单——**这里没有任何暗示宿主会随着时间装工具、改配置、加包**。

**最后兜底 deny 名单（yolo 兜底）。** 跑 `--dangerously-skip-permissions` 时
只有 deny 名单仍然生效。**故意做得很短**——只列"哪怕秒级发现都救不回来"的事故：

- `rm -rf /`、`rm -rf ~`、`rm -rf /Users/lazy/Code/crack/!(atelier)/**`、
  `:(){ :|:&};:`——核弹级
- `sudo *`、`doas *`——提权
- `curl *|bash`、`curl *|sh`、`wget *|bash`、`wget *|sh`、`eval *`、
  `exec *`——远程代码执行入口
- `Write/Edit ~/.ssh/**`、`~/.aws/**`、`~/.gnupg/**`、`~/.kube/**`、
  `~/.docker/**`——凭据存放（一次覆盖就完蛋）

**故意没列的 deny 项。** Shell rc（`~/.zshrc`、`~/.bashrc`）、宿主配置
（`~/.config/**`）、系统路径（`/etc/**`、`/usr/**`、`/System/**`、
`/Library/**`、`/Applications/**`）。架构上 CC 只写项目目录、其它全走 VM。
如果哪天架构真的破了（比如某个新功能就是要碰宿主 config），那是**往 allow
里加白名单**——不是去松 deny。**deny 是"不可恢复事故"用的，不是"现在不想要"用的**。

**墙只管这个项目。** 项目级 `settings.json` 只对在这个目录里跑的 CC 生效。
`cd ~/Code/crack/other-project` 跑 CC，那边用的是宿主 `~/.claude/settings.json`。
**留在项目里，墙就在。**

## 默认工作流（yolo harness）

任何**非琐碎的功能开发**（多文件 / 触动架构 / 新 API / 任何 UI）默认走这个闭环：

1. **规划（当前 CC，快速）** — 把请求拆成几个小任务；定下硬性的验收标准。
2. **生成（隔离 agent）** — 起 subagent（或 `bin/devbox run claude -p "..."`）
   写代码。**独立 context window，独立 session。**
3. **测试 + 评审（并行评估）** — 起 N 个独立评审者（各为 subagent）：
   正确性、安全、a11y、视觉、边界。跑项目自带测试套。各评审独立打分，不共享 context。
4. **守门（决策）** — 全部 `score ≥ 0.8` 且无 blocker 且测试全绿才算过。把 score card
   落盘做 checkpoint。
5. **提交或迭代** — 过：commit + push + 开 PR（附 score card）。不过：把 score card
   喂回生成者，迭代。
6. **升级** — 撞 `MAX_ITERATIONS`（默认 5）：停下来问人。spec 大概率是错的。

### 隔离：承重的属性

**生成者和评审者必须是独立 agent。** 三种机制，按重量排：

- **Agent 工具** — 起 subagent。新 context window，只回 summary。
- **`bin/devbox run claude ...`** — VM 里起一个完整 CC 进程。自己的 `/proc/<pid>`，
  自己的 `~/.claude/`，独立的工具链访问。
- **`council` skill** — 一次起 N 个评审者，每个 subagent。

**永远不要让生成者和评审者共享 context。** 评审的 transcript 是 MB 量级；混进生成
者的 context 就腐烂。生成者只能看 score card，不能看评审的推理过程。

### 硬性规则（无例外）

1. **永远不要自己评审自己写的代码。** 开发和评审必须是独立 agent。
2. **永远不要绕过失败的 gate** "省时间"——这是工程腐烂的起点。gate 说了算，句号。
3. **永远不要让生成者看评审的完整 transcript**——只能看 score card。否则生成者
   会去优化"讨好评审者"，而不是"做对"。
4. **只在 gate 失败或 stuck 升级时问人。** 不要为单个文件的评审 ping 人。

### 什么时候用

"上线了被 revert 我会心疼吗？"——会，就用 harness 闭环。改 typo、doc 微调、
琐碎 config，直接 commit。

完整设计（score card 格式、stuck 检测、预算守卫、并行评审模式）见
[`docs/workflow.md`](docs/workflow.md)。

## 日常循环
```bash
# 一次性
brew install --cask orbstack                            # 如果还没装
./setup/provision.sh                                    # VM 内跑（约 5 分钟，幂等）
./setup/host-passthrough.sh                             # 推 host env（ANTHROPIC_*、GITHUB_TOKEN）

# 每个工作日
bin/devbox claude                                       # Claude Code 在 VM 里跑（带 --dangerously-skip-permissions 开 yolo）
bin/devbox gui                                          # open-design web UI 隧道到宿主浏览器
bin/devbox shell                                        # 或者直接开 VM shell
bin/devbox run pnpm test                                # VM 里跑任意命令
bin/devbox doctor                                       # 自检
bin/devbox reset                                        # 推倒重建（破坏性）
```

## 工作规约（给我自己看的，Claude Code）

1. **重活在 VM 里跑**，别动宿主。用 `bin/devbox run <cmd>` 或
   `orb run atelier -- <cmd>`。宿主文件系统挂到 VM 的 `/mnt/mac`——两边都能编辑，
   但执行始终在沙箱里。
2. **设计审美从 Open Design 来。** 任何 UI 开工前先
   `mcp__open-design__get_artifact`，把返回结果当 spec。需要补外部参考时
   `mcp__plugin_lazyweb_lazyweb__lazyweb_search`。把活丢进
   `everything-claude-code:frontend-design` 和 `ui-ux-pro-max`。
3. **多视角验证是硬性要求。** 写完代码不要走"看着对"那条路。每次都：
   - 用 `verify` skill 真起浏览器点（不是"我推了一下"）。
   - `everything-claude-code:e2e-runner` 走关键用户路径。
   - 拉 `everything-claude-code:council`，N 个 agent 拿不同 lens（功能 / 视觉 / a11y /
     边界 / 安全）独立评审，多数票否决。
   - 关键页面用 `mcp__plugin_everything-claude-code_playwright__browser_take_screenshot`
     截图，跟 Open Design 参考肉眼比对。
4. **积极上 harness。** 非琐碎功能用 `everything-claude-code:autonomous-agent-harness` /
   `autonomous-loops` / `continuous-agent-loop` 编，让多 agent 议会在你被卷进来之前把
   方案吵明白。你是**裁判**，不是**操作员**。完整闭环、隔离机制、硬性规则看上面
   **"默认工作流（yolo harness）"** 段。
5. **错误别吞。** 必须进 VM 的宿主 MCP 要显式打通（目前没有；需要时在 `setup/` 写明
   模式）。
6. **VM 是消耗品。** `bin/devbox reset` 10 分钟推倒重建。没进源代码管理或没在
   `/mnt/mac` 里的东西都不算持久。

## 宿主 vs VM 跑什么

| 关注点                       | 宿主 | VM | 备注 |
|------------------------------|------|----|------|
| 终端、浏览器                 |  ✓   |    | 系统本来就做这个 |
| OrbStack 虚拟化              |  ✓   |    | 在 Apple Silicon 上跑 Linux VM |
| Claude Code                  |      |  ✓ | `bin/devbox claude`，跟本地 MCP 通信 |
| open-design daemon           |      |  ✓ | Node 服务，bind 127.0.0.1:7456 |
| open-design MCP              |      |  ✓ | stdio 桥，`.mcp.json` 配的 |
| open-design web UI           |      |  ✓ | daemon 起服务，宿主浏览器经 SSH 隧道访问 |
| `playwright` MCP             |      |  ✓ | 浏览器跑在 VM 内（更快、隔离）|
| `context7` / `exa` / `lazyweb` |   |  ✓ | 纯网络，不动宿主状态 |
| `github` MCP                 |      |  ✓ | 用 VM 自己的 `gh` 鉴权 |
| Node 24 / pnpm / uv / go / rust / gh / starship |  | ✓ | 详见 `setup/provision.sh` |
| Docker 守护进程              |  ✓   |    | OrbStack 守护在宿主；VM 里的 CLI 通过 socket 通信 |

## 排错

- **`orb: command not found`** → `export PATH="/opt/homebrew/bin:$PATH"` 或把
  `bin/devbox` 软链到 PATH 里。
- **`atelier` 没起** → `bin/devbox provision`（拉起 + 装）。
- **Token 轮换了** → 重新跑 `./setup/host-passthrough.sh`。
- **VM 玩坏了** → `bin/devbox reset`（破坏性，从零重建）。
