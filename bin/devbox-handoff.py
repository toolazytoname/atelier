#!/usr/bin/env python3
"""atelier harness handoff — render the next generator's prompt.

Reads the feature spec + the previous iteration's score card (and
optionally an explicit feedback blob) and renders a self-contained
prompt document following `handoff-template.md`. The orchestrator
then passes this document to the next `bin/devbox run claude -p`
invocation.

Usage::

    # render to stdout
    devbox-handoff.py \\
        --spec feature-spec.md \\
        --score-card score-cards/iter-1.json \\
        --iter 2

    # render to a file
    devbox-handoff.py \\
        --spec feature-spec.md \\
        --score-card score-cards/iter-1.json \\
        --iter 2 \\
        --out prompts/iter-2.md

    # optional: include extra free-form feedback
    devbox-handoff.py \\
        --spec feature-spec.md \\
        --score-card score-cards/iter-1.json \\
        --iter 2 \\
        --feedback "Re-read the boundary tests; the user wants more cases"

Exit codes:

- 0  — rendered successfully
- 1  — bad arguments
- 2  — input file missing or unreadable
- 3  — score card is not valid JSON
- 4  — template missing

Stdlib only; no third-party deps.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "handoff-template.md"
DEVBOX = HERE / "devbox"

BANNER = "<!-- rendered by bin/devbox-handoff.py — DO NOT EDIT BY HAND -->"


def _read_text(path: Path, *, what: str) -> str:
    if not path.exists():
        sys.stderr.write(f"{what} not found: {path}\n")
        sys.exit(2)
    try:
        return path.read_text(encoding="utf-8")
    except OSError as e:
        sys.stderr.write(f"{what} unreadable: {path}: {e}\n")
        sys.exit(2)


def _parse_score_card(path: Path) -> dict:
    raw = _read_text(path, what="score card")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"score card at {path} is not valid JSON: {e}\n")
        sys.exit(3)


def _format_score_card(card: dict) -> str:
    """Pretty-print a score card as markdown for inclusion in the prompt."""
    cards = card.get("cards", [])
    if not cards:
        return "(empty score card — no reviewer results)\n"
    blocks: list[str] = []
    for c in cards:
        reviewer = c.get("reviewer", "?")
        score = c.get("score", 0.0)
        blockers = c.get("blockers", []) or []
        suggestions = c.get("suggestions", []) or []
        evidence = c.get("evidence", "")
        blocks.append(f"### Reviewer: `{reviewer}` — score **{score:.2f}**")
        if evidence:
            blocks.append(f"_evidence_: `{evidence}`")
        if blockers:
            blocks.append("\n**Blockers (must fix):**\n")
            for b in blockers:
                blocks.append(f"- {b}")
        else:
            blocks.append("\n_Blockers: none_\n")
        if suggestions:
            blocks.append("\n**Suggestions (optional):**\n")
            for s in suggestions:
                blocks.append(f"- {s}")
        blocks.append("")
    return "\n".join(blocks).rstrip() + "\n"


def _resolve_paths(args: argparse.Namespace) -> dict[str, str]:
    """Pre-fill the placeholder values that go into the template."""
    iter_n = args.iter
    next_iter = iter_n + 1
    spec_path = args.spec.resolve()
    score_card_path = args.score_card.resolve()
    project_root = Path.cwd().resolve()
    next_score_card = (
        args.next_score_card.resolve()
        if args.next_score_card
        else (project_root / "score-cards" / f"iter-{next_iter}.json")
    )
    return {
        "spec_path": str(spec_path),
        "score_card_path": str(score_card_path),
        "feedback_path": (
            str(args.feedback.resolve()) if args.feedback else "(none)"
        ),
        "next_score_card_path": str(next_score_card),
        "iter": str(iter_n),
        "next_iter": str(next_iter),
        "vm_name": os.environ.get("DEVBOX_VM", "atelier"),
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "project_root": str(project_root),
        "devbox_path": str(DEVBOX),
    }


def render(args: argparse.Namespace) -> str:
    if not TEMPLATE.exists():
        sys.stderr.write(f"template missing: {TEMPLATE}\n")
        sys.exit(4)

    spec_text = _read_text(args.spec, what="spec")
    card = _parse_score_card(args.score_card)
    score_card_md = _format_score_card(card)

    extra_feedback = "(none)"
    if args.feedback is not None:
        extra_feedback = _read_text(args.feedback, what="feedback")
    if args.feedback_text:
        extra_feedback = (
            (extra_feedback + "\n\n" + args.feedback_text)
            if extra_feedback != "(none)"
            else args.feedback_text
        )

    paths = _resolve_paths(args)

    template = TEMPLATE.read_text(encoding="utf-8")
    rendered = template.format(
        banner=BANNER,
        spec=spec_text.rstrip(),
        score_card=score_card_md,
        extra_feedback=extra_feedback,
        **paths,
    )
    return rendered


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="devbox-handoff.py",
        description=(
            "Render the next-iteration generator prompt from a spec "
            "and a previous score card."
        ),
    )
    p.add_argument(
        "--spec", type=Path, required=True,
        help="Path to the feature spec (YAML or Markdown).",
    )
    p.add_argument(
        "--score-card", type=Path, required=True,
        help="Path to the previous iteration's score card (JSON).",
    )
    p.add_argument(
        "--iter", type=int, required=True,
        help="The iteration number whose feedback is being rendered.",
    )
    p.add_argument(
        "--next-score-card", type=Path, default=None,
        help=(
            "Where the generator should write the next score card "
            "(default: <project_root>/score-cards/iter-<N+1>.json)."
        ),
    )
    p.add_argument(
        "--feedback", type=Path, default=None,
        help="Optional path to a free-form feedback blob.",
    )
    p.add_argument(
        "--feedback-text", type=str, default="",
        help="Optional free-form feedback text (concatenated with --feedback).",
    )
    p.add_argument(
        "--out", type=Path, default=None,
        help="Write rendered prompt to this file instead of stdout.",
    )
    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.iter < 1:
        parser.error("--iter must be >= 1")
    text = render(args)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())