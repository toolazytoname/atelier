#!/usr/bin/env python3
"""Atelier harness demo — minimal orchestrator for the closed-loop pattern.

This is a toy implementation that shows the SHAPE of the harness loop:

    spec -> generator -> parallel reviewers -> gate -> commit-or-iterate

For real work, use ``everything-claude-code:autonomous-agent-harness`` or
``continuous-agent-loop``. They add checkpointing, stuck detection,
token budgets, and concurrency caps. This demo omits all of that for
clarity.

Usage::

    # from the atelier project root, on the host
    bin/devbox run python examples/harness-demo/orchestrate.py

    # or step into the VM first
    bin/devbox shell
    cd /mnt/mac/.../examples/harness-demo
    python orchestrate.py

The orchestrator runs INSIDE the VM. It spawns ``claude`` as a
subprocess for the generator; the generator then uses the Agent tool
internally to spawn the 4 reviewer subagents in parallel. All of that
stays inside the VM — the host sees nothing.
"""

from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

ROOT     = Path(__file__).resolve().parent
SPEC     = ROOT / "feature-spec.yaml"
SCORES   = ROOT / "score-cards"
WORK     = ROOT  # generator writes demo/ + score-cards/ here

GATE_SCORE = 0.8      # every reviewer must hit this or higher
MAX_ITER   = 5        # bail and ask the human after this many tries
CLAUDE_BIN = "claude" # must be on PATH inside the VM

# ---------------------------------------------------------------------------
# Generator prompt — what the fresh CC subprocess sees on -p
# ---------------------------------------------------------------------------

GENERATOR_PROMPT = """\
You are the GENERATOR agent in iteration {iter} of a harness loop. Your \
job is to satisfy the spec below, then spawn 4 reviewer subagents in \
parallel, then aggregate their score cards and exit.

## Spec

{spec}

## Previous feedback (iteration {prev_iter})

{previous_feedback}

## Hard rules (these are non-negotiable)

1. You are the GENERATOR, not a reviewer. Do NOT score your own code.
2. The 4 reviewers must run in PARALLEL — one assistant message with 4 \
Agent tool calls. Each reviewer gets a fresh context window and must \
NOT see the other reviewers' findings.
3. You only get the SCORE CARDS (JSON), not the reviewers' reasoning. \
That isolation is the point — do not try to bypass it by re-reading \
their transcripts.
4. Address every blocker from the previous iteration BEFORE doing \
anything else. Suggestions are optional.
5. After all 4 reviewers finish, write the aggregated score cards to:

       {score_card_path}

   with this exact shape:

       {{"iter": {iter}, "cards": [<card>, <card>, <card>, <card>]}}

   where each <card> is:

       {{"reviewer": "<name>", "score": <0.0-1.0>,
         "blockers": [<str>, ...], "suggestions": [<str>, ...],
         "evidence": "<short citation or path>"}}

6. Then EXIT. The orchestrator will read your score card and decide.

## Suggested flow

1. Read the spec carefully (it's a YAML file in this directory).
2. Write `demo/slugify.py` and `demo/test_slugify.py`.
3. Run `pytest demo/ -v` and confirm it passes. If it doesn't, fix and \
re-run until it does. (Don't skip this — the test reviewer WILL check.)
4. In one assistant message, spawn 4 reviewers via the Agent tool. \
Give each the spec + a path to the code, and ask them to return ONLY \
the score card JSON.
5. Write the aggregated JSON to the path above.
6. Exit.
"""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def read_spec() -> str:
    if not SPEC.exists():
        sys.exit(f"missing spec: {SPEC}")
    return SPEC.read_text()


def build_prompt(iter_n: int, spec_text: str, prev_feedback: str) -> str:
    score_card_path = SCORES / f"iter-{iter_n}.json"
    if iter_n == 1:
        prev_iter_str = "(none — first iteration)"
    else:
        prev_iter_str = f"{iter_n - 1}"
    return GENERATOR_PROMPT.format(
        iter=iter_n,
        spec=spec_text,
        previous_feedback=prev_feedback or "(none)",
        prev_iter=prev_iter_str,
        score_card_path=score_card_path,
    )


def spawn_generator(iter_n: int, spec_text: str, prev_feedback: str) -> None:
    """Spawn a fresh `claude` subprocess for this iteration."""
    prompt = build_prompt(iter_n, spec_text, prev_feedback)
    cmd = [
        CLAUDE_BIN,
        "--dangerously-skip-permissions",
        "-p", prompt,
    ]
    printable = " ".join(shlex.quote(c) if i < 3 else f"<{len(c)} chars>"
                         for i, c in enumerate(cmd))
    print(f"  $ {printable}")
    result = subprocess.run(cmd, cwd=WORK, check=False)
    if result.returncode != 0:
        print(f"  ! generator exited with code {result.returncode}")


