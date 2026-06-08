# atelier

An isolated, disposable Linux dev sandbox that runs **Claude Code, the
open-design daemon, and every dev tool** inside an OrbStack VM. The host
Mac is reduced to its true minimum: a terminal, a browser tab, and
OrbStack itself. No Node, no Python, no Go, no Rust, no MCP servers, no
open-design app — all of it lives in the VM, dies with the VM, and can be
rebuilt from scratch in ~5 minutes.

## TL;DR

```bash
# 1. install OrbStack (one time)
brew install --cask orbstack
open /Applications/OrbStack.app        # complete first-run setup

# 2. bring up the VM and provision it (~5 min, idempotent)
./setup/provision.sh
./setup/host-passthrough.sh           # forward host env (ANTHROPIC_*, ...)

# 3. daily use — everything is in the VM
bin/devbox claude                     # Claude Code, inside the VM
bin/devbox gui                        # open-design web UI on host browser
bin/devbox run pnpm test              # run any command inside the VM
bin/devbox shell                      # open a VM shell
bin/devbox doctor                     # health check
bin/devbox reset                      # nuke and recreate
```

The host stays inert: no dev tools installed, no shell rc modified, no
config files touched.

### Mirrors

`provision.sh` defaults to **mainland-China mirrors** because the
international Cloudflare-fronted CDNs (deb.nodesource.com,
download.docker.com, etc.) rate-limit aggressively when traffic comes
from CN egress. The script uses TUNA (apt), npmmirror (Node/npm/binary
mirror), goproxy.cn (Go module proxy), rsproxy.cn (crates.io), and
ghfast.top (GitHub releases). Set `CN_MIRROR=0 ./setup/provision.sh` to use
international sources instead.

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
|------------------------------|------|----|----------------------------------------------------------------------------------|
| Terminal, browser, display  |  ✓   |    | the OS already does this for you                                                |
| OrbStack hypervisor           |  ✓   |    | runs the Linux VM on Apple Silicon                                               |
| Claude Code                  |      |  ✓ | talks to local open-design MCP; no host config needed                           |
| open-design daemon           |      |  ✓ | Node service; binds 127.0.0.1 only; accessed via SSH tunnel                      |
| open-design MCP              |      |  ✓ | stdio bridge from CC to the daemon                                              |
| open-design web UI           |      |  ✓ | served at 127.0.0.1:7456 inside VM; user sees it at localhost:7456 on host        |
| Node 24 / pnpm / Python / Go / Rust / uv / gh / starship |  | ✓ | isolated per-project; `bin/devbox reset` removes them in one shot    |
| project files                |  ✓   |    | `/Users/lazy/Code/crack/atelier/` on host, mounted as `/mnt/mac/...` in VM       |

## The four-pillar methodology

This project delivers the user's four stated requirements. Each pillar
maps to a concrete tool / skill / pattern; the VM is the foundation that
makes the loop fast and safe.

| # | Requirement                                  | How it is delivered                                                                                                                                                                                                          |
|---|----------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1 | Less human involvement                       | `everything-claude-code:autonomous-agent-harness` · `autonomous-loops` · `continuous-agent-loop` · `multi-plan` → `multi-execute` → `council` · `quality-gate` / `verification-loop` / `gateguard` for stage gates                   |
| 2 | Design aesthetic aligned with Open Design    | `mcp__open-design__*` tools (served by local daemon) pull the live design project as the spec · `mcp__plugin_lazyweb_lazyweb__lazyweb_search` adds real product references · `everything-claude-code:frontend-design` / `ui-ux-pro-max` / `design-system` |
| 3 | Catch what self-test misses                  | `verify` skill runs the real app in a real browser · `everything-claude-code:e2e-runner` walks critical user flows · `council` runs N independent agents with different lenses (correctness / visual / a11y / boundary / security) · `mcp__plugin_everything-claude-code_playwright__browser_take_screenshot` for visual diff against Open Design references |
| 4 | Isolated VM, no impact on the host           | OrbStack Ubuntu 24.04 VM (`atelier`) · every dev tool lives inside · `bin/devbox reset` rebuilds the VM from scratch in ~5 min · the host stays inert: no packages, no shell rc edits, no config files touched                            |

## File layout

```
.
├── CLAUDE.md                  # instructions for Claude Code in this project
├── CLAUDE.zh-CN.md            # 同上，中文版
├── README.md                  # this file (English)
├── README.zh-CN.md            # 中文版
├── CONTRIBUTING.md            # how to file issues / send PRs (EN + 中文)
├── LICENSE                    # MIT
├── Makefile                   # make setup / doctor / reset / passthrough / shell
├── .gitignore
├── .claude/
│   └── settings.json          # project-level sandbox config (allow list, yolo backstop deny)
├── .mcp.json                  # open-design MCP bridge config (consumed by CC inside the VM)
├── docs/
│   └── design.md              # why this project exists
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
