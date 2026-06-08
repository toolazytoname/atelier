# Design rationale

This document explains the *why* behind `atelier`. If you want to extend or
fork the project, read this first — it tells you which knobs are load-bearing
and which are aesthetic.

## The problem

Working with Claude Code on a single Mac hits four walls:

1. **The host is shared.** Every `npm install` mutates the host's global state.
   A bad script can trash your dotfiles, your SSH agent, or your `~/.zshrc`.
2. **The design loop is single-perspective.** A single agent's "looks good to
   me" misses obvious problems. The cost of catching issues late is high.
3. **The user is the operator.** Every dev workflow tool wants the user to
   make decisions, run commands, copy errors, and steer. The user wanted to
   be the *arbiter*, not the *operator*.
4. **Network reality bites.** Anyone behind a slow or rate-limited egress
   (CN, corporate, mobile) gets 5-minute `apt-get install` for things that
   should take 5 seconds.

This project doesn't try to solve all of agent engineering. It solves the
"how do I let Claude Code do real work without me babysitting it, in a way
that's safe, looks good, and runs in the network I'm actually on" question.

## The four pillars

Each pillar maps to a concrete tool or pattern that already exists in the
Claude Code environment. The sandbox just makes them composable.

### 1. Less human involvement

**Mechanism:** `everything-claude-code:autonomous-agent-harness` /
`autonomous-loops` / `continuous-agent-loop` for long-running work;
`multi-plan` → `multi-execute` → `multi-workflow` → `council` for review;
`quality-gate` / `verification-loop` / `gateguard` as stage gates.

**What it looks like in practice:** A non-trivial feature request lands. The
harness spawns a planner, an executor, and a three-agent council. The
council reviews the executor's output on three lenses (correctness, visual,
a11y). The user sees the council's verdict and either approves or asks for
one specific change — they don't debug.

**Why this is a pillar, not just a feature:** Without orchestration, the
single biggest cost of using AI for development is *attention switching*.
The user is constantly context-switching between "watch the agent", "fix
what it broke", "explain to it what I actually want". The harness pushes
all of that out of the user's loop.

**What to do if you don't have these skills:** Start with one skill —
`everything-claude-code:plan` — and use it for every non-trivial task. The
habit is more important than the tool.

### 2. Design aesthetic aligned with Open Design

**Mechanism:** `mcp__open-design__get_artifact` pulls the user's live
design project as the spec. `mcp__plugin_lazyweb_lazyweb__lazyweb_search`
adds real product references. `everything-claude-code:frontend-design` /
`ui-ux-pro-max` / `design-system` are the implementation skills.

**What it looks like in practice:** Before any UI work, the agent runs
`mcp__open-design__get_artifact` and reads the returned design tokens,
component library, and reference screens. It then writes CSS/JSX that
matches. If it needs a reference for a screen type it hasn't seen (e.g.
"a pricing page with annual/monthly toggle"), it asks
`mcp__plugin_lazyweb_lazyweb__lazyweb_search` for the best three real
products in that space and uses their patterns as input.

**Why this is a pillar, not just a feature:** A model's design taste out of
the box is, charitably, "fine". It converges to whatever the most common
Stack Overflow Bootstrap snippet looks like. The user's bar is much higher
than that, and a spec from Open Design is the only way to meet it.

**What to do if you don't have Open Design:** Pick any source of design
truth — Figma, a Tailwind config your team uses, screenshots of a
reference app. The principle is: the agent should never invent the visual
language; it should read one.

### 3. Multi-perspective verification

**Mechanism:** `verify` skill (real browser, real interactions);
`everything-claude-code:e2e-runner` (Playwright walks critical paths);
`council` (N independent reviewers on different concerns);
`mcp__plugin_everything-claude-code_playwright__browser_take_screenshot`
for visual diff.

**What it looks like in practice:** The agent writes the code. Then it
must pass three gates before reporting "done":
1. **Functional:** `verify` launches the app in a real browser, exercises
   the new feature, checks that nothing else broke.
2. **Path coverage:** `e2e-runner` walks the user's day-one and day-N
   journeys, asserts nothing regressed.
3. **Lens review:** `council` spawns three agents — one checks correctness
   (does the code do what it claims?), one checks visual (does it match the
   Open Design spec?), one checks a11y (does it work for keyboard and
   screen reader users?). Majority vote to accept.

