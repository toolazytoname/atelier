# AGENTS.md — for any AI coding agent working in or with atelier

> This document is the portable companion to the project's
> `CLAUDE.md`. If you're Claude Code, read `CLAUDE.md` first
> (it has richer context). If you're Hermes, Aider, Codex,
> Cline, Continue, Roo, or any other agent, **this is your
> entry point**. The skill-based workflows described in
> `CLAUDE.md` won't apply to you — use the principles here.

## 1. What atelier is

`atelier` (French: *workshop*) is a **disposable Linux dev
sandbox** that runs on macOS via OrbStack. The host Mac is
intentionally inert: it runs the AI agent itself, a terminal,
and a browser. **All heavy development work happens in an
Ubuntu 24.04 Linux VM called `atelier`.**

The only bridge between the host and the VM is a small bash
script: `bin/devbox` (in the project root).

```
┌─────────────────────┐         ┌──────────────────────────┐
│   Host (macOS)      │  orb    │   VM (atelier, Linux)    │
│ ─────────────────── │ ──────▶ │ ──────────────────────── │
│ • AI agent (you)    │  SSH    │ • Node 24 / pnpm         │
│ • Browser (display) │  tunnel │ • Python 3.12 / uv       │
│ • Terminal          │  /mnt   │ • Go 1.23 / Rust 1.96    │
│ • bin/devbox (only) │  mac    │ • All MCP servers        │
│                     │  share  │ • Playwright browser     │
└─────────────────────┘         └──────────────────────────┘

Project files:  host    /Users/you/Code/crack/<project>
                ↕  OrbStack auto-share
                VM      /mnt/mac/Users/you/Code/crack/<project>
```

## 2. The contract you must respect

### Rule 1: heavy work goes through `bin/devbox run`

| Operation | Run on host | Run in VM (`bin/devbox run ...`) |
|-----------|:-----------:|:-------------------------------:|
| Reading files | ✅ | (no benefit) |
| Editing project files | ✅ | (no benefit) |
| `git status` / `git diff` / `git commit` | ✅ | (no benefit) |
| `pnpm install` / `pnpm test` | ❌ | ✅ |
| `npm run build` | ❌ | ✅ |
| `python -m venv .venv` | ❌ | ✅ |
| `cargo build` / `go test` | ❌ | ✅ |
| Long-running servers | ❌ | ✅ |
| Network calls (curl, fetch) | ⚠️ prefer VM | ✅ |
| Browser automation | ❌ | ✅ |
| `sudo anything` | ❌ | ❌ (deny-listed) |
| `rm -rf /` / `rm -rf ~` | ❌ | ❌ (deny-listed) |
| `curl ... \| bash` | ❌ | ❌ (deny-listed) |

If the toolchain **only exists in the VM** (Node, pnpm, uv,
cargo, go, gh, MCP servers) — your
command is meaningless on the host. Route it.

### Rule 2: project files live on the host, accessible from the VM

The host's `/Users/you/Code/crack/<project>/` is auto-shared
into the VM as `/mnt/mac/Users/you/Code/crack/<project>/`.
You can edit either side. **Identical bytes. Identical git
state.** Edits from the VM appear on the host instantly (and
vice versa).

This means:

- You can `Read` a file from the host without booting the VM
- You can `Edit` a file on the host; the VM sees the change
- You can `Bash(bin/devbox run ls /mnt/mac/...)` to verify
  from the VM side
- **Do not** copy files into the VM (`/tmp`, `~`, `/usr/local`)
  if you want them to persist past `bin/devbox reset`

### Rule 3: the VM is disposable; the project is not

`bin/devbox reset` deletes the VM and recreates it from
`setup/provision.sh` in ~5 minutes. **Anything not in the
project tree is lost.** The only persistent state is:

- The project tree (host + VM via the auto-share)
- `~/.config/environment.d/host-proxy.conf` inside the VM (the
  passthrough'd tokens; re-run `./setup/host-passthrough.sh`
  to repopulate)
- OrbStack's VM image (the `.orbstack` directory on the host,
  which the user manages)

Everything else (`~/.cargo`, `~/go/pkg`, `node_modules/`,
`~/.bash_history`, `~/.claude/...`) is gone after reset.

### Rule 4: tokens stay in the VM

`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `GITHUB_TOKEN`
are forwarded from the host into
`~/.config/environment.d/host-proxy.conf` by
`./setup/host-passthrough.sh`. The agent (you) should not log
them, print them, write them to disk on the host, or include
them in any URL. If a log line accidentally contains a token,
**rotate the token immediately** and re-run the passthrough.

## 3. The complete `bin/devbox` command set

| Command | What it does |
|---------|--------------|
| `bin/devbox run <cmd...>` | run a single command in the VM |
| `bin/devbox shell` | open an interactive shell inside the VM |
| `bin/devbox claude [args]` | run Claude Code entirely inside the VM |
| `bin/devbox push <file> [dest]` | copy a file/folder from host into the VM's `~` |
| `bin/devbox pull <file> [dest]` | copy from VM `~` to the host |
| `bin/devbox status` | show VM state |
| `bin/devbox doctor` | health check (OrbStack / VM / mount / passthrough) |
| `bin/devbox provision` | re-run `setup/provision.sh` (idempotent) |
| `bin/devbox reset` | **DESTRUCTIVE** — delete + recreate the VM. Asks for `yes` |
| `bin/devbox help` | show the same help text |

Add `--json` to any subcommand (`bin/devbox --json run …`) for a
stable parseable envelope: `ok / exit_code / duration_ms / stdout /
stderr`.

**Prefer the MCP server over shelling out.** atelier ships
`bin/mcp-atelier.py`, a stdio MCP server (Python stdlib, zero deps,
already wired in `.mcp.json`) that wraps `bin/devbox --json` as tools.
If your runtime speaks MCP, call these instead of `Bash`:

| MCP tool | Replaces |
|---|---|
| `mcp__atelier__run({"cmd": "pnpm test"})` | `bin/devbox run pnpm test` |
| `mcp__atelier__run_claude({"prompt": "…"})` | `bin/devbox run claude -p "…"` |
| `mcp__atelier__status({})` / `doctor({})` / `version({})` | `bin/devbox <subcmd>` |

Each call returns `{content: [{type: "text", text: "<json>"}], isError}`;
parse `text` as the same envelope `--json` emits.

**Default invocation pattern:**

```bash
# "Run X inside the VM" → bin/devbox run X
bin/devbox run pnpm test
bin/devbox run npm run build
bin/devbox run python -m pytest
bin/devbox run cargo build --release
bin/devbox run go test ./...

