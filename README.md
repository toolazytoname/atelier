<p align="center">
  <a href="README.md">
    <img src="assets/banner.svg" alt="atelier — a disposable Linux dev sandbox for Claude Code" width="820">
  </a>
</p>

<p align="center">
  <strong>Run Claude Code in a disposable Linux VM. Your host stays clean.</strong>
</p>

<p align="center">
  <a href="README.md"><b>English</b></a>
  ·
  <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://orbstack.dev"><img src="https://img.shields.io/badge/VM-OrbStack-blueviolet" alt="VM: OrbStack"></a>
  <a href="https://github.com/toolazytoname/atelier/actions/workflows/ci.yml"><img src="https://github.com/toolazytoname/atelier/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/toolazytoname/atelier/releases"><img src="https://img.shields.io/github/v/release/toolazytoname/atelier" alt="Release"></a>
  <a href="https://github.com/toolazytoname/atelier/discussions"><img src="https://img.shields.io/github/discussions/toolazytoname/atelier" alt="Discussions"></a>
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Ubuntu%2024.04-lightgrey" alt="Platform">
  <img src="https://img.shields.io/badge/powered_by-Claude%20Code-D97757" alt="Powered by Claude Code">
</p>

---

*atelier* (French: **workshop**) is a self-contained, **disposable Linux
dev sandbox** for building whatever you want. The whole workflow — code,
builds, tests, dependencies — lives inside an OrbStack Linux VM. The
host Mac is reduced to its true minimum: a terminal, a browser tab, and
OrbStack itself. No Node, no Python, no Go, no Rust, no MCP servers — all
of it lives in the VM, dies with the VM, and can be rebuilt from scratch
in ~5 minutes.

## Quick start

```bash
# 1. install OrbStack (one time)
brew install --cask orbstack
open /Applications/OrbStack.app        # complete first-run setup

# 2. bring up the VM and provision it (~5 min, idempotent)
make setup                            # = install-orbstack + provision + passthrough + doctor
# or step by step:
./setup/provision.sh
./setup/host-passthrough.sh           # forward host env (ANTHROPIC_*, ...)

# 3. daily use — Claude Code lives IN the VM
bin/devbox claude                     # ← recommended: Claude Code inside the VM
bin/devbox gui                        # open-design web UI on host browser
bin/devbox run pnpm test              # any command inside the VM
bin/devbox shell                      # interactive VM shell
bin/devbox doctor                     # health check
bin/devbox reset                      # nuke and recreate
```

