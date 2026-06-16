# Changelog

All notable changes to `atelier` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `docs/architecture.md` — deeper system architecture
- `docs/comparison.md` — vs Docker Desktop / Lima / Vagrant / Multipass
- `docs/security-model.md` — yolo-safety model in detail
- `docs/screenshots/` — gallery of verified sandbox screenshots
- `examples/` — minimal end-to-end demos
- `assets/social-card.svg` — Open Graph / social share image
- `.editorconfig`
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/workflows/ci.yml` — shellcheck + markdownlint
- `SECURITY.md` — vulnerability disclosure policy

### Changed
- README: "全在 VM" (`bin/devbox claude`) is now the recommended default;
  running Claude Code on the host is documented as a downgrade
- README: four-pillar table now distinguishes *bundled* from *recommended*
- `docs/design.md` — refreshed to match current architecture

### Removed
- Root-level screenshot artifacts (`*.png`, `screenshot.mjs`)
- `package.json` / `node_modules/` — atelier is a bash + scripts project,
  not an npm package (use your distro's package manager for dev tooling)
- `public/` — empty, unused

## [1.0.0] — 2026-06-16

### Added
- First public release
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
- Bilingual documentation: `README.md` + `README.zh-CN.md`,
  `CLAUDE.md` + `CLAUDE.zh-CN.md`, `CONTRIBUTING.md` (EN + 中文)
- `LICENSE` — MIT
- `assets/logo.svg`, `assets/banner.svg`
- CN-friendly mirrors by default (`TUNA` apt, `npmmirror` Node,
  `goproxy.cn` Go, `rsproxy.cn` crates, `ghfast.top` GitHub releases);
  set `CN_MIRROR=0` to use international sources
- `docs/design.md` — design rationale and the four-pillar methodology

[Unreleased]: https://github.com/toolazytoname/atelier/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/toolazytoname/atelier/releases/tag/v1.0.0
