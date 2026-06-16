# The yolo-harness workflow

> This is the workflow atelier is **designed for**, not just capable
> of. The sandbox makes it safe; this loop makes the work good.

The sandbox (VM isolation) is one half of atelier. The other half is
the **multi-agent harness loop**: a closed pipeline where a generator
writes code, an independent evaluator grades it, and a gate decides
whether to ship — looping until the work meets a quality bar, with
the human only arbitrating when the loop is stuck.

The loop is the default for any non-trivial feature work. The
sandbox makes it safe to run unattended.

## The five stages

```
            ┌───────────────────────────────────────────────┐
            │              Feature spec (in)               │
            └─────────────────────┬─────────────────────────┘
                                  ↓
                          1. Plan (fast)
                                  ↓
                          2. Generate
                                  ↓
                          3. Test + Review (parallel)
                                  ↓
                          4. Gate (decision)
                                  ↓
                          pass ──→ 5. Commit / open PR
                          fail ──→ 2. Generate (with feedback)
                                  ↓
                          (max iter reached) ──→ escalate
```

### 1. Plan (orchestrator)

Same CC instance that received the request. Reads the feature spec,
decomposes it into a small set of tasks, identifies the
non-negotiable acceptance criteria, and decides which roles to
spawn. This stage is fast — minutes, not hours.

**Output:** `feature-spec.md` — the canonical input to stage 2.

### 2. Generate (developer agent)

**Always a fresh, isolated CC instance.** Spawned via
`bin/devbox run claude --dangerously-skip-permissions -p "$(cat feature-spec.md)"` or
via the `Agent` tool with a developer-flavored prompt.

Properties:
- Own context window
- Own session history
- Writes to the project tree
- Reads the spec; does **not** read the previous iteration's review
  transcript (only the score card)
- Runs linters, type-checks, and the project's own test suite
  before declaring done

**Output:** code changes in the project tree + a self-reported
summary (`generator-summary.md`).

### 3. Test + Review (parallel evaluators)

This stage runs **multiple independent agents in parallel**:

- **Tester** (functional): runs the test suite, captures failures,
  reports pass/fail per test
- **Reviewer: correctness** — does the code do what the spec says?
- **Reviewer: security** — auth bypass, injection, secrets in
  logs, dependency CVEs
- **Reviewer: a11y** — WCAG 2.2 AA, keyboard, screen reader
- **Reviewer: visual** — Playwright screenshot vs. design spec,
  pixel diff, layout regression
- **Reviewer: boundary** — empty input, huge input, unicode, RTL,
  timezone, leap seconds, network failures, disk full, OOM

Each reviewer is its own CC instance / Agent invocation. They do
**not** know what the other reviewers said. They do not know the
generator's full transcript. They only see the final code.

**Output:** a `score-card.json` per reviewer:

```json
{
  "reviewer": "security",
  "score": 0.9,
  "blockers": [
    "Hardcoded API key in src/config.py:42"
  ],
  "suggestions": [
    "Consider using a secret manager; document the env var"
  ],
  "evidence": "tests/security/output.log"
}
```

### 4. Gate (decision)

The orchestrator (stage 1) consumes the score cards and decides:

- **Pass** if all `score >= 0.8` AND no `blockers` AND test suite is
  green
- **Fail** otherwise — the score card is fed back to stage 2 as the
  next iteration's "previous review"