**Why this is a pillar, not just a feature:** A single agent's self-test
*always* passes. That's not because the agent is dishonest — it's because
the agent's notion of "this works" is "I wrote it, the syntax is valid,
the unit tests pass". The bugs that survive are exactly the ones that need
a different perspective: someone who didn't write the code, who is
imagining a different user, who is reading the design spec, not the code.

**What to do if you don't have all these tools:** Even one external
reviewer agent helps. The key is: review must come from something
*different* from the code-writing agent, on a *different* concern.

### 4. Isolated VM

**Mechanism:** OrbStack Linux VM (`atelier`) with host filesystem
mounted at `/mnt/mac`. `bin/devbox` wrapper keeps every command sandboxed.
`bin/devbox reset` rebuilds the VM in under 10 minutes.

**What it looks like in practice:** The agent's `pnpm install` doesn't
write to the host's global node_modules. Its `apt-get install` doesn't
touch macOS. Its `rm -rf /*` (which it will sometimes do) destroys only
the VM. The user can walk away from the agent for an hour and come back
to a system that is either "feature shipped" or "VM is broken; run
`make reset`". The host is *never* the casualty.

**Why this is a pillar, not just a feature:** Trust. The whole rest of
the system (long-running agents, autonomous loops, "let it just do the
work") requires the user to trust that things won't go sideways. A
disposable VM is the cheapest way to give that trust a physical bound.

**What to do if you don't have OrbStack:** Any disposable Linux VM works
(Multipass, Vagrant, Lima, UTM, even a Docker-in-Docker setup with
caveats). The point is: the blast radius is bounded, and reset is cheap.

## Why these four, not others

- **Why not "faster model"?** Cost: marginal. Effect: marginal. The
  bottleneck is not token throughput.
- **Why not "better memory"?** Memory helps within a session, but most
  cross-session context is project structure, not the agent's opinions.
  Pinning the design spec and a verification loop does more.
- **Why not "more context"?** A longer context window is wasted if the
  context is full of irrelevant past attempts. The four pillars
  *constrain* what goes into context: design spec, current task,
  verification result, environment state.
- **Why not "fine-tuned for code"?** Same reason as model choice.
  Bottleneck isn't the model.

The four pillars address the four real costs: **time spent operating,
quality of output, cost of catching bugs late, and trust.**

## Mirror selection

`provision.sh` defaults to mainland-China mirrors because that's where the
project originated, and the international CDNs rate-limit CN egress
aggressively. The `CN_MIRROR` env var switches to international sources.

We deliberately *don't* mirror things that aren't slow:
- Go's `dl.google.com` is fast from both egresses (~20 MB/s).
- Rust's `static.rust-lang.org` works from both.
- Docker's `download.docker.com` is fine for the small CLI package.

Mirroring those would just add a layer of debugging surface for no speed
gain. The rule of thumb: **only mirror the thing that actually hurts.**

## Naming

`atelier` is French for *workshop*, and the Chinese mirror is *工坊* (gōngfāng).
The name captures the whole idea in two languages: a place where you make
things carefully, by hand or with tools, and where the workspace is set up
deliberately rather than improvised. The four pillars — autonomous harness,
design spec, multi-perspective verification, isolated VM — are the workbench,
the blueprint, the QC bench, and the blast-door of the workshop.

We considered and rejected:

- **Anvil** (铁砧) — short and iconic, but the Chinese "砧" is obscure.
- **Crucible** (坩埚) — captures the verification pillar, but reads as
  a single feature, not a whole workflow.
- **Foundry** (铸造厂) — collides with the LLVM project.
- **Loop** / **Yard** / **Blastbox** — too generic, too informal, or too
  much of a geek joke respectively.

The default OrbStack VM is also called `atelier` (override with `make setup
VM=other-name` if you have a collision). The `bin/devbox` wrapper is a
generic name — it works for any OrbStack VM, not just this project's.

Feel free to rename for your fork; the patterns travel.

## What this project explicitly is NOT

- A complete dev environment replacement. The host Mac is still where you
  read email and edit markdown.
- A model-specific tool. The harness / council / verify patterns work with
  any agent that can call tools.
- An attempt at "fully autonomous software engineering". The user is
  still the arbiter. The pillars reduce the *operator* load; they don't
  remove the need for someone to say "yes, ship it".
