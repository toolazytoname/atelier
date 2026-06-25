# CLAUDE.md — atelier dev sandbox

## What this project is

A self-contained, **isolated Linux dev sandbox** for building whatever the
user wants. The whole workflow — code, builds, tests, dependencies — lives
inside an OrbStack Linux VM called `atelier`. The host Mac only runs
Claude Code itself.

## The yolo-safety model

**Yolo with a bounded blast radius.** The architecture is the wall; the
deny list is just the backstop for `--dangerously-skip-permissions`.

- **The wall** — the host is inert. Every mutating op routes through
  `bin/devbox run` into the VM. `.claude/settings.json` allow-lists only
  the sandbox driver (`bin/devbox*`, `setup/*`, `make*`, `git*`, `orb*`)
  and observation/CC tools (`Read`, `Glob`, `Grep`, `Agent`, …).
  Anything else, the user grants explicitly — the host does not grow
  tools or config over time.
- **The backstop** — under yolo, only the deny list bites, and only on
  the unrecoverable: `rm -rf /`/`~`, fork bombs, `sudo`/`doas`,
  `curl|bash`/`eval`/`exec`, and writes to credential stores
  (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `~/.docker`). Shell rc
  files and host config dirs are deliberately *not* denied — if a
  feature genuinely needs them, the user adds to the allow list rather
  than relaxing the deny list.
- **The wall only covers this project.** A project `settings.json` only
  applies inside this directory; `cd` elsewhere runs CC under the host's
  global settings. Stay in the project to keep the wall up.

Full threat model and the three layers: [`docs/security-model.md`](docs/security-model.md).

## Default workflow (yolo harness)

For any **non-trivial feature work** (more than 1 file / touches
architecture / new API / any UI), the default loop is:

1. **Plan (this CC, fast)** — decompose the request into a small
   set of tasks; identify non-negotiable acceptance criteria.
2. **Generate (isolated agent)** — spawn a subagent (or
   `bin/devbox run claude -p "..."`) to write the code. **Own
   context window, own session.**
3. **Test + Review (parallel evaluators)** — spawn N independent
   reviewers, each its own subagent: correctness, security, a11y,
   visual, boundary. Run the project's own test suite. Each
   reviewer scores independently, no shared context.
4. **Gate (decision)** — pass if all `score ≥ 0.8` AND no blockers
   AND tests green. Persist the score card as a checkpoint.
5. **Commit or iterate** — if pass: commit + push + open PR with
   score cards attached. If fail: feed the score card back to
   the generator, iterate.
6. **Escalate** — if `MAX_ITERATIONS` (default 5) hit, stop and
   ask the human. The spec is probably wrong.

### Isolation: the load-bearing property

**The generator and the reviewers MUST be separate agents.**
Three mechanisms, in increasing weight:

- **Agent tool** — spawn a subagent. It gets a fresh context
  window, returns only a summary.
- **`bin/devbox run claude ...`** — spawn a full CC process
  inside the VM. Own `/proc/<pid>`, own `~/.claude/`, independent
  toolchain access.
- **`council` skill** — N reviewers in one tool call, each
  subagent.

**Never share context between generator and reviewer.** The
reviewer's transcript is megabytes; merging it into the
generator's context causes context rot. The generator should
only see the score card, not the reviewer's reasoning.

### Hard rules (no exceptions)

1. **Never review your own code.** Developer and reviewer are
   always separate agents.
2. **Never bypass a failed gate** "to save time." That's how
   engineering rot starts. The gate decides, period.
3. **Never let the generator see the reviewer's full
   transcript** — only the score card. Otherwise the generator
   optimizes for pleasing the reviewer, not for being correct.
4. **Ask the human only at the gate failure or the stuck
   escalation.** Don't ping for individual file reviews.

### When to use it

Use the harness loop when "would I be sad if I had to revert
this in production?" is yes. For one-line typos, doc tweaks, or
trivial config changes, just commit.

For the full design (score card format, stuck detection, budget
guards, parallel reviewer patterns), see
[`docs/workflow.md`](docs/workflow.md).

## Where things live

**Everything runs inside the VM.** The host is a thin client: a
terminal, a browser, and OrbStack.

