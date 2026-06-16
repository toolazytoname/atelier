# Yolo-harness 工作流

> 这个工作流是 atelier **为它设计的**，不只是"能跑"。沙箱让它安全；
> 这个循环让它质量高。

沙箱（VM 隔离）是 atelier 的一半。另一半是**多 agent harness 循环**：
一条封闭流水线，generator 写代码，独立的 evaluator 评分，gate 决定是否发布——
循环直到工作达到质量线，期间人类只在循环卡住时仲裁。

这个循环是任何非琐碎功能开发的默认。沙箱让它能放心 unattended 地跑。

## 五阶段

```
            ┌───────────────────────────────────────────────┐
            │              Feature spec (in)               │
            └─────────────────────┬─────────────────────────┘
                                  ↓
                          1. Plan（快速）
                                  ↓
                          2. Generate
                                  ↓
                          3. Test + Review（并行）
                                  ↓
                          4. Gate（决策）
                                  ↓
                          pass ──→ 5. Commit / 开 PR
                          fail ──→ 2. Generate（带反馈）
                                  ↓
                          (max iter 撞到) ──→ 升级
```

### 1. Plan（orchestrator）

就是收到请求的那个 CC 实例。读 feature spec，拆成一小批任务，定下不可
妥协的验收标准，决定要起哪些角色。这一阶段很快——几分钟，不是几小时。

**输出：** `feature-spec.md` —— 第 2 阶段的规范化输入。

### 2. Generate（developer agent）

**永远是一个全新的、隔离的 CC 实例。** 通过
`bin/devbox run claude --dangerously-skip-permissions -p "$(cat feature-spec.md)"`
起，或者用 `Agent` 工具带一个 developer 味的 prompt。

属性：

- 自己的 context window
- 自己的 session 历史
- 往项目树里写
- 只读 spec；**不**读上一轮的评审 transcript（只读 score card）
- 宣布完成前跑 linter、type-check 和项目自己的测试套

**输出：** 项目树里的代码变更 + 自我汇报摘要（`generator-summary.md`）。

### 3. Test + Review（并行 evaluator）

这一阶段跑**多个独立 agent，并行**：

- **Tester（功能性）**：跑测试套，抓失败，逐项报告 pass/fail
- **Reviewer: correctness** —— 代码做的是 spec 说的吗？
- **Reviewer: security** —— 鉴权绕过、注入、日志里的凭据、依赖 CVE
- **Reviewer: a11y** —— WCAG 2.2 AA、键盘、屏幕阅读器
- **Reviewer: visual** —— Playwright 截图 vs design spec，pixel diff，布局回归
- **Reviewer: boundary** —— 空输入、巨大输入、unicode、RTL、时区、闰秒、
  网络失败、磁盘满、OOM

每个 reviewer 都是独立的 CC 实例 / Agent 调用。它们**不知道**别的 reviewer
说了什么。它们不知道 generator 的完整 transcript。它们只看最终代码。

**输出：** 每个 reviewer 一份 `score-card.json`：

```json
{
  "reviewer": "security",
  "score": 0.9,
  "blockers": [
    "src/config.py:42 硬编码了 API key"
  ],
  "suggestions": [
    "用 secret manager；文档化环境变量"
  ],
  "evidence": "tests/security/output.log"
}
```

### 4. Gate（决策）

orchestrator（第 1 阶段）吃下所有 score card，决定：

- **Pass** —— 全部 `score >= 0.8` 且无 `blockers` 且测试套全绿
- **Fail** —— 否则，score card 喂回第 2 阶段作为下一轮的"上一轮评审"