**Why `bin/devbox claude` and not the host's `claude`?** Because the
whole point of atelier is that the host Mac stays inert. CC running
on the host will write `~/.claude/{cache,file-history,session-data}`
on the host and run any MCP servers on the host. `bin/devbox claude`
moves the whole process into the VM. The trade-off is ~30–80 ms of
TUI latency over `orbctl` — invisible for coding, mildly annoying
for interactive browser feedback. See
["Should I run Claude Code on the host?"](#should-i-run-claude-code-on-the-host)
below.

### Mirrors

`provision.sh` defaults to **mainland-China mirrors** because the
international Cloudflare-fronted CDNs (`deb.nodesource.com`,
`download.docker.com`, etc.) rate-limit aggressively when traffic comes
from CN egress. The script uses TUNA (apt), npmmirror (Node/npm/binary
mirror), goproxy.cn (Go module proxy), rsproxy.cn (crates.io), and
ghfast.top (GitHub releases). Set `CN_MIRROR=0 ./setup/provision.sh` to
use international sources instead.

## Highlights

- **Yolo with a bounded blast radius.** Run Claude Code with
  `--dangerously-skip-permissions`; the architecture is the wall, the
  allow/deny list is just the backstop.
- **Host stays inert.** No dev tools installed, no shell rc modified,
  no config files touched. `bin/devbox reset` rebuilds the VM in
  ~5 min.
- **CN-friendly out of the box.** `provision.sh` defaults to
  mainland-China mirrors so installs don't crawl on CN egress. Set
  `CN_MIRROR=0` to switch to international sources.
- **One wrapper, every command.** `bin/devbox run` / `shell` / `claude` /
  `gui` / `doctor` / `reset` — your whole toolchain lives behind one
  driver.
- **Harness loop by default.** Non-trivial features go through a
  5-stage closed loop — generator → N parallel reviewers → quality
  gate → commit (or iterate). The sandbox makes it safe to run
  unattended; humans only arbitrate when the loop is stuck. See
  [docs/workflow.md](docs/workflow.md) for the full design and
  [examples/harness-demo/](examples/harness-demo/) for a runnable
  demo.

## The all-in-VM architecture

```
Host (Mac) — thin client
├── Terminal (you type here)
├── Browser tab pointing at http://localhost:7456 (the open-design UI)
└── OrbStack (the hypervisor)
                │
                │ orb run atelier -- <cmd>      ← stdio forwarded
                │ ssh atelier@orb -L 7456:...  ← browser tab tunnel
                ↓
VM (atelier) — everything else
├── Claude Code (run via `bin/devbox claude`)
├── open-design daemon (HTTP at 127.0.0.1:7456, MCP at `od mcp`)
├── open-design MCP (stdio; talks to local daemon; CC discovers via .mcp.json)
├── open-design web UI (served by daemon, viewed in host browser via SSH tunnel)
├── Node 24 / pnpm / Python 3.12 / Go / Rust / uv / gh / starship
└── network MCPs (lazyweb, context7, exa, playwright, github, sequential-thinking)
```

The whole thing shares the host's `/Users/lazy/Code/crack/atelier/`
through OrbStack's mount at `/mnt/mac/...` — your files live where
you'd expect (on the host), and the VM just borrows them for execution.

## What lives where

| Concern                       | Host | VM | Why                                                                              |
|-------------------------------|------|----|----------------------------------------------------------------------------------|
| Terminal, browser, display    |  ✓   |    | the OS already does this for you                                                |
| OrbStack hypervisor           |  ✓   |    | runs the Linux VM on Apple Silicon                                               |
| Claude Code¹                  |      |  ✓ | **recommended**: `bin/devbox claude`. CC-on-host works but breaks the "host stays inert" promise |
| open-design daemon¹           |      |  ✓ | Node service; binds 127.0.0.1 only; accessed via SSH tunnel                      |
| open-design MCP¹              |      |  ✓ | stdio bridge from CC to the daemon                                              |
| open-design web UI¹           |      |  ✓ | served at 127.0.0.1:7456 inside VM; user sees it at localhost:7456 on host      |
| Node 24 / pnpm / Python / Go / Rust / uv / gh / starship |  | ✓ | isolated per-project; `bin/devbox reset` removes them in one shot    |
| project files                 |  ✓   |    | `/Users/lazy/Code/crack/atelier/` on host, mounted as `/mnt/mac/...` in VM       |

¹ *open-design is a separate project. Atelier ships a bridge config
(`.mcp.json`) and will start the daemon for you, but open-design
itself is optional. Without it, atelier still works — you just lose
the design-aware features. See
[FAQ § "What's the relationship between atelier and open-design?"](FAQ.md).*

## The four-pillar methodology

This project delivers the user's four stated requirements. Each pillar
maps to a concrete tool / skill / pattern; the VM is the foundation
that makes the loop fast and safe.

> The skills and MCPs named in pillars 1–3 are **recommended companions**,
> not parts of the atelier repo. Atelier works without them; you
> just lose the corresponding feature. The one thing atelier *does*
> ship is pillar 4 (the sandbox itself).

| # | Requirement                                  | How it is delivered (bundled vs recommended)                                                                                                                                                                                  |
|---|----------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1 | Less human involvement                       | **Recommended.** The default workflow for any non-trivial feature is a closed-loop harness: a generator writes code in isolation, N independent reviewers (correctness / security / a11y / visual / boundary) grade it in parallel, and a quality gate decides pass or iterate. The human only arbitrates when the loop gets stuck. Powered by the `everything-claude-code` plugin family — `autonomous-agent-harness`, `continuous-agent-loop`, `council`, `quality-gate`. Atelier ships no orchestration itself; it provides the sandbox that makes running this loop unattended safe. |
| 2 | Design aesthetic aligned with Open Design    | **Recommended:** the `mcp__open-design__*` tools (served by the local daemon), the `mcp__plugin_lazyweb_lazyweb__lazyweb_search` reference library, and the `everything-claude-code:frontend-design` / `ui-ux-pro-max` / `design-system` skills. None of these are required. |
| 3 | Catch what self-test misses                  | **Recommended:** the `verify` skill, `everything-claude-code:e2e-runner`, the multi-agent `council`, and `mcp__plugin_everything-claude-code_playwright__browser_take_screenshot`. All opt-in.                                            |
| 4 | Isolated VM, no impact on the host           | **Bundled.** OrbStack Ubuntu 24.04 VM (`atelier`) · every dev tool lives inside · `bin/devbox reset` rebuilds the VM from scratch in ~5 min · the host stays inert: no packages, no shell rc edits, no config files touched. **Run `bin/devbox claude` to keep this promise — see below.** |

## File layout

```
.
├── CLAUDE.md                  # instructions for Claude Code in this project
├── CLAUDE.zh-CN.md            # 同上，中文版
├── README.md                  # this file (English)
├── README.zh-CN.md            # 中文版
├── FAQ.md                     # frequently asked questions
├── CONTRIBUTING.md            # how to file issues / send PRs (EN + 中文)
├── CHANGELOG.md               # release notes (Keep a Changelog)
├── SECURITY.md                # vulnerability disclosure policy
├── LICENSE                    # MIT
├── Makefile                   # make setup / doctor / reset / passthrough / shell
├── .editorconfig              # indentation / EOL / final newline
├── .markdownlint.jsonc        # markdown lint rules
├── .gitignore
├── assets/
│   ├── logo.svg               # monogram used in social cards
│   ├── banner.svg             # banner used in this README
│   └── social-card.svg        # Open Graph / social share card
├── .claude/
│   └── settings.json          # project-level sandbox config (allow list, yolo backstop deny)
├── .mcp.json                  # open-design MCP bridge config (consumed by CC inside the VM)
├── .github/
│   ├── workflows/
│   │   ├── ci.yml             # shellcheck + markdownlint + JSON/YAML validation + smoke
│   │   └── test-mirrors.yml   # both CN_MIRROR branches must parse + reach real hosts
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   └── feature_request.yml
│   └── PULL_REQUEST_TEMPLATE.md
├── docs/
│   ├── design.md              # why this project exists
│   ├── architecture.md        # component diagram + data flow + env passthrough
│   ├── comparison.md          # vs Docker Desktop / Lima / Vagrant / Multipass
│   ├── security-model.md      # yolo-safety model: walls, threats, limitations
│   ├── workflow.md            # the harness loop: 5 stages + isolation rules
│   └── *.zh-CN.md             # 中文版（architecture / comparison / security-model / workflow）
├── examples/                  # minimal end-to-end demos
│   └── harness-demo/          # runnable harness loop: spec + orchestrate.py + reviewers
├── bin/
│   └── devbox                 # host wrapper: run / shell / claude / gui / reset / doctor
└── setup/
    ├── install-orbstack.sh    # brew or direct .dmg install of OrbStack
    ├── provision.sh           # one-shot VM bootstrap (apt, node 24, python, go, rust, open-design)
    ├── host-passthrough.sh    # forward host env (ANTHROPIC_*, GITHUB_TOKEN) into the VM
    └── uninstall.sh           # tear it all down (--all removes OrbStack itself)
```

## Daily workflow

```bash
# start of session
bin/devbox claude              # Claude Code, inside the VM, yolo
# in another terminal tab:
bin/devbox gui                 # open-design web UI tunneled to host browser
# in the host browser:
open http://localhost:7456
```

When you're done, Ctrl-C both terminals. Nothing leaks back to the host.

## Should I run Claude Code on the host?

**Default: no. Use `bin/devbox claude`.**

Atelier's whole promise is that the host Mac stays inert. That
promise only holds when Claude Code itself runs in the VM. If you
launch CC on the host instead, the following happens on the host:

- CC writes to `~/.claude/{cache,file-history,session-data,
  paste-cache, telemetry, ...}`
- Any MCP server CC loads (open-design, lazyweb, context7, ...)
  runs as a host process
- Any CC-installed skill or plugin writes to `~/.claude/...`
- The `.claude/settings.json` deny list *still* works (it's read
  by the host's CC), but its scope is reduced — it can no longer
  protect you from a misbehaving MCP server

**When is host CC OK?**
- You're not running with `--dangerously-skip-permissions`
- You're doing read-only work (no writes, no MCP, no shell)
- You're asking a quick question, not driving a multi-step task
- You understand you've opted out of the "host stays inert" promise

**When is host CC a bad idea?**
- yolo mode: always `bin/devbox claude`
- Multi-step coding with tool use: `bin/devbox claude`
- Anything that touches the network: `bin/devbox claude` (the MCP
  servers that handle network calls only exist in the VM)
- Anything that needs `pnpm test` etc. (host has no pnpm anyway)

If you really must run on the host, the project's
`.claude/settings.json` still applies — atelier is not bypassed,
just *weakened* (the wall is still there, but a misbehaving
plugin / MCP can leave a footprint on the host).

## The yolo-safety model

The point of this project is **yolo with a bounded blast radius.** The
architecture itself is the wall — the deny list is just the last-resort
backstop for `--dangerously-skip-permissions`.

**Architecture (the real wall).** The host is supposed to be inert. Every
mutating op that needs CPU/memory/disk routes through `bin/devbox run`
into the VM. The host runs nothing except Claude Code's display terminal
and the open-design web UI in your browser. The `.claude/settings.json`
in this project has a tiny allow list (sandbox driver + observation
tools) — anything else, the user has to grant explicitly.

**Last-resort deny list (yolo backstop).** When you run CC with
`--dangerously-skip-permissions`, only the deny list still bites. It
contains only the things whose consequences don't recover even if
caught in seconds: `rm -rf /`, `sudo`, `curl|bash`, credential stores
(`~/.ssh/**`, `~/.aws/**`, etc.). Shell rc files and host config dirs
are deliberately **not** in the deny list — the architecture says CC
writes only to the project tree. If the architecture breaks, the user
adds a path to the allow list; the deny list is for the "unrecoverable
mistake" class, not for "things we don't want right now."

See `CLAUDE.md` for the full model.

## Why OrbStack and not "just Docker"?

OrbStack gives a *real* Linux VM (full init, kernel isolation, disk
image) plus a Docker daemon that runs natively on macOS via Apple's
Virtualization framework. Compared to Docker Desktop, it is faster on
Apple Silicon, lighter on resources, and lets you keep state in
disposable VMs (`bin/devbox reset` rebuilds in seconds). The trade-off
is that a Linux VM is heavier than a plain container — but for a real
dev environment with shared folders, dev servers, easy reset, and SSH
access, that trade is worth it.

## Troubleshooting

| Symptom                                            | Fix                                                                                              |
|----------------------------------------------------|--------------------------------------------------------------------------------------------------|
| `orb: command not found`                           | `export PATH="/opt/homebrew/bin:$PATH"` or `ln -sf $(pwd)/bin/devbox /usr/local/bin/devbox`      |
| `atelier` not running                              | `bin/devbox provision` (creates + starts + installs)                                             |
| `claude` in VM not authenticated                   | `./setup/host-passthrough.sh` then start a new `bin/devbox claude`                                |
| `od` daemon not running                            | `bin/devbox gui` (auto-starts the daemon) or `bin/devbox claude`                                |
| Browser shows connection refused on localhost:7456 | `bin/devbox gui` is not running. Run it.                                                          |
| Want a clean slate                                 | `bin/devbox reset` (DESTRUCTIVE — wipes the VM and recreates from zero)                          |
| Port 8000 already taken on the host                | VM has its own network namespace; use any port inside the VM                                     |
| Suspicious of a state in the VM                    | `bin/devbox run bash -c "rm -rf ~/*"` — it's a VM, the blast radius is bounded                   |

## Resetting the sandbox

```bash
bin/devbox reset
```

Prompts for confirmation, deletes the existing `atelier` VM, and
recreates it from scratch with the same provision script. Re-run time:
~5–10 minutes (mostly downloading Ubuntu packages and language
runtimes). The host filesystem is untouched.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to file issues and send
PRs. The design rationale behind the four pillars lives in
[`docs/design.md`](docs/design.md); deeper system details are in
[`docs/architecture.md`](docs/architecture.md), the yolo-safety model
in [`docs/security-model.md`](docs/security-model.md), and the
Docker Desktop / Lima / Vagrant / Multipass comparison in
[`docs/comparison.md`](docs/comparison.md). For common questions, see
[FAQ.md](FAQ.md). Security issues: see
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
