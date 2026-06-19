{banner}

# Handoff — iteration {iter} of the atelier harness loop

This document is the **starting prompt** for the next iteration's
generator. The orchestrator rendered it by combining:

- The original feature spec (`{spec_path}`)
- The previous iteration's score card (`{score_card_path}`)
- Optional explicit feedback (`{feedback_path}` or `--feedback`)

The generator's job is to address every blocker in the previous
score card, re-run the project's test suite, then spawn N reviewer
subagents in parallel and write the aggregated card to
`{next_score_card_path}`.

---

## 1. Feature spec (the contract)

{spec}

---

## 2. Previous iteration's score card

> Read every blocker. Address them before doing anything else.
> Suggestions are optional. The reviewer's `evidence` field points
> at the file or log that justifies the score.

{score_card}

---

## 3. Additional feedback (if provided)

{extra_feedback}

---

## 4. Sandbox state (auto-captured)

- **VM name**: `{vm_name}`
- **Timestamp (UTC)**: {timestamp}
- **Project root**: `{project_root}`
- **Harness bin**: `{devbox_path}`

All heavy work goes through `bin/devbox run ...`. Tests live in
the VM, not on the host. The orchestrator's read-only context does
not include the reviewer's full transcript — only this card.

---

## 5. Hard rules (non-negotiable)

1. **You are the GENERATOR, not a reviewer.** Do NOT score your
   own code.
2. **The N reviewers must run in PARALLEL.** One assistant message
   with N `Agent` tool calls. Each reviewer gets a fresh context
   and must NOT see the other reviewers' findings.
3. **You only see this score card, not the reviewers' full
   transcripts.** That isolation is the point — do not try to
   bypass it.
4. **Address every blocker from the previous iteration BEFORE doing
   anything else.** Suggestions are optional but recommended.
5. **After all reviewers finish, write the aggregated card to:**

       {next_score_card_path}

   with this exact shape:

       {{"iter": {next_iter}, "cards": [<card>, <card>, ...]}}

   where each `<card>` is:

       {{"reviewer": "<name>",
         "score": <0.0-1.0>,
         "blockers": [<str>, ...],
         "suggestions": [<str>, ...],
         "evidence": "<short citation or path>"}}

6. **Then EXIT.** The orchestrator will read your score card and
   decide whether to commit or iterate.

---

{banner}