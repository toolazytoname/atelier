# CLAUDE.md — atelier 开发沙箱（中文版）

## 这个项目是什么

一个自包含、**隔离的 Linux 开发沙箱**，用来构建任何你想做的东西。整个
工作流——代码、构建、测试、依赖——都在一个叫 `atelier` 的 OrbStack Linux
VM 里。宿主 Mac 只跑 Claude Code 本身。

## yolo 的安全模型

**yolo 但爆炸半径有限。** 架构是那堵墙；deny 列表只是
`--dangerously-skip-permissions` 下的兜底。

- **那堵墙** —— 宿主保持惰性。所有修改型操作都通过 `bin/devbox run`
  路由进 VM。`.claude/settings.json` 只把沙箱驱动
  （`bin/devbox*`、`setup/*`、`make*`、`git*`、`orb*`）和观察/CC 工具
  （`Read`、`Glob`、`Grep`、`Agent`……）放进 allow 列表。其它任何东西
  都要用户显式授权——宿主不会随着时间装工具或加配置。
- **兜底** —— yolo 下只有 deny 列表还管用，而且只针对不可恢复的：
  `rm -rf /`/`~`、fork 炸弹、`sudo`/`doas`、`curl|bash`/`eval`/`exec`，
  以及对凭据存放的写入（`~/.ssh`、`~/.aws`、`~/.gnupg`、`~/.kube`、
  `~/.docker`）。Shell rc 文件和宿主配置目录**故意**不 deny——如果某个
  功能确实需要它们，用户往 allow 列表里加，而不是放松 deny 列表。
- **墙只管这个项目。** 项目级 `settings.json` 只对这个目录里生效；
  `cd` 到别处跑 CC 用的是宿主的全局配置。留在项目里，墙就在。

完整威胁模型和三个层次：[`docs/security-model.md`](docs/security-model.md)。

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

## 东西在哪

**全部在 VM 里跑。** 宿主只是个瘦客户端：终端、OrbStack。

- **宿主（Mac）**：终端显示、OrbStack。仅此而已。没有 Node、没有
  MCP、没有 dev 工具——全在 VM 里。
- **VM（atelier）**：
  - Claude Code（用 `bin/devbox claude` 跑）
  - atelier 沙箱 MCP 桥（stdio；通过项目下 `.mcp.json` 配置——包装
    `bin/devbox --json`，让 agent 驱动沙箱）
  - 全部 dev 工具：Node 24 / pnpm / Python 3.12 / Go 1.23 / Rust 1.96 /
    uv / gh / starship
  - 网络型 MCP：`playwright`、`context7`、`exa`、`github`、
    `lazyweb`、`sequential-thinking`
- **项目文件**（`/Users/you/Code/crack/atelier/`）在宿主上，通过
  OrbStack 自动挂载到 VM 的 `/mnt/mac/Users/you/Code/crack/atelier/`。
  两边都能编辑；执行始终在 VM 里。

## 日常循环

```bash
# one-time
brew install --cask orbstack                            # if missing
./setup/provision.sh                                    # inside the VM (~5 min, idempotent)
./setup/host-passthrough.sh                             # forward env (ANTHROPIC_*, GITHUB_TOKEN)

# every session
bin/devbox claude                                       # Claude Code, inside the VM (run with --dangerously-skip-permissions for yolo)
bin/devbox shell                                        # or just an interactive shell
bin/devbox run pnpm test                                # run any command inside the VM
bin/devbox doctor                                       # health check
bin/devbox reset                                        # nuke + recreate (DESTRUCTIVE)
```

## 工作规约（给我自己看的，Claude Code）

1. **重活在 VM 里跑**，别动宿主。用 `bin/devbox run <cmd>` 或
   `orb run atelier -- <cmd>`。宿主文件系统以读写方式挂到 VM 的
   `/mnt/mac`——两边都能编辑，但沙箱化的执行路径始终在 VM 里。
2. **设计审美从真实参考来。** 任何 UI 开工前先用
   `mcp__plugin_lazyweb_lazyweb__lazyweb_search` 交叉对照真实产品
   参考，把它当 spec。把活丢进 `everything-claude-code:frontend-design`
   和 `ui-ux-pro-max` skills。
3. **多视角验证是硬性要求。** 写完代码不要相信那条看着对的路。每次都：
   - 用 `verify` skill 真起浏览器、真交互。
   - `everything-claude-code:e2e-runner` 走关键用户路径。
   - 拉 `everything-claude-code:council`，N 个独立 agent 拿不同 lens
     （正确性 / 视觉 / a11y / 边界 / 安全）。
   - 关键页面用 `mcp__plugin_everything-claude-code_playwright__browser_take_screenshot`
     截图，跟你的设计参考肉眼比对。
4. **积极上 harness。** 非琐碎功能用
   `everything-claude-code:autonomous-agent-harness` /
   `autonomous-loops` / `continuous-agent-loop` 编，让多 agent 议会在
   用户被卷进来之前把方案吵明白。用户想当**裁判**，不是**操作员**。
   完整闭环、隔离机制、硬性规则看上面 **"默认工作流（yolo harness）"** 段。
5. **错误别吞。** 所有需要在 VM 里可用的宿主专属 MCP 都必须显式打通
   （目前没有；需要时在 `setup/` 写明模式）。
6. **VM 是消耗品。** `bin/devbox reset` 从零重建。没进源代码管理或没在
   `/mnt/mac` 里的东西都会丢。

## 宿主 vs VM 跑什么

简版：宿主跑终端、OrbStack 和 `git`/文件读取；**其它一切都跑在
VM 里**（Claude Code、atelier 沙箱 MCP、所有语言工具链、所有网络
型 MCP）。完整的逐组件表格在
[`docs/architecture.md`](docs/architecture.md)。

## 排错

症状 → 处理的表格见 [FAQ § Troubleshooting](FAQ.md#troubleshooting)。
通用恢复手段是 `bin/devbox reset`（破坏性——从零重建 VM；宿主文件系统
不动）。