# "Open the VM shell and let me poke around" → bin/devbox shell
bin/devbox shell
$ pwd    # /mnt/mac/Users/you/Code/crack/<project>
$ ls     # project files
$ exit   # back to host

# "I need a clean slate" → bin/devbox reset
bin/devbox reset   # types 'yes' when prompted
```

## 4. The yolo-harness workflow (multi-agent review)

atelier is designed for a specific kind of long-running,
review-heavy work: the **multi-agent harness loop**.

If you (the agent) are driving a non-trivial feature, the
recommended loop is:

```
   spec ──▶ Plan (you) ──▶ Generate (isolated subagent)
                                 │
                                 ▼
                       Test + Review (N parallel reviewers,
                                       each its own context)
                                 │
                                 ▼
                            Gate (score ≥ 0.8)
                                 │
                       pass ──▶ Commit / open PR
                       fail ──▶ Generate (with feedback, iter+1)
```

**Hard rules:**

1. **The generator and the reviewers MUST be separate
   agents.** Do not review code you just wrote. Use a
   subagent or a spawned CC process. The reviewer's context
   must not include your conversation history.
2. **The reviewers MUST NOT see each other's output.** Each
   reviewer scores independently. The orchestrator
   (you) collects the score cards.
3. **The gate MUST block commit if any score < 0.8 or any
   blocker is present.** No "I'll fix it later" — that's how
   engineering rot starts.
4. **The human is only in the loop at the gate failure or
   the stuck-detection escalation.** Don't ping for
   individual file reviews.

The full design is in [`docs/workflow.md`](docs/workflow.md).
The short version is: **separate contexts, parallel
reviewers, score card gate, no self-review.**

## 5. When to ask the user

Ask only when:

- The spec is ambiguous and you can't proceed without a
  choice
- The harness has failed `MAX_ITERATIONS` (default 5) and
  the score card shows the same blocker across all iters
  (the spec is probably wrong, not the code)
- A command failed with a deny-list hit (don't try to
  bypass; tell the user)
- You're about to run `bin/devbox reset` (DESTRUCTIVE)
- You need to install a new tool that isn't in
  `setup/provision.sh` (user must approve adding it)

**Don't** ask for:

- "Should I run this in the VM or the host?" — assume VM
  unless the operation is observation-only
- "Is the build green?" — run the build and see
- "Should I commit?" — the gate decides; if it passes,
  commit
- "What's the next step?" — read the spec, follow it

## 6. Failure modes and their fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `command not found` on host | toolchain in VM, not host | `bin/devbox run <cmd>` |
| `VM atelier is not running` | VM stopped | `bin/devbox run ...` (auto-starts) or `orb start atelier` |
| `permission denied: ~/.ssh` | deny list hit | correct behaviour — don't bypass |
| token not seen in VM | passthrough not run / token rotated | `./setup/host-passthrough.sh` |
| VM boots but tools missing | provision didn't finish | `bin/devbox provision` |
| `bin/devbox: command not found` | host PATH | `export PATH="/Users/you/Code/crack/claude/atelier/bin:$PATH"` or `make install-bin` |

## 7. Where to learn more

These docs aren't required reading — but if you need depth on a
specific question, point at these rather than re-deriving:

| Question | Doc |
|----------|-----|
| How is the host / VM split wired? Why these specific pieces? | [`docs/architecture.md`](docs/architecture.md) |
| What's the yolo-safety threat model? What does the wall guarantee? | [`docs/security-model.md`](docs/security-model.md) |
| Why OrbStack over Docker Desktop / Lima / Vagrant / Multipass? | [`docs/comparison.md`](docs/comparison.md) |
| The harness loop in detail (stages, isolation, score card)? | [`docs/workflow.md`](docs/workflow.md) |
| What problem does this project solve, and why these choices? | [`docs/design.md`](docs/design.md) |

If you're Claude Code, prefer `CLAUDE.md` — it has project-specific
conventions and triggers the yolo-harness loop on the right natural
language cues.

## 8. TL;DR

- **`bin/devbox run <cmd>` is the universal escape hatch** for
  any non-trivial work
- **The host is for reading, editing, and git**; the VM is for
  everything else
- **Generator and reviewer are separate agents** — never
  review your own code, never share contexts
- **Tokens stay in the VM** — never log them, never put them
  in URLs
- **Ask only at gates and on `bin/devbox reset`** — otherwise
  keep the loop running

If you only read one section, read this one. The rest is
reference.