def read_score_card(iter_n: int) -> dict:
    path = SCORES / f"iter-{iter_n}.json"
    if not path.exists():
        sys.exit(
            f"\ngenerator did not write {path}.\n"
            f"  -> the generator prompt instructs it to write this file.\n"
            f"  -> if the generator failed, re-run with --verbose to debug."
        )
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as e:
        sys.exit(f"score card at {path} is not valid JSON: {e}")


def gate(card: dict) -> tuple[bool, list[str]]:
    """Return (passed, reasons). A pass requires every reviewer's score
    to be at or above GATE_SCORE and every blocker's list to be empty."""
    reasons: list[str] = []
    cards = card.get("cards", [])
    if not cards:
        return False, ["no reviewer cards found"]
    for c in cards:
        score = c.get("score", 0.0)
        if score < GATE_SCORE:
            reasons.append(f"{c.get('reviewer', '?')}: score {score:.2f} < {GATE_SCORE}")
        for b in c.get("blockers", []):
            reasons.append(f"{c.get('reviewer', '?')} blocker: {b}")
    return (not reasons), reasons


def commit() -> bool:
    """Best-effort commit of the demo/ output. Returns True if a commit
    was created (or there was nothing to commit), False on git error."""
    if not (WORK / "demo").exists():
        return True
    add = subprocess.run(["git", "add", "-A"], cwd=WORK, check=False)
    if add.returncode != 0:
        print("  ! git add failed (not a git repo or no .git in scope)")
        return False
    status = subprocess.run(
        ["git", "status", "--porcelain"], cwd=WORK, capture_output=True, text=True
    )
    if not status.stdout.strip():
        print("  (nothing to commit)")
        return True
    msg = subprocess.run(
        ["git", "commit", "-m", "feat(harness-demo): generator passed the gate"],
        cwd=WORK, check=False,
    )
    if msg.returncode != 0:
        print("  ! git commit failed")
        return False
    print("  ✓ committed")
    return True


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Atelier harness demo — minimal closed-loop orchestrator."
    )
    parser.add_argument("--max-iter", type=int, default=MAX_ITER,
                        help=f"max iterations before escalating (default: {MAX_ITER})")
    parser.add_argument("--gate", type=float, default=GATE_SCORE,
                        help=f"per-reviewer score gate (default: {GATE_SCORE})")
    parser.add_argument("--clean", action="store_true",
                        help="wipe demo/ and score-cards/ before running")
    args = parser.parse_args()

    if shutil.which(CLAUDE_BIN) is None:
        sys.exit(
            f"\n'{CLAUDE_BIN}' not found on PATH.\n"
            f"  -> this demo must run INSIDE the atelier VM.\n"
            f"  -> run:  bin/devbox run python examples/harness-demo/orchestrate.py"
        )

    if args.clean:
        for p in (SCORES, WORK / "demo"):
            if p.exists():
                shutil.rmtree(p) if p.is_dir() else p.unlink()

    SCORES.mkdir(exist_ok=True)
    spec_text = read_spec()
    prev_feedback = ""

    for i in range(1, args.max_iter + 1):
        print(f"\n=== iteration {i}/{args.max_iter} ===")
        spawn_generator(i, spec_text, prev_feedback)

        card = read_score_card(i)
        passed, reasons = gate(card)

        scores = ", ".join(
            f"{c.get('reviewer', '?')}={c.get('score', 0):.2f}"
            for c in card.get("cards", [])
        )
        print(f"  scores: {scores}")
        print(f"  gate:   {'PASS' if passed else 'FAIL'} "
              f"({len(reasons)} blocker{'s' if len(reasons) != 1 else ''})")

        if passed:
            print(f"\n✓ GATE PASS at iteration {i}")
            commit()
            return 0

        for r in reasons[:5]:
            print(f"  - {r}")
        if len(reasons) > 5:
            print(f"  ... and {len(reasons) - 5} more")

        prev_feedback = json.dumps(card, indent=2)
        time.sleep(1)

    print(f"\n✗ hit MAX_ITER={args.max_iter}; escalating")
    print(f"  -> inspect: ls -la {SCORES}/")
    print(f"  -> the spec is probably wrong, or the gate is too strict")
    return 2


if __name__ == "__main__":
    sys.exit(main())