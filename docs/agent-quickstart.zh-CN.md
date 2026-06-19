# Agent 快速上手 — 在 atelier 上跑另一个 AI agent

> 给消费 atelier 的 AI agent 的一页式契约。刻意做得紧凑：读一遍，
> 留着不关。要更深入的 Claude Code 触发词和项目约定，看
> [`../CLAUDE.md`](../CLAUDE.md)。要 portable 的多 agent 入口，
> 看 [`../AGENTS.md`](../AGENTS.md)。

## TL;DR（四行）

- **重活** → `Bash(bin/devbox run <cmd>)`。宿主的 toolchain 是空
  的，这不是 bug，是设计——宿主上没东西可跑。
- **长跑 / 隔离的工作** → `Bash(bin/devbox run claude -p "<自包含
  prompt>")`，拉起一个全新的 CC 子进程（在 VM 里），独立的
  `/proc`、独立的 `~/.claude`、独立的 toolchain。
- **代码评审** → 并行拉起 N 个独立的 `Agent` subagent，每个返回
  一张 score card。**永远不要审自己的代码。**
- **Gate 不可商量。** 每个 reviewer score ≥ 0.8 且零 blocker 才能
  commit。

## 1. atelier 给你的是什么

一台一次性的 Ubuntu 24.04 VM（`atelier`），已经装好 **Node 24 /
pnpm / Python 3.12 / uv / Go / Rust / gh / Playwright**，外加 MCP
服务器（**open-design**、**lazyweb**、**context7**、**exa**、
**github**）。你的项目文件（在宿主上）通过 OrbStack 自动挂到
VM 内的 `/mnt/mac/...`——同一份字节，不需要 copy。宿主 Mac 保持
惰性：不装 Node、不装 Python、不改 shell rc、不动任何配置文件。

那堵墙：`../.claude/settings.json` 白名单放行 `Bash(bin/devbox*)`、
`Bash(git*)`、观察工具、`Agent`、`TodoWrite`，并 deny 掉那些不可
恢复的失误（`rm -rf /`、`sudo`、`curl|bash`、`~/.ssh/**`、
`~/.aws/**`……）。加了 `--dangerously-skip-permissions` 之后，
限缩爆炸半径的是**架构**——不是 deny 列表。

## 2. 你应该知道的命令集

| 命令 | 干什么 | agent 什么时候用 |
|---|---|---|
| `Bash(bin/devbox run <cmd>)` | 在 VM 里跑命令，返回输出 | `pnpm test`、`npm run build`、`cargo build`、`pytest`、`playwright`、沙箱里的 `curl`，任何 toolchain 相关 |
| `Bash(bin/devbox run claude -p "<prompt>")` | 在 VM 里拉起一个全新的 CC，传入自包含 prompt | 拉起隔离的 generator 或 evaluator 子进程 |
| `Bash(bin/devbox status)` | 看 VM 状态 | 长跑前的预检 |
| `Bash(bin/devbox doctor)` | 健康检查（OrbStack / VM / mount / passthrough） | "沙箱到底能不能用？" |
| `Bash(bin/devbox provision)` | 重跑 `setup/provision.sh`（幂等） | VM 坏了之后恢复 |
| `Bash(bin/devbox shell)` | 进交互式 VM shell | 几乎不用（LLM 看不到交互式 prompt） |
| `Bash(bin/devbox reset)` | **破坏性** —— 推倒重建 VM，要敲 `yes` | 只有用户明确同意时才用 |
| `Bash(bin/devbox --json <subcmd>)` | 同上，但输出可解析的 JSON 信封 | 程序化消费者，需要稳定的 `ok / exit_code / duration_ms / stdout / stderr` 字段时 |

