# Agent quickstart — using atelier from another AI agent

> One-page contract for an AI agent consuming atelier. Deliberately
> compact: read it once, keep it open. For richer Claude Code-specific
> triggers and project conventions, read [`../CLAUDE.md`](../CLAUDE.md).
> For the portable multi-agent entry point, read
> [`../AGENTS.md`](../AGENTS.md).

## TL;DR (4 lines)

- **Heavy work** → `Bash(bin/devbox run <cmd>)`. The host's toolchain
  is empty on purpose — there's nothing to run there.
- **Long-running / isolated work** →
  `Bash(bin/devbox run claude -p "<self-contained prompt>")` for a
  fresh CC subprocess inside the VM (own `/proc`, own `~/.claude`,
  own toolchain).
- **Code review** → spawn N independent `Agent` subagents in
  parallel; each returns one score card. Never review your own code.
- **The gate is non-negotiable.** Every reviewer score ≥ 0.8 and
  zero blockers before anything commits.

## 1. What atelier gives you

A disposable Ubuntu 24.04 VM (`atelier`) with **Node 24 / pnpm /
Python 3.12 / uv / Go / Rust / gh / Playwright** plus MCP servers
(**open-design**, **lazyweb**, **context7**, **exa**, **github**)
preinstalled. Your project files (on the host) auto-mount at
`/mnt/mac/...` inside the VM — same bytes, no copy. The host Mac
stays inert: no Node, no Python, no shell-rc edits, no config files
touched.

The wall: `../.claude/settings.json` permit-lists `Bash(bin/devbox*)`,
`Bash(git*)`, observation tools, `Agent`, `TodoWrite`, and
deny-lists the unrecoverable mistakes (`rm -rf /`, `sudo`, `curl|bash`,
`~/.ssh/**`, `~/.aws/**`, …). With
`--dangerously-skip-permissions` the architecture — not the deny
list — is what bounds the blast radius.

## 2. The command set you should know