gate 同时也是**checkpoint**：落 score card 加 git ref，循环中途崩了能从
checkpoint 续。见下面的 [`continuous-agent-loop`](#closed-loop-mechanics)。

### 5. Commit / 开 PR（或升级）

如果 gate 通过，orchestrator 提交代码、推分支、开 PR（附上 score card），停。

如果循环撞 `MAX_ITERATIONS`（默认 5）还没过，orchestrator **停下问人** ——
spec 大概率有歧义，或者有个架构层面的分歧 agent 自己解不了。这是 happy path
里唯一的人类介入点。

## 隔离，承重的属性

整条循环建在一个原则上：**generator 和 evaluator 永远不共享 context**。原因：

| 风险 | 隔离防的是什么 |
|------|----------------|
| **Context rot** | generator 的 context 是**小**且稳定的。评审 transcript 每个好几 MB。merge 起来 generator 要么丢（信号低）要么淹（噪声大）。 |
| **Confirmation bias** | generator 看到评审者的推理，就会优化成"讨好评审者"而不是"做对"。独立打分更接近真相。 |
| **自我欺骗** | generator 的工作是"让 gate 过"，不是"找到正确答案"。独立的 reviewer 有不同的激励。 |
| **爆炸半径** | reviewer 加载的恶意或有 bug 的 MCP server 看不见 generator 的 session —— 它们不共享任何宿主文件、环境变量、网络 socket。 |

三种隔离机制，按重量递增：

#### Mechanism A：`Agent` 工具（subagent）

父 CC 实例用 `Agent` 工具起 subagent。subagent：

- 拿到一个**全新的 context window**（父的 transcript 不会预加载）
- 只回一个字符串给父（摘要、判定、patch）
- 父的 context 只看到那个返回的字符串

这是短命 evaluator（单文件评审、单测试跑）的正确工具。便宜、快、隔离。

#### Mechanism B：完整 CC 进程（`bin/devbox run claude ...`）

对长跑 evaluator（整个测试套、30 张截图的视觉回归），在 VM 里起一个完整
CC 进程。它：

- 是独立的 OS 进程，有自己的 `/proc/<pid>/...`
- 有自己的 `~/.claude/`（配置、缓存、历史）
- 读项目树但写自己的 scratch 目录（`/tmp/eval-<timestamp>/`）
- 回一个 JSON 文件（`/tmp/eval-<timestamp>/score-card.json`）给 orchestrator 拿

这是需要真正工具用（读文件、shell、浏览器、网络）但不该污染 generator session
的 evaluator 的正确工具。

#### Mechanism C：`council` skill（一次 N 个 reviewer）

为了广度，`everything-claude-code:council` skill 在一个 tool call 里起 N 个
reviewer（一个一个 lens）。每个都是 Mechanism A 的 subagent。orchestrator
拿回 N 张 score card，不是 N 份 transcript。

这是需要快速多视角（UI 改动一次性要安全 + a11y + 视觉）的正确工具。

## 闭环机制

`everything-claude-code:continuous-agent-loop` skill（以及它的伙伴
`loop-operator`）处理那些无聊但关键的活儿：

- **Iteration 计数** —— `MAX_ITERATIONS=5` 默认
- **Checkpoint** —— 每个 gate 后落 score card + git SHA，崩了能续
- **Stuck 检测** —— 同一 blocker 连续 2 轮 `< threshold`，升级（spec 大概率错了）
- **预算守卫** —— token 花费上限；`tokens > MAX_TOKENS` 就升级
- **并发上限** —— 同时最多 N 个并行 reviewer（默认 N=4，避免打爆宿主）

一个最简 Python orchestrator 长这样：

```python
# examples/harness-demo/orchestrate.py
import json, subprocess, sys, time
from pathlib import Path

SPEC          = Path("feature-spec.md")
MAX_ITER      = 5
GATE_SCORE    = 0.8
SCORE_CARDS   = Path("score-cards")
SCORE_CARDS.mkdir(exist_ok=True)

prev_feedback = ""

for i in range(1, MAX_ITER + 1):
    print(f"\n=== iteration {i} ===")
    # stage 2: generate（独立 CC 进程，独立 context）
    subprocess.run([
        "bin/devbox", "run", "claude",
        "--dangerously-skip-permissions",
        "-p", SPEC.read_text() + "\n\n# Previous review feedback\n" + prev_feedback,
    ], check=True)

    # stage 3: evaluate（通过 Agent 工具的并行 subagent ——
    # 在 generator 自己的 --dangerously-skip-permissions 循环里处理，
    # 或者在这里另起）
    score_card = json.loads((SCORE_CARDS / f"iter-{i}.json").read_text())

    # stage 4: gate
    if all(c["score"] >= GATE_SCORE for c in score_card["cards"]) \
       and not any(c["blockers"] for c in score_card["cards"]):
        print("GATE PASS — committing")
        subprocess.run(["git", "add", "-A"], check=True)
        subprocess.run(["git", "commit", "-m", f"feat: {SPEC.stem} (harness iter {i})"], check=True)
        sys.exit(0)

    prev_feedback = json.dumps(score_card, indent=2)
    print(f"  gate fail: {[c['reviewer'] for c in score_card['cards'] if c['score'] < GATE_SCORE]}")
    time.sleep(2)

print(f"hit MAX_ITER={MAX_ITER}, escalating")
sys.exit(2)
```

真正的实现在 `everything-claude-code:autonomous-agent-harness` /
`continuous-agent-loop` skill 里——它们处理进程监督、断点续跑、stuck 检测。
**用 skill，别自己撸。**

## 实际的质量线

对"典型"feature（1-3 个文件，无架构变更）：

| Reviewer | 线 | 常见失败模式 |
|----------|-----|-------------|
| correctness | 0.8 | spec 有歧义；gate 挂在漏掉的边界 case |
| security | 0.8 | 没转义的 user input；gate 挂在 Bash injection 发现 |
| a11y | 0.7（非 UI 更低） | 按钮颜色对比；gate 挂 |
| visual | 0.8 | pixel diff > 2% 跟 spec 对不上 |
| boundary | 0.7 | 空输入崩；gate 挂 |
| tests | 必须过 | 一个 flaky test；gate 挂 |

对更大的活（架构变更、新模块），加：

- `architect` —— 改动符合现有模式吗？
- `dependency-reviewer` —— 我们有没有拉 fork / EOL 包？
- `performance-optimizer` —— N+1 查询、缺索引、热循环

对 UI 工作，再加：

- `lazyweb-design-research` —— 拉真实产品参考
- `open-design` —— design system spec 必须在 generator 跑前加载

## 什么时候**不**用 harness

harness 对这些是 overkill：

- 单行 typo 修复
- 文档微调
- 琐碎的依赖 bump
- 单行配置改动

这些用编辑器 + 单次测试跑就够了。harness 是给**非琐碎、上线 revert 会心疼的功能工作**
准备的、需要第二（第三、第四）双眼睛的那种。

阈值大致是："上线被 revert 我会心疼吗？"会就跑 harness，不会就 commit。

## 哪里学更多

- `everything-claude-code:autonomous-agent-harness` —— 把这些都串起来的
  meta-orchestrator
- `everything-claude-code:council` —— 一个 call 拿 N 视角评审
- `everything-claude-code:continuous-agent-loop` —— checkpoint + stuck 检测 + 预算守卫
- `everything-claude-code:loop-operator` —— 跑着 harness 的人类监督
- `everything-claude-code:gateguard` / `quality-gate` / `verification-loop` ——
  不同形状的 gate 逻辑
- `everything-claude-code:gan-build` —— 这个设计衍生自的 Generator+Evaluator 原版