- **Host (Mac)**: terminal display, browser tab pointing at
  `http://localhost:7456` (the open-design web UI via SSH tunnel).
  Nothing else. No Node, no MCPs, no dev tools — those are all in the VM.
- **VM (atelier)**:
  - Claude Code (run via `bin/devbox claude`)
  - open-design daemon (HTTP at `127.0.0.1:7456`, MCP at `od mcp`)
  - open-design MCP bridge (stdio; configured via `.mcp.json` in the project)
  - All dev tools: Node 24 / pnpm / Python 3.12 / Go 1.23 / Rust 1.96 /
    uv / gh / starship
  - Network MCPs: `playwright`, `context7`, `exa`, `github`,
    `lazyweb`, `sequential-thinking`
- **Project files** (`/Users/you/Code/crack/atelier/`) live on the host,
  mounted at `/mnt/mac/Users/you/Code/crack/atelier/` inside the VM via
  OrbStack's auto-share. Edit either side; execution stays in the VM.

## Daily loop

```bash
# one-time
brew install --cask orbstack                            # if missing
./setup/provision.sh                                    # inside the VM (~5 min, idempotent)
./setup/host-passthrough.sh                             # forward env (ANTHROPIC_*, GITHUB_TOKEN)

# every session
bin/devbox claude                                       # Claude Code, inside the VM (run with --dangerously-skip-permissions for yolo)
bin/devbox gui                                          # open-design web UI tunneled to host browser
bin/devbox shell                                        # or just an interactive shell
bin/devbox run pnpm test                                # run any command inside the VM
bin/devbox doctor                                       # health check
bin/devbox reset                                        # nuke + recreate (DESTRUCTIVE)
```

## Rules of engagement (for me, Claude Code)

1. **Run heavy work in the VM**, not on the host. Use `bin/devbox run <cmd>`
   or `orb run atelier -- <cmd>`. The host filesystem is mounted
   read-write at `/mnt/mac` inside the VM — edit either side, but the
   sandboxed execution path stays inside the VM.
2. **Design aesthetic comes from Open Design.** Before designing any UI,
   pull the active project via
   `mcp__open-design__get_artifact` and treat the result as the spec.
   Cross-reference with `mcp__plugin_lazyweb_lazyweb__lazyweb_search` for
   real product references. Run the work through the
   `everything-claude-code:frontend-design` and `ui-ux-pro-max` skills.
3. **Multi-perspective verification is mandatory.** After writing code,
   don't trust the obvious path. Always:
   - Run the app via the `verify` skill (real browser, real interactions).
   - Use `everything-claude-code:e2e-runner` for critical user flows.
   - Spin up `everything-claude-code:council` with N independent agents
     using different lenses (correctness / visual / a11y / boundary / security).
   - Screenshot key views via `mcp__plugin_everything-claude-code_playwright__browser_take_screenshot`
     and visually compare to Open Design references.
4. **Harness aggressively.** For non-trivial features, orchestrate with
   `everything-claude-code:autonomous-agent-harness` /
   `autonomous-loops` / `continuous-agent-loop` and let the multi-agent
   council debate before the user is asked. The user wants to be the
   *arbiter*, not the *operator*. See **"Default workflow (yolo
   harness)"** above for the canonical loop, the isolation
   mechanisms, and the hard rules.
5. **Never silently swallow errors.** All host-only MCPs that need to be
   available inside the VM must be explicitly tunneled (none today; if
   needed, document the pattern in `setup/`).
6. **Treat the VM as disposable.** `bin/devbox reset` recreates it from
   zero. Anything not under source control or in `/mnt/mac` is lost.

## What runs on the host vs. the VM

Short version: the host runs the terminal, the browser, OrbStack, and
`git`/file reads; **everything else runs in the VM** (Claude Code,
open-design daemon + MCP, all language toolchains, all network MCPs).
The full per-component table is in
[`docs/architecture.md`](docs/architecture.md).

## Troubleshooting

See [FAQ § Troubleshooting](FAQ.md#troubleshooting) for the symptom →
fix table. The universal recovery is `bin/devbox reset` (DESTRUCTIVE —
rebuilds the VM from scratch; the host filesystem is untouched).