| Command | What it does | When an agent uses it |
|---|---|---|
| `Bash(bin/devbox run <cmd>)` | Run a command in the VM; return its output | `pnpm test`, `npm run build`, `cargo build`, `pytest`, `playwright`, `curl` inside the sandbox, anything toolchain-y |
| `Bash(bin/devbox run claude -p "<prompt>")` | Spawn a fresh CC inside the VM with a self-contained prompt | Spawning an isolated generator or evaluator subprocess |
| `Bash(bin/devbox status)` | Show VM state | Pre-flight check before a long run |
| `Bash(bin/devbox doctor)` | Health check (OrbStack / VM / mount / passthrough) | "Is the sandbox actually working?" |
| `Bash(bin/devbox provision)` | Re-run `setup/provision.sh` (idempotent) | Recovery from a broken VM |
| `Bash(bin/devbox shell)` | Open an interactive VM shell | Almost never (you can't see an interactive prompt from an LLM) |
| `Bash(bin/devbox reset)` | **DESTRUCTIVE** — nuke + recreate the VM, asks for `yes` | Only when the user explicitly approves |
| `Bash(bin/devbox --json <subcmd>)` | Same as above, but emits a parseable JSON envelope | Programmatic consumers that need stable `ok / exit_code / duration_ms / stdout / stderr` fields |

Full command reference: `bin/devbox help` or
[`AGENTS.md` §3](../AGENTS.md#3-the-complete-bin-devbox-command-set).

### 2a. Prefer the MCP server over the shell

`bin/mcp-atelier.py` is a **stdio MCP server** (Python stdlib, zero
third-party deps) that wraps `bin/devbox --json` as MCP tools. When
the runtime you're running on supports MCP, prefer the tools over
shelling out:

| MCP tool | Replaces | When |
|---|---|---|
| `mcp__atelier__run({"cmd": "pnpm test"})` | `Bash(bin/devbox run pnpm test --json)` | Any toolchain call; the tool returns the parsed envelope |
| `mcp__atelier__status({})` | `Bash(bin/devbox --json status)` | Pre-flight check |
| `mcp__atelier__doctor({})` | `Bash(bin/devbox --json doctor)` | "Is the sandbox working?" |
| `mcp__atelier__run_claude({"prompt": "..."})` | `Bash(bin/devbox run claude -p "...")` | Spawning an isolated generator / evaluator subprocess |
| `mcp__atelier__version({})` | — | Health ping |

Wire it in `.mcp.json` (already done for this project). The
contract:

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

Each tool call returns `{content: [{type: "text", text: "<json>"}], isError}`. Parse `text` as JSON; the envelope shape is identical to `bin/devbox --json`.

## 3. Host vs VM — where each operation belongs

| Operation | Host | VM |
|---|:---:|:---:|
| `Read` / `Edit` / `Glob` / `Grep` (project files) | ✅ | (no benefit) |
| `git status` / `git diff` / `git commit` / `git push` | ✅ | (no benefit) |
| `pnpm install` / `pnpm test` / `npm run *` | ❌ | ✅ via `bin/devbox run` |
| `pytest` / `python -m venv` | ❌ | ✅ |
| `cargo build` / `go test` | ❌ | ✅ |
| `playwright` (browser automation) | ❌ | ✅ |
| Network calls (`curl`, `fetch`, API calls) | ⚠ prefer VM | ✅ |
| MCP servers (open-design, lazyweb, context7, exa, github, playwright) | ❌ | ✅ (they only exist inside the VM) |
| Long-running dev servers | ❌ | ✅ |
| `sudo *` / `rm -rf /` / `curl *\|bash` / writes to `~/.ssh/**`, `~/.aws/**` | ❌ | ❌ (deny-listed; don't try to bypass) |

**Rule of thumb:** if the toolchain or service only exists in the
VM (Node, pnpm, uv, cargo, go, gh, the open-design daemon, MCP
servers), running it on the host is meaningless — route it.

## 4. The harness loop (default for non-trivial features)

Atelier is designed for a specific kind of work: long-running,
review-heavy, multi-agent. The default loop:

```
        ┌──────────────────────────────────────────────┐
        │          Feature spec (input)                │
        └─────────────────────┬────────────────────────┘
                              ↓
                       1. Plan (you)
                              ↓
                       2. Generate
                          (fresh isolated CC subprocess)
                              ↓
                       3. Test + Review
                          (N parallel Agent subagents)
                              ↓
                       4. Gate
                          score ≥ 0.8, no blockers
                              ↓
                  pass ───→ 5. Commit / open PR
                  fail ───→ 2. Generate (with feedback)
                              ↓
                  MAX_ITER hit ───→ escalate to the human
```

Full 5-stage design and isolation rules:
[`workflow.md`](workflow.md). Runnable minimal example:
[`../examples/harness-demo/`](../examples/harness-demo/) — run it with
`bin/devbox run python examples/harness-demo/orchestrate.py`.

### Hard rules

1. **Generator and reviewer are separate agents.** Don't review
   your own code. The reviewer must not see the generator's
   transcript — only the final code + the spec.
2. **Reviewers don't see each other.** Spawn N independent `Agent`
   subagents in parallel. Each returns one score card. The
   orchestrator (you) collects and gates.
3. **The gate is non-negotiable.** Every `score >= 0.8` AND empty
   `blockers` AND green tests. Otherwise iterate.
4. **The human is only in the loop at gate failure or stuck
   escalation.** Don't ping for individual file reviews.

### Three isolation mechanisms (in increasing weight)

| Mechanism | What you get | When to use |
|---|---|---|
| **`Agent` tool** | Parent CC spawns a subagent. Fresh context. Returns one string. | Short-lived evaluators (one file, one test, one lens). Cheap, fast, isolated. |
| **`Bash(bin/devbox run claude -p "...")`** | Full CC subprocess inside the VM. Own `/proc/<pid>`, own `~/.claude/`, own toolchain, own scratch dir. | Long-running evaluators that need real tool use (full test suite, screenshot diff over 30 frames). |
| **`everything-claude-code:council` skill** | N reviewers in one tool call. Each is a Mechanism-A subagent. | When you want diverse perspectives fast (security + a11y + visual + boundary in parallel for a UI change). |

**Never share context between generator and reviewer.** The reviewer's
transcript is megabytes; merging it into the generator's context
causes context rot. The generator should only see the score card.

## 5. Score card schema

Each reviewer produces a JSON object shaped like:

```json
{
  "reviewer": "security",
  "score": 0.9,
  "blockers": [
    "Hardcoded API key in src/config.py:42"
  ],
  "suggestions": [
    "Use a secret manager; document the env var"
  ],
  "evidence": "tests/security/output.log"
}
```

The orchestrator (you) reads N cards, applies the gate, and either
commits or feeds the cards back to the next generator iteration as
"previous review". The minimal harness at
[`../examples/harness-demo/`](../examples/harness-demo/) uses the
exact shape above and is the canonical reference implementation.

## 6. Canonical orchestrator recipe

A minimal Python orchestrator that drives the harness loop:

```python
import json, subprocess, sys
from pathlib import Path

MAX_ITER, GATE = 5, 0.8
SCORES = Path("score-cards")
SCORES.mkdir(exist_ok=True)
prev = ""

for i in range(1, MAX_ITER + 1):
    # Stage 2: generate (isolated subprocess inside the VM)
    prompt = (
        Path("feature-spec.md").read_text()
        + "\n\n# Previous review feedback\n" + prev
    )
    subprocess.run([
        "bin/devbox", "run", "claude",
        "--dangerously-skip-permissions",
        "-p", prompt,
    ], check=False)

    # Stage 3+4: reviewers (spawned inside the generator's own CC
    # via the Agent tool) write score-cards/iter-<i>.json
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

print(f"hit MAX_ITER={MAX_ITER}; escalating")
sys.exit(2)
```

Production alternatives add the boring-but-critical bits:
checkpointing, stuck detection, token budget guards, concurrency
caps, resume from crash.

| What | Use |
|---|---|
| Minimal example (this snippet, ~30 lines) | [`../examples/harness-demo/orchestrate.py`](../examples/harness-demo/orchestrate.py) |
| Production with checkpointing + stuck detection | `everything-claude-code:continuous-agent-loop` |
| Production with full orchestration + budget guards | `everything-claude-code:autonomous-agent-harness` |
| Production with human-in-the-loop supervision | `everything-claude-code:loop-operator` |

## 7. When to ask the human

Ask only when:

- The spec is ambiguous and you can't proceed without a choice.
- The harness hits `MAX_ITER` (default 5) with the same blocker
  across iterations — the spec is probably wrong, not the code.
- A command hit the deny list (correct behavior — don't try to
  bypass).
- You're about to run `bin/devbox reset` (DESTRUCTIVE — wipes the
  VM).
- You need to install a new tool that isn't in
  `setup/provision.sh` (user must approve adding it).

**Don't** ask for:

- "Should I run this in the VM or on the host?" — assume VM unless
  the operation is observation-only.
- "Is the build green?" — run the build and see.
- "Should I commit?" — the gate decides; if it passes, commit.
- "What's the next step?" — read the spec, follow it.

## 8. Where to go next

| Question | Doc |
|---|---|
| Portable multi-agent rules, full `bin/devbox` reference | [`AGENTS.md`](../AGENTS.md) |
| Claude Code-specific harness triggers + project conventions | [`CLAUDE.md`](../CLAUDE.md) |
| Host / VM wiring, components, env passthrough | [`architecture.md`](architecture.md) |
| What the yolo-safety model actually guarantees (and doesn't) | [`security-model.md`](security-model.md) |
| The harness loop in detail (5 stages, score card design) | [`workflow.md`](workflow.md) |
| Runnable minimal harness example | [`../examples/harness-demo/`](../examples/harness-demo/) |
| Why OrbStack over Docker Desktop / Lima / Vagrant | [`comparison.md`](comparison.md) |
| Why this project exists at all (the four pillars) | [`design.md`](design.md) |

If you only have time to read three things: this document,
[`AGENTS.md`](../AGENTS.md), and the harness demo at
[`../examples/harness-demo/`](../examples/harness-demo/).