完整命令参考：`bin/devbox help` 或
[`AGENTS.md` §3](../AGENTS.md#3-the-complete-bin-devbox-command-set)。

### 2a. 优先用 MCP server，不要 shell

`bin/mcp-atelier.py` 是一个 **stdio MCP server**（Python stdlib 实现，
零第三方依赖），把 `bin/devbox --json` 包成 MCP tools。runtime 支持
MCP 的时候，优先用 tool 而不是 shell：

| MCP tool | 替代什么 | 何时 |
|---|---|---|
| `mcp__atelier__run({"cmd": "pnpm test"})` | `Bash(bin/devbox run pnpm test --json)` | 任何 toolchain 调用；tool 直接返回解析好的 envelope |
| `mcp__atelier__status({})` | `Bash(bin/devbox --json status)` | 预检 |
| `mcp__atelier__doctor({})` | `Bash(bin/devbox --json doctor)` | "沙箱到底能不能用？" |
| `mcp__atelier__run_claude({"prompt": "..."})` | `Bash(bin/devbox run claude -p "...")` | 拉起隔离的 generator / evaluator 子进程 |
| `mcp__atelier__version({})` | — | 健康 ping |

在 `.mcp.json` 里挂上（本项目已经挂好）：

```json
{
  "mcpServers": {
    "atelier": {
      "type": "stdio",
      "command": "python3",
      "args": ["${CLAUDE_PROJECT_DIR}/bin/mcp-atelier.py"]
    }
  }
}
```

每次 tool call 返回
`{content: [{type: "text", text: "<json>"}], isError}`。把 `text` 当
JSON 解析；envelope 形状跟 `bin/devbox --json` 完全一致。

## 3. 宿主 vs VM —— 每个操作该跑哪

| 操作 | 宿主 | VM |
|---|:---:|:---:|
| `Read` / `Edit` / `Glob` / `Grep`（项目文件） | ✅ | （没必要） |
| `git status` / `git diff` / `git commit` / `git push` | ✅ | （没必要） |
| `pnpm install` / `pnpm test` / `npm run *` | ❌ | ✅ 走 `bin/devbox run` |
| `pytest` / `python -m venv` | ❌ | ✅ |
| `cargo build` / `go test` | ❌ | ✅ |
| `playwright`（浏览器自动化） | ❌ | ✅ |
| 网络调用（`curl`、`fetch`、API 调用） | ⚠ 优先 VM | ✅ |
| MCP 服务器（open-design、lazyweb、context7、exa、github、playwright） | ❌ | ✅（它们只在 VM 里存在） |
| 长跑的 dev server | ❌ | ✅ |
| `sudo *` / `rm -rf /` / `curl *\|bash` / 写 `~/.ssh/**`、`~/.aws/**` | ❌ | ❌（deny 掉了；不要尝试绕过） |

**经验法则：** 如果 toolchain 或服务只在 VM 里（Node、pnpm、uv、
cargo、go、gh、open-design 守护进程、MCP 服务器），在宿主上跑
它就是没意义——路由到 VM。

## 4. Harness 循环（任何非琐碎功能的默认）

atelier 为一种特定的工作设计：长跑、评审密集、多 agent。默认循环：

```
        ┌──────────────────────────────────────────────┐
        │          需求 spec（输入）                    │
        └─────────────────────┬────────────────────────┘
                              ↓
                       1. Plan（你）
                              ↓
                       2. Generate
                          （全新隔离的 CC 子进程）
                              ↓
                       3. Test + Review
                          （N 个并行 Agent subagent）
                              ↓
                       4. Gate
                          score ≥ 0.8，无 blocker
                              ↓
                  pass ───→ 5. Commit / 开 PR
                  fail ───→ 2. Generate（带 feedback）
                              ↓
                  撞 MAX_ITER ───→ 升级给人
```

完整的 5 阶段设计和隔离规则：
[`workflow.md`](workflow.md)。可跑的最小示例：
[`../examples/harness-demo/`](../examples/harness-demo/) —— 用
`bin/devbox run python examples/harness-demo/orchestrate.py` 跑。

### 硬规则

1. **Generator 和 reviewer 是不同的 agent。** 不要审自己的代码。
   Reviewer 不能看到 generator 的 transcript——只看最终代码 +
   spec。
2. **Reviewer 之间互相看不到。** 并行拉起 N 个独立的 `Agent`
   subagent，每个返回一张 score card。Orchestrator（你）收集并
   跑 gate。
3. **Gate 不可商量。** 每个 `score >= 0.8` 且 `blockers` 为空，且
   测试全绿。否则就继续迭代。
4. **人只在 gate 失败或 stuck escalation 时介入。** 不要为单个
   文件评审去 ping 人。

### 三种隔离机制（强度递增）

| 机制 | 得到什么 | 何时用 |
|---|---|---|
| **`Agent` 工具** | 父 CC 拉起 subagent。全新 context。返回一条字符串。 | 短命 evaluator（一个文件、一个测试、一个 lens）。便宜、快、隔离。 |
| **`Bash(bin/devbox run claude -p "...")`** | 完整的 CC 子进程，在 VM 里。独立的 `/proc/<pid>`、独立的 `~/.claude/`、独立的 toolchain、独立的 scratch 目录。 | 需要真实 tool use 的长跑 evaluator（整套测试、30 帧截图 diff）。 |
| **`everything-claude-code:council` skill** | 一次 tool call 拉起 N 个 reviewer。每个都是机制 A 的 subagent。 | 想快速拿多样视角的时候（UI 改动时并行跑 security + a11y + visual + boundary）。 |

**Generator 和 reviewer 之间永远不要共享 context。** Reviewer 的
transcript 是几 MB；把它并进 generator 的 context 会引起 context
rot。Generator 只能看到 score card。

## 5. Score card 的 schema

每个 reviewer 产出一个 JSON 对象，形状如下：

```json
{
  "reviewer": "security",
  "score": 0.9,
  "blockers": [
    "src/config.py:42 硬编码了 API key"
  ],
  "suggestions": [
    "用 secret manager；写下对应的环境变量文档"
  ],
  "evidence": "tests/security/output.log"
}
```

Orchestrator（你）读 N 张 card，跑 gate，要么 commit 要么把 card
作为"上一轮 review"喂回 generator 的下一轮 prompt。最小的 harness
在 [`../examples/harness-demo/`](../examples/harness-demo/)，用的
就是这个 schema 的标准实现。

## 6. 标准 orchestrator 配方

一个驱动 harness 循环的最小 Python orchestrator：

```python
import json, subprocess, sys
from pathlib import Path

MAX_ITER, GATE = 5, 0.8
SCORES = Path("score-cards")
SCORES.mkdir(exist_ok=True)
prev = ""

for i in range(1, MAX_ITER + 1):
    # 第 2 阶段：generate（VM 里的隔离子进程）
    prompt = (
        Path("feature-spec.md").read_text()
        + "\n\n# 上一轮 review feedback\n" + prev
    )
    subprocess.run([
        "bin/devbox", "run", "claude",
        "--dangerously-skip-permissions",
        "-p", prompt,
    ], check=False)

    # 第 3+4 阶段：reviewer（generator 自己的 CC 内部通过
    # Agent 工具拉起）把 score-cards/iter-<i>.json 写出来
    card = json.loads((SCORES / f"iter-{i}.json").read_text())
    if all(
        c["score"] >= GATE and not c["blockers"]
        for c in card["cards"]
    ):
        subprocess.run(["git", "add", "-A"], check=True)
        subprocess.run(
            ["git", "commit", "-m", f"feat: iter {i}"], check=True,
        )
        sys.exit(0)

    prev = json.dumps(card, indent=2)

print(f"撞 MAX_ITER={MAX_ITER}；升级给人")
sys.exit(2)
```

生产替代品加了那些无聊但关键的部分：checkpointing、stuck detection、
token budget guard、并发上限、crash 之后 resume。

| 想要什么 | 用什么 |
|---|---|
| 最小示例（这段 ~30 行） | [`../examples/harness-demo/orchestrate.py`](../examples/harness-demo/orchestrate.py) |
| 加 checkpointing + stuck detection 的生产版 | `everything-claude-code:continuous-agent-loop` |
| 完整编排 + budget guard 的生产版 | `everything-claude-code:autonomous-agent-harness` |
| 加 human-in-the-loop 监督的生产版 | `everything-claude-code:loop-operator` |

## 7. 什么时候问人

只在这些时候问：

- spec 有歧义，没法选。
- harness 撞 `MAX_ITER`（默认 5）且 blocker 几轮一样——那是
  spec 大概率有问题，不是代码。
- 命令被 deny 列表拦了（这是正确行为，不要尝试绕过）。
- 你要跑 `bin/devbox reset`（破坏性——VM 推倒）。
- 你需要装 `setup/provision.sh` 里没有的新工具（必须用户同意
  才能加）。

**不要**问这些：

- "这个跑 VM 还是宿主？"——默认 VM，除非是观察类。
- "build 绿了吗？"——跑一下就知道。
- "要不要 commit？"——gate 说了算，过了就 commit。
- "下一步呢？"——读 spec，按它走。

## 8. 下一步看哪里

| 问题 | 文档 |
|---|---|
| Portable 多 agent 规则、完整的 `bin/devbox` 参考 | [`AGENTS.md`](../AGENTS.md) |
| Claude Code 专用 harness 触发词 + 项目约定 | [`CLAUDE.md`](../CLAUDE.md) |
| 宿主 / VM 接线、组件、env 透传 | [`architecture.md`](architecture.md) |
| yolo 安全模型真正保证了什么（和不保证什么） | [`security-model.md`](security-model.md) |
| Harness 循环的细节（5 阶段、score card 设计） | [`workflow.md`](workflow.md) |
| 可跑的最小 harness 示例 | [`../examples/harness-demo/`](../examples/harness-demo/) |
| 为什么选 OrbStack 而不是 Docker Desktop / Lima / Vagrant | [`comparison.md`](comparison.md) |
| 这个项目为什么存在（四根支柱） | [`design.md`](design.md) |

如果只能读三份文档：这一份、
[`AGENTS.md`](../AGENTS.md)、和
[`../examples/harness-demo/`](../examples/harness-demo/) 的 harness
demo。
