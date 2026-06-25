# Changelog

All notable changes to `atelier` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- open-design integration: the `bin/devbox gui` command, the
  `localhost:7456` browser tunnel, the open-design daemon / `od` binary /
  Electron dependencies in `setup/provision.sh`, and the open-design
  server block in `.mcp.json`. atelier is now positioned purely as an
  isolated dev sandbox.

### Changed

- `.mcp.json` now ships a single `atelier` MCP server — a Python-stdlib
  bridge wrapping `bin/devbox --json` so agents can drive the sandbox
  (`run` / `status` / `doctor` / `run_claude` / `version`).

## [1.0.0] — 2026-06-16

First public release.

### The sandbox (core)

- OrbStack Ubuntu 24.04 VM called `atelier` (default: 4 CPU / 8G RAM / 64G disk)
- `bin/devbox` driver with subcommands:
  `run`, `shell`, `claude`, `gui`, `push`, `pull`, `status`,
  `doctor`, `provision`, `reset`
- `setup/` scripts: `install-orbstack.sh`, `provision.sh`,
  `host-passthrough.sh`, `uninstall.sh`
- open-design MCP bridge (`.mcp.json`; daemon auto-started by
  `bin/devbox claude` / `bin/devbox gui`)
- `Makefile` with `help`, `setup`, `install-orbstack`, `provision`,
  `passthrough`, `doctor`, `shell`, `run`, `reset`, `uninstall`, `clean`,
  `lint`, `test` targets
- Project-level `settings.json` — tiny allow list (sandbox driver surface
  only) + last-resort deny list for `--dangerously-skip-permissions`

### Yolo-safety model

Three independent layers documented in `docs/security-model.md`:

- **Layer 1**: OrbStack VM isolation (real Linux kernel, no host
  filesystem / network / hardware access)
- **Layer 2**: project-level allow list (only `bin/devbox*`, `setup/*`,
  `make*`, `git*`, `orb*`, `orbctl*`, observation tools)
- **Layer 3**: last-resort deny list (`rm -rf /`, `sudo`, `curl|bash`,
  credential stores — only the unrecoverable-mistake class)

### Default workflow: the harness loop

Non-trivial features go through a 5-stage closed loop — generator →
N parallel reviewers → quality gate → commit (or iterate). Documented
in `docs/workflow.md`; runnable toy example in
`examples/harness-demo/`.

The loop is invoked naturally via the user-level
`~/.claude/skills/harness/` skill (triggers on "用 harness",
"多 agent 评审", "yolo 跑这个", etc.).

### Documentation

- `README.md` + `README.zh-CN.md` (bilingual overview)
- `CLAUDE.md` + `CLAUDE.zh-CN.md` (bilingual instructions for CC)
- `CONTRIBUTING.md` (EN + 中文)
- `FAQ.md`
- `AGENTS.md` (portable entry point for non-CC agents)
- `docs/design.md` — design rationale and the four-pillar methodology
- `docs/architecture.md` + `.zh-CN.md` — system architecture
- `docs/comparison.md` + `.zh-CN.md` — vs Docker Desktop / Lima / Vagrant / Multipass
- `docs/security-model.md` + `.zh-CN.md` — yolo-safety model in detail
- `docs/workflow.md` + `.zh-CN.md` — harness loop design
- `TASKS.md` — persistent task checklist (survives `/clear`)

### Open-source hygiene

- `LICENSE` — MIT
- `SECURITY.md` — GitHub Security Advisories (private, not public issues)
- `CHANGELOG.md` — this file (Keep a Changelog)
- `.editorconfig`
- `.markdownlint.jsonc`
- `.github/ISSUE_TEMPLATE/bug_report.yml` — structured intake (requires doctor output)
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/workflows/ci.yml` — shellcheck + markdownlint + JSON/YAML
  validation + smoke
- `.github/workflows/test-mirrors.yml` — both `CN_MIRROR=0` and
  `CN_MIRROR=1` parse + reach real hosts
- `.github/workflows/release.yml` — auto-create GitHub Release on
  `v[0-9]+.[0-9]+.[0-9]+` tag push (or via `workflow_dispatch`)

### Assets

- `assets/logo.svg` — monogram
- `assets/banner.svg` — README banner
- `assets/social-card.svg` — 1200×630 Open Graph card for social shares

### Runnable example

- `examples/harness-demo/` — minimal end-to-end harness loop:
  `feature-spec.yaml` (sample spec) + `orchestrate.py` (~280-line
  Python orchestrator) + `README.md` + `.gitignore`

### Behavior changes

- README: `bin/devbox claude` (CC inside the VM) is now the
  recommended default; running CC on the host is documented as a
  downgrade of the "host stays inert" promise.
- README: four-pillar table now distinguishes *bundled* (pillar 4,
  the sandbox) from *recommended* (pillars 1–3, which depend on
  external companion tools).

### Removed

- Root-level screenshot artifacts (`*.png`, `screenshot.mjs`) — were
  test artifacts from a previous games project, not atelier
- `package.json` / `node_modules/` — atelier is a bash + scripts
  project, not an npm package (use your distro's package manager
  for dev tooling)
- `public/` — empty, unused

[Unreleased]: https://github.com/toolazytoname/atelier/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/toolazytoname/atelier/releases/tag/v1.0.0
