# harness-demo — minimal runnable example of the atelier harness loop

This directory shows the harness loop end-to-end with a toy feature:
implementing a `slugify(text)` function with tests. The point is to
show the **shape** of the loop, not to ship a useful library.

## What it does

```
feature-spec.yaml
        │
        ▼
   orchestrate.py
        │
        │ spawn fresh `claude` subprocess (generator, own context)
        ▼
   generator: writes demo/slugify.py + demo/test_slugify.py
              runs pytest, fixes until green
              spawns 4 reviewer subagents in PARALLEL (Agent tool)
              writes score-cards/iter-N.json
        │
        ▼
   gate: all scores ≥ 0.8 AND no blockers
        │
   pass ─┴── fail ──→ re-spawn generator with score-card feedback
   │                     loop until pass or MAX_ITER
   ▼
commit & exit   OR   escalate (exit 2) at MAX_ITER
```

## Files

| File | Purpose |
|------|---------|
| `feature-spec.yaml` | The spec the generator reads — acceptance criteria, test cases, reviewer lenses. |
| `orchestrate.py` | The loop driver. Spawns generator, reads score cards, applies gate. ~200 lines. |
| `demo/` | Created at runtime by the generator. Gitignored. |
| `score-cards/` | Created at runtime by the generator. Gitignored. |
| `.gitignore` | Keeps the example clean between runs. |

## How to run

```bash
# from the atelier project root, on the host
bin/devbox run python examples/harness-demo/orchestrate.py
```

Or step into the VM first (useful for poking at intermediate state):

```bash
bin/devbox shell
cd /mnt/mac/.../examples/harness-demo
python orchestrate.py --clean --max-iter 5
```

Flags:

- `--max-iter N` — bail after N iterations (default: 5)
- `--gate 0.8` — per-reviewer score threshold (default: 0.8)
- `--clean` — wipe `demo/` and `score-cards/` before starting

## What to expect

A typical run looks like:

```
=== iteration 1/5 ===
  $ claude --dangerously-skip-permissions -p <prompt>
  scores: correctness=0.85, security=0.95, boundary=0.60, test=0.90
  gate:   FAIL (1 blocker)
  - boundary blocker: leading/trailing dashes not trimmed

=== iteration 2/5 ===
  $ claude --dangerously-skip-permissions -p <prompt>
  scores: correctness=0.95, security=0.95, boundary=0.90, test=0.95
  gate:   PASS

✓ GATE PASS at iteration 2
  ✓ committed
```

Common first-iteration failures:

- Forgetting to trim leading/trailing dashes (boundary reviewer catches it)
- Using `re.sub` without ASCII-folding for diacritics (correctness reviewer)
- Not handling all-whitespace input (boundary reviewer)
- Test cases that don't actually run (test reviewer)

Inspect intermediate score cards:

```bash
cat score-cards/iter-1.json | jq
cat score-cards/iter-2.json | jq
```

## What this demo is NOT

This is a teaching toy. The production harness adds:

| Capability | This demo | Production (`autonomous-agent-harness`) |
|---|---|---|
| Per-iteration checkpointing | no | yes — crash mid-loop, resume |
| Stuck detection (same blocker N×) | no | yes — escalate early |
| Token budget guards | no | yes — stop at MAX_TOKENS |
| Concurrency caps | no | yes — at most N parallel reviewers |
| Parallel generators | no | sometimes — useful for ambiguous specs |
| Resume from crash | no | yes — git SHA + score-card persistence |
| Human-in-the-loop operator | no | yes via `loop-operator` skill |

Use the production skills for real work. This file's job is to make
the pattern concrete enough that the production code makes sense.

## Architectural notes

**Why is the generator a separate CC subprocess, but the reviewers are
Agent tool subagents?** The reviewers don't need their own OS process
— context isolation is enough. The generator, by contrast, is the
agent that runs the longest, makes the most tool calls, and writes the
most files; giving it a separate process keeps its failures from
polluting the orchestrator's session.

**Why does the orchestrator pass the spec as `-p` text rather than a
file path?** So the prompt is self-contained — no surprise file reads
outside the orchestrator's control. The generator's only job is to
parse the prompt.

**Why `--dangerously-skip-permissions`?** Because the whole point of
atelier is that you can. The deny list in `.claude/settings.json` is
the backstop; the VM is the wall. Drop the flag if you want a tighter
gate during demo runs.

## See also

- [`docs/workflow.md`](../../docs/workflow.md) — full design (5 stages,
  isolation mechanisms, score card schema, when NOT to use)
- [`CLAUDE.md`](../../CLAUDE.md) — the default workflow section
- `~/.claude/skills/harness/SKILL.md` — the natural-language trigger
  ("用 harness", "多 agent 评审", "yolo 跑这个", ...)
- [`everything-claude-code:autonomous-agent-harness`](../../README.md)
  — the production implementation