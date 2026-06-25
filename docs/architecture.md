# Architecture

> Read this if you want to extend or modify atelier. The README gives
> the *what*; this doc gives the *how*.

## Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 1: Display                                                    │
│  ───────────────                                                     │
│  macOS Terminal (you type here)                                      │
│  macOS Browser (http://localhost:7456 → open-design web UI)          │
│  Nothing else runs on the host.                                      │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                │  SSH / orbctl stdio
                                ↓
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 2: Sandbox driver (the only thing on the host)                │
│  ───────────────                                                     │
│  bin/devbox — bash script, ~250 lines                                │
│    • run     → orbctl run -m atelier -- <cmd>                        │
│    • shell   → orbctl shell atelier                                  │
│    • claude  → orbctl run ... bash -lc '...' (wraps CC inside VM)    │
│    • gui     → SSH -L 7456:127.0.0.1:7456 atelier@orb                │
│    • reset   → orbctl delete + create + provision                    │
│    • doctor  → orbctl info + check mounts + env passthrough          │
│                                                                      │
│  Allow-listed in .claude/settings.json. Nothing else.                │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                │  OrbStack auto-share
                                ↓
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 3: VM (atelier)                                               │
│  ───────────────                                                     │
│  Ubuntu 24.04, 4 CPU / 8G RAM / 64G disk                             │
│  Provisioned once by setup/provision.sh (~5 min, idempotent)         │
│                                                                      │
│  • Claude Code  (run via bin/devbox claude, yolo-friendly)           │
│  • open-design daemon (HTTP 127.0.0.1:7456, stdio MCP)               │
│  • Node 24 / pnpm / Python 3.12 / uv / Go 1.23 / Rust 1.96 / gh     │
│  • starship / zsh / fzf / ripgrep / fd / bat / lazygit               │
│  • Network MCPs: lazyweb, context7, exa, github,                     │
│                  sequential-thinking, playwright                     │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                │  Host filesystem auto-shared
                                ↓
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 4: Project files                                              │
│  ───────────────                                                     │
│  /Users/you/Code/crack/<project>  (host)                            │
│  ↕ OrbStack auto-share                                               │
│  /mnt/mac/Users/you/Code/crack/<project>  (VM)                      │
│                                                                      │
│  Edit either side. Identical bytes. Survives bin/devbox reset.        │
└──────────────────────────────────────────────────────────────────────┘
```

## Data flow

### A command on the host runs in the VM

```
$ bin/devbox run pnpm test
        │
        │  (1) bin/devbox parses argv
        ↓
ensure_vm   (2) — start atelier if not running
        │
        ↓
orbctl run -m atelier -- pnpm test   (3) — exec in VM shell
        │
        ↓
VM bash:  PATH=~/.local/bin:/usr/local/node-v24.11.0/bin:$PATH
          pnpm test                       (4) — runs against /mnt/mac/...
        │
        ↓
stdout/stderr piped back to host terminal via orbctl
        │
        ↓
$  (you see the output, exit code propagated)
```

### Claude Code in the VM, MCP in the VM, browser on the host

```
$ bin/devbox claude
        │
        ↓
ensure_vm → start atelier
        │
        ↓
od start &   (daemon binds 127.0.0.1:7456 in VM)
        │
        ↓
claude   (5) — discovers .mcp.json in cwd → loads open-design MCP
        │       the MCP is a stdio bridge, so no port forwarding needed
        │       for the agent ↔ MCP link
        ↓
User types: "show me the design system tokens"
        │
        ↓
CC → mcp__open-design__get_artifact → daemon → response → CC
        │
        ↓
User wants to see the visual UI:
$ bin/devbox gui   (separate terminal)
        │
        ↓
SSH -L 7456:127.0.0.1:7456 atelier@orb   (6) — tunnel browser → daemon
        │
        ↓
Browser tab at http://localhost:7456 → reaches daemon's 127.0.0.1:7456
```

The 6 step numbers above correspond to comments in
[`bin/devbox`](../bin/devbox) `cmd_claude()` and `cmd_gui()` if you
want to trace the code.

## Why each piece exists

### `bin/devbox` is a thin shell script

It's pure bash, no Node dependency, no compilation, no installation
beyond `chmod +x` (or `ln -sf` into `~/bin`). It exists so the host
shell has **exactly one** thing to know about: this binary routes
commands into the VM. Everything else in the project is either
observation (`Read`, `Glob`, `Grep`) or a file edit.

### The VM is Ubuntu 24.04

LTS until 2029, well-supported by Node / Python / Go / Rust toolchains,
and the OrbStack image boots in under 4 seconds. We don't use Alpine
(musl libc breaks too many prebuilt wheels) and we don't use Arch
(rolling release breaks reproducibility).

### `setup/provision.sh` is one big idempotent script

We chose "one script, runs end-to-end, idempotent" over a more
modular config-management approach (Ansible / Chef / Nix) because:

- The reprovision target is **a fresh empty VM** — there's no
  "selectively update" workflow
- The script is 300 lines and readable end-to-end in 5 minutes
- Re-running it is safe (apt reinstall is a no-op, `pip install -U`
  is idempotent for version-pinned packages)
- A maintainer can bisect provisioning regressions with `git log` and
  `git checkout` + `make reset`

### The allow-list is tiny on purpose

`.claude/settings.json` allows **only** what the architecture needs:

- `bin/devbox*` — the only host-side mutating op
- `setup/*` — provisioning (run by the user, not CC)
- `make*`, `git*` — pure-file ops
- `orb*`, `orbctl*` — VM control
- `Read`, `Glob`, `Grep`, `WebFetch`, `WebSearch` — observation
- Claude Code built-ins (`TodoWrite`, `Task`, `Agent`, ...)

Anything else — including `Write` / `Edit` outside the project tree —
needs explicit grant. This is what makes `--dangerously-skip-permissions`
safe in the yolo harness loop.

### The deny list is the last-resort backstop

It contains only the commands whose consequences don't recover even
if caught in seconds:

- `rm -rf /`, `rm -rf ~`, `rm -rf $HOME/Code/crack/!(atelier)/**`
- `sudo *`, `doas *`
- `curl *|bash`, `wget *|bash`, `eval *`, `exec *`
- `Write` / `Edit` to `~/.ssh/**`, `~/.aws/**`, `~/.gnupg/**`,
  `~/.kube/**`, `~/.docker/**`

Shell rc files and host config dirs are **deliberately not in the
deny list** — the architecture contract is that CC writes only to
the project tree. If a future feature genuinely needs to touch a
host config, the user adds the path to the allow list, not the deny
list. The deny list is for the "unrecoverable mistake" class, not
"things we don't want right now".

## Where state lives

| What | Where | Survives `bin/devbox reset`? |
|------|-------|------------------------------|
| Project source code | `/Users/you/Code/crack/<project>` (host) ↔ `/mnt/mac/...` (VM) | ✅ |
| Project `.env`, `.git/`, `node_modules/`, `.venv/`, `target/` | same as above | ✅ |
| Anthropic token | `/etc/environment.d/host-proxy.conf` (VM), set by `setup/host-passthrough.sh` | ❌ (re-run passthrough) |
| Claude Code session history | `~/.claude/session-data/` (VM) | ❌ |
| open-design design project | `~/.local/share/open-design/` (VM) | ❌ (re-import spec) |
| Open-design daemon PID / logs | `~/.local/share/open-design/daemon.log` (VM) | ❌ |
| Global npm packages | `~/.npm-global/` (VM) | ❌ |
| Rust crates cache | `~/.cargo/` (VM) | ❌ |
| Go module cache | `~/go/pkg/` (VM) | ❌ |

The split: **the project tree is durable; everything else in the VM
is disposable.** If you find yourself storing something important
inside the VM, move it into the project tree (committed or
gitignored as appropriate) or into `setup/provision.sh` so it's
recreated on provision.

## Reset and the contract

`bin/devbox reset`:

1. Asks the user to type `yes` (no `--force`)
2. `orbctl delete atelier --force` (DESTRUCTIVE — drops the VM image)
3. `orbctl create ...` (recreates from `ubuntu:24.04` image, ~30s)
4. Runs `setup/provision.sh` (~5 min)

The host filesystem is **never** touched by `bin/devbox reset`. The
project tree on the host is the source of truth; the VM is rebuilt
from the same `setup/provision.sh` anyone would use.

## Extending the architecture

Common forks / extensions:

| Want to… | Where to look |
|----------|---------------|
| Add a new subcommand to `bin/devbox` | `bin/devbox` — add a `cmd_<name>()` and a dispatch case |
| Add a new tool to the VM | `setup/provision.sh` — add an apt line, or a new `curl \| tar` block, or a new `pip install` |
| Change the VM size | `bin/devbox` `VM_*` defaults, or `make setup CPUS=8 MEMORY=16G DISK=128G` |
| Use a different distro | `bin/devbox` `VM_DISTRO` (default `ubuntu:24.04`) — must be a standard OrbStack image |
| Replace OrbStack with Lima / Docker | Rewrite `bin/devbox`. The 8 subcommands map to 8 small functions; this is a day of work, not a week |
| Add a new MCP server | `.mcp.json` — point at the binary, restart CC |

For the "multi-agent harness" workflow that sits on top of this
sandbox, see [`docs/workflow.md`](workflow.md). For the security
model, see [`docs/security-model.md`](security-model.md). For why
we picked OrbStack over alternatives, see
[`docs/comparison.md`](comparison.md).
