---
name: atelier
description: >
  Route dev commands (build, test, install, run server, lint, format, browser automation)
  into an isolated OrbStack Linux VM via `bin/devbox run`. The host Mac has no toolchain —
  Node, Python, Go, Rust, pnpm, uv, cargo, gh, Playwright all live in the VM.
  Use when the user says: "跑测试", "构建", "装依赖", "启动服务", "在沙箱里跑",
  "run tests", "build", "install dependencies", "start server", "run in sandbox",
  "lint", "format", or any phrase that implies executing code, not just reading it.
  Do NOT use for: reading files, editing files, git status/diff/commit/log — those
  run fine on the host.
---

# atelier — VM sandbox routing

The host Mac is a thin client. **All execution goes through the VM.**

## When to route to the VM

Any command that requires a toolchain or runtime:

| Route to VM (`bin/devbox run ...`) | Stay on host |
|---|---|
| `pnpm test` / `pnpm build` / `pnpm install` | `git status` / `git diff` / `git commit` |
| `npm run dev` / `npm run build` | Read / Edit / Write files |
| `python -m pytest` / `pip install` / `uv sync` | `grep` / `find` / `ls` |
| `cargo build` / `cargo test` | Glob / Grep tool |
| `go test ./...` / `go build` | |
| `eslint` / `prettier` / `tsc` | |
| `playwright test` / browser automation | |
| `curl` / `wget` / network calls | |
| Any long-running server | |

## How to run

```bash
bin/devbox run <command>
```

Examples:

```bash
bin/devbox run pnpm test
bin/devbox run pnpm build
bin/devbox run python -m pytest
bin/devbox run cargo build --release
bin/devbox run go test ./...
bin/devbox run npm run dev
```

For interactive shell access:

```bash
bin/devbox shell
```

## File access

Project files live on the host and are auto-shared into the VM:

- Host: `/Users/<you>/Code/crack/<project>/`
- VM: `/mnt/mac/Users/<you>/Code/crack/<project>/`

Same bytes, same git state. Edit on either side. The VM borrows the mount for execution.

## Health check & recovery

```bash
bin/devbox doctor       # verify VM, mount, tokens
bin/devbox provision    # re-run setup (idempotent)
bin/devbox reset        # DESTRUCTIVE — delete + recreate VM (~5 min)
```

The VM is long-lived — keep using it across sessions. If the environment gets
corrupted, `bin/devbox reset` rebuilds from scratch in ~5 minutes. Host files
are untouched.

## MCP alternative

If your runtime supports MCP, call these tools instead of shelling out:

| MCP tool | Equivalent |
|---|---|
| `mcp__atelier__run({"cmd": "pnpm test"})` | `bin/devbox run pnpm test` |
| `mcp__atelier__status({})` | `bin/devbox status` |
| `mcp__atelier__doctor({})` | `bin/devbox doctor` |

## Rules

1. **Never run build/test/install on the host** — the toolchain isn't there.
2. **Tokens stay in the VM** — never log `ANTHROPIC_API_KEY`, `GITHUB_TOKEN`, etc.
3. **Don't store state outside the project tree** — anything in the VM's `~` is
   lost on `bin/devbox reset`.
