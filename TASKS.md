# TASKS — atelier

> **Persistent task checklist.** Survives `/clear`. Lives in git.
>
> Conventions:
>
> - `- [ ]` — todo
> - `- [~]` — in progress
> - `- [x]` — done
> - `- [-]` — cancelled / no longer needed
>
> **Rule of thumb:** if a task will take more than one model turn,
> put it here. Single-turn stuff can live in the in-session
> TaskList alone (which dies on `/clear`).

## Current focus

atelier v1.0.0 is released. Maintenance + docs cleanup.

## Open

(none)

## Key decisions (non-obvious)

These are the load-bearing choices that aren't obvious from the code:

- **The harness loop is the default** for any non-trivial feature work.
  Canonical design in [`docs/workflow.md`](docs/workflow.md); CC triggers
  in `CLAUDE.md`; portable rules in `AGENTS.md`.
- **Three-layer yolo-safety model** — VM isolation (Layer 1) + allow
  list (Layer 2) + deny-list backstop (Layer 3). Canonical:
  [`docs/security-model.md`](docs/security-model.md).
- **One canonical home per concept.** Each idea (host/VM split, harness
  loop, yolo model, troubleshooting) is written out in full in exactly
  one doc; everything else links to it. Don't re-explain — link.
- **zh-CN only for entry docs** — `README.zh-CN.md` + `CLAUDE.zh-CN.md`
  are the only translations kept in sync. Deep docs (`docs/*`) are
  English-only by policy, to halve the edit surface.
- **`package.json` is gone** — atelier is bash + scripts, not an npm
  package. CI uses Node only for markdownlint.
- **No automatic HANDOFF.md** — recovery across `/clear` is the model's
  job (`TASKS.md` + `CLAUDE.md` + git), not a script's.