The gate is also a **checkpoint**: it persists the score card and
a git ref so a crash mid-loop can resume. See
[`continuous-agent-loop`](#continuous-agent-loop) below.

### 5. Commit / open PR (or escalate)

If the gate passes, the orchestrator commits the code, pushes the
branch, opens a PR with the score cards attached, and stops.

If the loop hits `MAX_ITERATIONS` (default: 5) without passing, the
orchestrator **stops and asks the human** — the spec is probably
ambiguous, or there's a real architectural disagreement that the
agents can't resolve. This is the only human-in-the-loop step in
the happy path.

## Isolation, the load-bearing property

The whole loop is built on the principle that **generator and
evaluator never share context**. The reasons:

| Risk | What isolation prevents |
|------|-------------------------|
| **Context rot** | The generator's context is *small* and stable. The reviewer transcripts are megabytes each. If they merged, the generator would either lose them (low signal) or drown in them (high noise). |
| **Confirmation bias** | If the generator saw the reviewer's reasoning, it would optimize for *pleasing* the reviewer rather than *being correct*. Independent grading is closer to ground truth. |
| **Self-deception** | The generator's job is to *make the gate pass*, not to *find the right answer*. A separate reviewer has different incentives. |
| **Blast radius** | A malicious or buggy MCP server loaded by the reviewer can't see the generator's session — they don't share any host file, env var, or network socket. |

Three isolation mechanisms, in increasing weight:

#### Mechanism A: `Agent` tool (subagent)

The parent CC instance uses the `Agent` tool to spawn a subagent.
The subagent:

- Gets a **fresh context window** (the parent's transcript is not
  pre-loaded)
- Returns a single string to the parent (a summary, a verdict, a
  patch)
- The parent's context sees only that returned string

This is the right tool for short-lived evaluators (a single file
review, a single test run). Cheap, fast, isolated.

#### Mechanism B: full CC process (`bin/devbox run claude ...`)

For longer-running evaluators (an entire test suite, a visual
regression pass over 30 screenshots), spawn a full CC process
inside the VM. It:

- Is a separate OS process with its own `/proc/<pid>/...`
- Has its own `~/.claude/` (config, cache, history)
- Reads the project tree but writes its own scratch dir
  (`/tmp/eval-<timestamp>/`)
- Returns a JSON file (`/tmp/eval-<timestamp>/score-card.json`)
  that the orchestrator picks up

This is the right tool for evaluators that need real tool use —
file reading, shell, browser, network — but should not pollute the
generator's session.

#### Mechanism C: `council` skill (N reviewers at once)

For breadth, the `everything-claude-code:council` skill spawns N
reviewers (one per lens) in a single tool call. Each is a
Mechanism A subagent. The orchestrator gets back N score cards,
not N transcripts.

This is the right tool when you need diverse perspective fast
(security + a11y + visual in parallel for a UI change).

## Closed-loop mechanics

The `everything-claude-code:continuous-agent-loop` skill (and its
companion `loop-operator`) handle the boring-but-critical parts:

- **Iteration counter** — `MAX_ITERATIONS=5` by default
- **Checkpointing** — after each gate, persist the score card
  + git SHA so a crash can resume
- **Stuck detection** — if `score < threshold` for 2 consecutive
  iterations with the same blocker, escalate (the spec is
  probably wrong)
- **Budget guard** — token spend cap; if `tokens > MAX_TOKENS`,
  escalate
- **Concurrency cap** — at most N parallel reviewers at once
  (default N=4 to avoid hammering the host)

A minimal Python orchestrator looks like this:

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
    # stage 2: generate (separate CC process, separate context)
    subprocess.run([
        "bin/devbox", "run", "claude",
        "--dangerously-skip-permissions",
        "-p", SPEC.read_text() + "\n\n# Previous review feedback\n" + prev_feedback,
    ], check=True)

    # stage 3: evaluate (parallel subagents via the Agent tool — handled inside
    # the generator's own --dangerously-skip-permissions loop, OR spawned here)
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

The real implementation is in
`everything-claude-code:autonomous-agent-harness` / `continuous-agent-loop`
skills — they handle process supervision, resume, and stuck
detection. Use the skills; don't roll your own.

## Quality bars in practice

For a "typical" feature (1–3 files, no architecture change):

| Reviewer | Bar | Common failure mode |
|----------|-----|---------------------|
| correctness | 0.8 | spec was ambiguous; gate fails on a missing edge case |
| security | 0.8 | unescaped user input; gate fails on a Bash injection finding |
| a11y | 0.7 (lower for non-UI) | color contrast on a button; gate fails |
| visual | 0.8 | pixel diff > 2% from spec |
| boundary | 0.7 | empty input crashes; gate fails |
| tests | must pass | one flaky test; gate fails |

For larger work (architecture change, new module), add:

- `architect` — does the change match the existing patterns?
- `dependency-reviewer` — are we pulling in a fork / EOL package?
- `performance-optimizer` — N+1 query, missing index, hot loop

For UI work, also add:

- `lazyweb-design-research` — pull real product references
- `open-design` — the design system spec must be loaded before the
  generator runs

## When NOT to use the harness

The harness is overkill for:

- Single-line typo fixes
- Documentation tweaks
- Trivial dependency bumps
- One-line configuration changes

For these, the editor + a single test run is enough. The harness
is for **non-trivial feature work that needs a second (and third,
and fourth) pair of eyes before it ships**.

The threshold is roughly: "would I be sad if I had to revert this
in production?" If yes, run the harness. If no, just commit.

## Where to learn more

- `everything-claude-code:autonomous-agent-harness` — the
  meta-orchestrator that wires all of this together
- `everything-claude-code:council` — N-perspective review in one
  call
- `everything-claude-code:continuous-agent-loop` — checkpointing +
  stuck detection + budget guards
- `everything-claude-code:loop-operator` — human-in-the-loop
  supervision of a running harness
- `everything-claude-code:gateguard` / `quality-gate` /
  `verification-loop` — the gate logic in different shapes
- `everything-claude-code:gan-build` — the original
  Generator+Evaluator pattern this design derives from
