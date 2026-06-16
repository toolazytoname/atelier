# TASKS — atelier

> **Persistent task checklist.** Survives `/clear`. Lives in git.
>
> Conventions:
> - `- [ ]` — todo
> - `- [~]` — in progress
> - `- [x]` — done
> - `- [-]` — cancelled / no longer needed
>
> **Rule of thumb:** if a task will take more than one model turn,
> put it here. Single-turn stuff can live in the in-session
> TaskList alone (which dies on `/clear`).

## Current focus

Shipping atelier v1.0.0 — open-source release.

## Open

- [ ] **First GitHub release v1.0.0.** Tag, push, open release on
      GitHub with `CHANGELOG.md` content. Requires the user to
      push to GitHub (this is the publish step). Also enable
      Discussions on the repo.

## Done (recent)

- [x] **Create `assets/social-card.svg`.** 1200×630 Open Graph
      card for social shares. Same design language as
      `logo.svg` + `banner.svg` (dark navy gradient, amber
      spark, monospace URL footer).
- [x] **EN-ZH sync for new docs.** All 4 new docs translated
      to Chinese (`*.zh-CN.md`): architecture / comparison /
      security-model / workflow. README file layout updated to
      point at the `.zh-CN.md` variants.

## Done (recent)

- [x] **README: "Harness by default" section** — Highlights bullet
      added, Pillar 1 in the four-pillar table sharpened to
      explain what the harness loop actually does.
- [x] **`examples/harness-demo/`** — runnable demo of the harness
      loop: `feature-spec.yaml`, `orchestrate.py`, `README.md`,
      `.gitignore`. Referenced from `docs/workflow.md` and the
      README file layout.
- [x] **P0 + P1 open-source prep (prior session).** Cleanup
      (`package.json`, `node_modules/`, stale PNGs deleted),
      compliance files (`CHANGELOG.md`, `SECURITY.md`,
      `.editorconfig`, issue / PR templates), CI workflows
      (shellcheck + markdownlint + mirror smoke test), user-facing
      docs (`FAQ.md`, `docs/architecture.md`, `docs/comparison.md`,
      `docs/security-model.md`, `docs/workflow.md`, `AGENTS.md`),
      bilingual CLAUDE.md, user-level `~/.claude/skills/harness/`
      skill.

## Cancelled

- [-] **`bin/devbox handoff` subcommand + `~/.claude/rules/common/handoff.md`.**
      Built, tested, then deleted. Reason: TaskList (CC's
      in-memory task tracker) + CLAUDE.md + git state cover 95% of
      the recovery case; a dedicated HANDOFF.md was a parachute
      for a rare scenario. This `TASKS.md` is the lightweight
      alternative that survives `/clear`.

## Key decisions (non-obvious)

- **The harness loop is the default** for any non-trivial feature
  work. Documented in `CLAUDE.md` + `~/.claude/skills/harness/`.
  Pillar 1 in the README four-pillar table now points to it
  concretely.
- **Three layers, not one** — yolo-safety model = VM isolation
  (Layer 1) + allow list (Layer 2) + deny list (Layer 3 backstop).
  Documented in `docs/security-model.md`.
- **`package.json` is gone** — atelier is bash + scripts, not an
  npm package. CI uses Node only for markdownlint, not as a repo
  dependency.
- **No automatic HANDOFF.md generation** — recovery across
  `/clear` is the model's job (via `TASKS.md` + `CLAUDE.md` +
  git), not a script's. See `[-] bin/devbox handoff` above.