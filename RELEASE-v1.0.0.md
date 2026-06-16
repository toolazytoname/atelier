# atelier v1.0.0 — first public release

> First public release of atelier — a disposable Linux dev sandbox for
> Claude Code. Runs Claude Code inside an OrbStack Ubuntu 24.04 VM so
> the host Mac stays inert. `bin/devbox reset` rebuilds the VM from
> scratch in ~5 minutes.

## What's in v1.0.0

### The sandbox

- OrbStack Ubuntu 24.04 VM called `atelier` (default: 4 CPU / 8G RAM / 64G disk)
- `bin/devbox` driver with subcommands:
  `run`, `shell`, `claude`, `gui`, `push`, `pull`, `status`,
  `doctor`, `provision`, `reset`
- `setup/` scripts: `install-orbstack.sh`, `provision.sh`,
  `host-passthrough.sh`, `uninstall.sh`
- open-design MCP bridge (`.mcp.json`; daemon auto-started by
  `bin/devbox claude` / `bin/devbox gui`)
- `Makefile` with `help`, `setup`, `install-orbstack`, `provision`,
  `passthrough`, `doctor`, `shell`, `run`, `reset`, `uninstall`,
  `clean`, `lint`, `test` targets
- Project-level `settings.json` — tiny allow list (sandbox driver
  surface only) + last-resort deny list for `--dangerously-skip-permissions`

### Yolo-safety model

The architecture is the wall, the deny list is the backstop. Three
layers: VM isolation (Layer 1) + allow list (Layer 2) + deny list
(Layer 3). Documented in [`docs/security-model.md`](docs/security-model.md).

### Default workflow: the harness loop

Non-trivial features go through a 5-stage closed loop — generator →
N parallel reviewers → quality gate → commit (or iterate). Documented
in [`docs/workflow.md`](docs/workflow.md); runnable toy example in
[`examples/harness-demo/`](examples/harness-demo/).

### Documentation

- `README.md` + `README.zh-CN.md` (bilingual overview)
- `CLAUDE.md` + `CLAUDE.zh-CN.md` (bilingual instructions for CC)
- `CONTRIBUTING.md` (EN + 中文)
- `FAQ.md`, `AGENTS.md` (for non-CC agents)
- `docs/architecture.md` + `.zh-CN.md` — system architecture
- `docs/comparison.md` + `.zh-CN.md` — vs Docker Desktop / Lima / Vagrant / Multipass
- `docs/security-model.md` + `.zh-CN.md` — yolo-safety model
- `docs/workflow.md` + `.zh-CN.md` — harness loop design
- `docs/design.md` — design rationale and the four-pillar methodology

### CN-friendly by default

`provision.sh` defaults to mainland-China mirrors (TUNA apt, npmmirror
Node, goproxy.cn Go, rsproxy.cn crates, ghfast.top GitHub releases).
Set `CN_MIRROR=0` to switch to international sources.

### Open-source hygiene

- `LICENSE` — MIT
- `CHANGELOG.md` — Keep a Changelog format
- `SECURITY.md` — GitHub Security Advisories (private, not public issues)
- `.github/ISSUE_TEMPLATE/{bug_report,feature_request}.yml` — structured intake
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/workflows/ci.yml` — shellcheck + markdownlint + JSON/YAML validation
- `.github/workflows/test-mirrors.yml` — both CN and international mirror branches parse
- `.github/workflows/release.yml` — auto-create release on `v*` tag push

### Assets

- `assets/logo.svg` — monogram
- `assets/banner.svg` — README banner
- `assets/social-card.svg` — 1200×630 Open Graph card for social shares

## Install

```bash
brew install --cask orbstack
open /Applications/OrbStack.app

git clone https://github.com/toolazytoname/atelier.git
cd atelier
make setup          # ~5 min, idempotent
bin/devbox claude   # Claude Code, inside the VM
```

## Reporting issues

- **Bugs / features**: [open an issue](../../issues)
- **Security**: see [SECURITY.md](SECURITY.md) — GitHub Security Advisories, private

## License

[MIT](LICENSE)